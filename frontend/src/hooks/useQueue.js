import { useState, useEffect, useCallback } from 'react'
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

  useEffect(() => {
    let mounted = true

    fetch()

    // Realtime: qualquer mudança em queue_entries ou appointments refaz a query
    const channel = supabase
      .channel('queue-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_entries' },  () => { if (mounted) fetch() })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },   () => { if (mounted) fetch() })
      .subscribe()

    return () => {
      mounted = false
      supabase.removeChannel(channel)
    }
  }, [fetch])

  return { entries, loading, error, refresh: fetch }
}
