import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function useKpis() {
  const [kpis, setKpis] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    async function fetch() {
      setLoading(true)
      const { data, error } = await supabase
        .from('v_kpis')
        .select('*')
        .single()
      if (error) setError(error.message)
      else setKpis(data)
      setLoading(false)
    }
    fetch()
  }, [])

  return { kpis, loading, error }
}
