import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'

export function useEquipment({ horizonte = 30, tipoAtendimento = null } = {}) {
  const [equipment, setEquipment] = useState([])
  const [loading, setLoading]     = useState(true)
  const [error, setError]         = useState(null)

  const fetch = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const { data, error: err } = await supabase.rpc('fn_ocupacao_passada', {
        p_dias_atras:       horizonte,
        p_tipo_atendimento: tipoAtendimento,
      })
      if (err) throw err
      setEquipment(data ?? [])
    } catch (err) {
      setError(err.message || String(err))
      setEquipment([])
    } finally {
      setLoading(false)
    }
  }, [horizonte, tipoAtendimento])

  useEffect(() => { fetch() }, [fetch])

  return { equipment, loading, error, refresh: fetch }
}
