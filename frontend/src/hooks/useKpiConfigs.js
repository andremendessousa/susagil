import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function useKpiConfigs() {
  const [configs, setConfigs] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    let mounted = true
    async function fetch() {
      setLoading(true)
      const { data, error: err } = await supabase
        .from('v_kpi_thresholds')
        .select('*')
        .order('ordem_exibicao')

      if (!mounted) return
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
    }
    fetch()
    return () => { mounted = false }
  }, [])

  return { configs, loading, error }
}
