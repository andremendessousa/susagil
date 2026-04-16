import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'

export function useQueue({ horizonte = 30, filtroStatus = null, filtroTipo = null } = {}) {
  const [entries, setEntries]   = useState([])
  const [loading, setLoading]   = useState(true)
  const [error, setError]       = useState(null)

  const fetch = useCallback(async () => {
    setLoading(true)
    const dataLimite = new Date(Date.now() - horizonte * 86400000).toISOString()

    let query = supabase
      .from('v_dashboard_fila')
      .select('*')
      .gte('data_solicitacao_sisreg', dataLimite)
      .order('prioridade_codigo', { ascending: true })
      .order('data_solicitacao_sisreg', { ascending: true })

    if (filtroStatus) query = query.eq('status_local', filtroStatus)
    if (filtroTipo)   query = query.eq('tipo_atendimento', filtroTipo)

    const { data, error: err } = await query
    if (err) {
      setError(err.message)
      setEntries([])
    } else {
      // Dedup defensivo no cliente (redundância com DISTINCT ON da view)
      const unique = (data || []).filter(
        (e, i, self) => i === self.findIndex(x => x.id === e.id)
      )
      setEntries(unique)
      setError(null)
    }
    setLoading(false)
  }, [horizonte, filtroStatus, filtroTipo])

  useEffect(() => { fetch() }, [fetch])

  // Ref estável para o canal Realtime não ser recriado a cada mudança de filtro.
  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  // Nome único por instância evita conflito quando FilaPage e outras páginas
  // usam useQueue simultaneamente.
  const channelName = useRef(`queue-rt-${Math.random().toString(36).slice(2, 8)}`).current

  // Realtime: qualquer mudança em queue_entries ou appointments refaz a query.
  // Deps vazios: canal criado uma vez, nunca re-subscrito.
  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_entries' },  () => fetchRef.current?.())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },   () => fetchRef.current?.())
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { entries, loading, error, refresh: fetch }
}
