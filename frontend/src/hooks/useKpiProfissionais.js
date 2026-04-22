import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'

/**
 * Hook para os KPIs de BI da GestaoFilaProfissionaisPage.
 *
 * Chama a RPC `rpc_kpis_profissionais` e re-executa automaticamente
 * via Realtime sempre que `professional_confirmations` muda.
 *
 * Retorna:
 *   kpis.agendas_confirmadas_pct  — % de equipamentos confirmados na janela (number | null)
 *   kpis.equip_confirmaram        — count equipamentos confirmados (number)
 *   kpis.equip_com_agenda         — count equipamentos com agenda na janela (number)
 *   kpis.indisponibilidades_count — total de indisponibilidades nos últimos 30d (number)
 *   kpis.pacientes_protegidos     — count de deslocamentos potencialmente evitados (number)
 */
export function useKpiProfissionais({ horizonteHoras = 72 } = {}) {
  const [kpis, setKpis]       = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState(null)

  const fetch = useCallback(async () => {
    setLoading(true)
    const { data, error: err } = await supabase.rpc('rpc_kpis_profissionais', {
      p_horizonte_horas: horizonteHoras,
    })
    if (err) {
      setError(err.message)
      setKpis(null)
    } else {
      setKpis(data)
      setError(null)
    }
    setLoading(false)
  }, [horizonteHoras])

  useEffect(() => { fetch() }, [fetch])

  // Realtime: re-calcula KPIs quando confirmações mudam.
  // fetchRef mantém referência estável para o closure do canal.
  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  // Nome único por instância — evita conflito no React StrictMode (dupla montagem).
  const channelName = useRef(
    `kpis-profissionais-rt-${Math.random().toString(36).slice(2, 8)}`
  ).current

  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'professional_confirmations' },
        () => fetchRef.current?.()
      )
      .subscribe()
    return () => supabase.removeChannel(channel)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { kpis, loading, error, refetch: fetch }
}
