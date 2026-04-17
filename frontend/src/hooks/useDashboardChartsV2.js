import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'

/**
 * Busca dados de fila e desempenho para a ZONA 6 do Dashboard.
 *
 * Cinco RPCs criadas na Migration 0008 (202604180001_rpc_fila_desempenho.sql).
 * Nenhuma falha individual derruba as demais — usa Promise.allSettled.
 *
 * @param {{ horizonte?: number, tipoAtendimento?: string|null }} params
 * @returns {{ charts2, loading2, error2, refresh2 }}
 *
 * charts2 = {
 *   fila_por_ubs:      Array<{ ubs_nome, municipio, total_aguardando, pct_do_total, espera_media_dias }>
 *   fila_por_clinica:  Array<{ equipamento_nome, unidade_nome, municipio, vagas_comprometidas, capacidade_periodo, pct_carga_fila }>
 *   desempenho_ubs:    Array<{ ubs_nome, municipio, absenteismo_pct, espera_media_dias, total_atendidos, score_composto }>
 *   tipos_exame:       Array<{ tipo_exame, total_solicitacoes, pct_do_total, espera_media_dias }>
 *   espera_municipio:  Array<{ municipio, total_pacientes, espera_media_dias, pct_absenteismo }>
 * }
 */
export function useDashboardChartsV2({ horizonte = 30, tipoAtendimento = null } = {}) {
  const [charts2, setCharts2] = useState({
    fila_por_ubs:     [],
    fila_por_clinica: [],
    desempenho_ubs:   [],
    tipos_exame:      [],
    espera_municipio: [],
  })
  const [loading2, setLoading2] = useState(true)
  const [error2, setError2]     = useState(null)

  const fetch = useCallback(async () => {
    setLoading2(true)
    setError2(null)

    const results = await Promise.allSettled([
      supabase.rpc('get_fila_por_ubs', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('get_fila_por_clinica', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('get_desempenho_por_ubs', {
        p_horizonte_dias: horizonte,
      }),
      supabase.rpc('get_tipos_exame_solicitados', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('get_espera_por_municipio', {
        p_horizonte_dias: horizonte,
      }),
    ])

    function safeData(result) {
      if (result.status === 'rejected') return []
      if (result.value?.error) return []
      return result.value?.data ?? []
    }

    const [filaUbs, fila_clinica, desemp, tipos, esperaMun] = results

    const erros = results
      .filter(r => r.status === 'rejected' || r.value?.error)
      .map(r => r.reason?.message ?? r.value?.error?.message ?? 'RPC error')

    setCharts2({
      fila_por_ubs:     safeData(filaUbs),
      fila_por_clinica: safeData(fila_clinica),
      desempenho_ubs:   safeData(desemp),
      tipos_exame:      safeData(tipos),
      espera_municipio: safeData(esperaMun),
    })

    setError2(erros.length > 0 ? erros.join(' | ') : null)
    setLoading2(false)
  }, [horizonte, tipoAtendimento])

  useEffect(() => { fetch() }, [fetch])

  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  const channelName = useRef(
    `dashboard-charts-v2-rt-${Math.random().toString(36).slice(2, 8)}`
  ).current

  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },  () => fetchRef.current?.())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_entries' }, () => fetchRef.current?.())
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { charts2, loading2, error2, refresh2: fetch }
}
