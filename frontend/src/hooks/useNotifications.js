import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'

function calcularStats(notifications) {
  const hoje = new Date()
  hoje.setHours(0, 0, 0, 0)

  const total_hoje = notifications.filter(
    (n) => n.enviado_at && new Date(n.enviado_at) >= hoje
  ).length

  const finalizadas = notifications.filter(
    (n) => n.resposta_paciente === 'confirmou' || n.resposta_paciente === 'cancelou'
  )
  const confirmadas = finalizadas.filter((n) => n.resposta_paciente === 'confirmou').length
  const taxa_confirmacao =
    finalizadas.length > 0
      ? Math.round((confirmadas / finalizadas.length) * 100)
      : null

  const doisHorasAtras = new Date(Date.now() - 2 * 60 * 60 * 1000)
  const sem_resposta = notifications.filter(
    (n) =>
      !n.resposta_paciente &&
      n.enviado_at &&
      new Date(n.enviado_at) < doisHorasAtras
  ).length

  return { total_hoje, taxa_confirmacao, sem_resposta }
}

export function useNotifications() {
  const [notifications, setNotifications] = useState([])
  const [stats, setStats] = useState({ total_hoje: 0, taxa_confirmacao: null, sem_resposta: 0 })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetchNotifications = useCallback(async () => {
    setLoading(true)
    const { data, error: err } = await supabase
      .from('notification_log')
      .select(`
        id, patient_id, tipo, canal, enviado_at, respondido_at,
        resposta_paciente, entregue, erro, appointment_id,
        patients ( nome, telefone ),
        appointments (
          scheduled_at,
          equipment ( nome ),
          queue_entries ( ubs ( nome ) )
        )
      `)
      .order('enviado_at', { ascending: false })
      .limit(100)

    if (err) {
      setError(err.message)
    } else {
      // Normalizar para estrutura plana compatível com o prompt
      const normalized = (data || []).map((n) => ({
        ...n,
        paciente_nome:     n.patients?.nome       ?? '—',
        telefone:          n.patients?.telefone   ?? null,
        scheduled_at:      n.appointments?.scheduled_at ?? null,
        equipamento_nome:  n.appointments?.equipment?.nome ?? '—',
        ubs_nome:          n.appointments?.queue_entries?.ubs?.nome ?? null,
        appointment_id:    n.appointment_id ?? null,
      }))
      setNotifications(normalized)
      setStats(calcularStats(normalized))
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchNotifications()

    const channel = supabase
      .channel('notification-log-changes')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'notification_log',
      }, () => fetchNotifications())
      .subscribe()

    return () => supabase.removeChannel(channel)
  }, [fetchNotifications])

  return { notifications, stats, loading, error, refresh: fetchNotifications }
}
