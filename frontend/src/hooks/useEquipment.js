import { useState, useEffect, useCallback, useRef } from 'react'
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

  // Ref estável para o canal Realtime não ser recriado a cada mudança de params.
  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  // Nome único por instância evita conflito em múltiplas montagens.
  const channelName = useRef(`equipment-rt-${Math.random().toString(36).slice(2, 8)}`).current

  // Realtime: appointments/queue_entries mudam ao reaproveitamento → recalcula ocupação.
  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },   () => fetchRef.current?.())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_entries' }, () => fetchRef.current?.())
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { equipment, loading, error, refresh: fetch }
}
