import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function useEquipment() {
  const [equipment, setEquipment] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  async function fetch() {
    setLoading(true)
    const { data, error } = await supabase
      .from('v_ocupacao_equipamentos')
      .select('*')
      .order('pct_ocupacao', { ascending: false })

    if (error) setError(error.message)
    else setEquipment(data || [])
    setLoading(false)
  }

  useEffect(() => {
    fetch()

    const channel = supabase
      .channel('equipment-changes')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'appointments'
      }, () => fetch())
      .subscribe()

    return () => supabase.removeChannel(channel)
  }, [])

  return { equipment, loading, error, refresh: fetch }
}
