import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'

export function useKpiConfigs() {
  const [configs, setConfigs] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetch = useCallback(async () => {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('v_kpi_thresholds')
      .select('*')
      .order('ordem_exibicao')

    if (err) {
      setError(err.message)
      setConfigs(null)
    } else {
      // Indexa por chave para acesso O(1)
      const indexed = {}
      for (const row of data || []) {
        indexed[row.chave] = row
      }
      setConfigs(indexed)
      setError(null)
    }
    setLoading(false)
  }, [])

  useEffect(() => { fetch() }, [fetch])

  // Realtime: se um admin altera thresholds via ConfiguracoesPage,
  // o Dashboard reflete o novo status sem necessidade de reload.
  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  // Nome único por instância evita conflito no React StrictMode (dupla montagem).
  const channelName = useRef(`kpi-configs-rt-${Math.random().toString(36).slice(2, 8)}`).current

  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'kpi_configs' }, () => fetchRef.current?.())
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { configs, loading, error }
}
