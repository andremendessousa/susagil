import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function useQueue(filtroStatus = null) {
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  async function fetch() {
    setLoading(true)
    let query = supabase
      .from('v_dashboard_fila')
      .select('*')
      .order('prioridade_codigo', { ascending: true })

    if (filtroStatus) {
      query = query.eq('status_local', filtroStatus)
    }

    const { data, error } = await query
    if (error) setError(error.message)
    else setEntries(data || [])
    setLoading(false)
  }

  useEffect(() => {
    fetch()

    // Realtime: atualiza quando queue_entries mudar
    const channel = supabase
      .channel('queue-changes')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'queue_entries'
      }, () => fetch())
      .subscribe()

    return () => supabase.removeChannel(channel)
  }, [filtroStatus])

  return { entries, loading, error, refresh: fetch }
}
