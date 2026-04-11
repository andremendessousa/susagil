import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'

function getDateISO(dias) {
  const d = new Date()
  d.setDate(d.getDate() - dias)
  return d.toISOString()
}

function trunc(str, n = 20) {
  if (!str) return '—'
  return str.length > n ? str.slice(0, n) + '…' : str
}

export function useDashboardCharts() {
  const [periodo, setPeriodo] = useState(30)
  const [charts, setCharts] = useState({ A: [], B: [], C: [], D: [] })
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetchCharts = useCallback(async () => {
    setLoading(true)
    setError(null)
    const dateISO = getDateISO(periodo)

    try {
      const [resA, resB, resC, resD] = await Promise.all([
        // Query A — exames por unidade executante
        supabase
          .from('appointments')
          .select('nome_unidade_executante, st_falta_registrada, status')
          .gte('created_at', dateISO)
          .not('nome_unidade_executante', 'is', null),

        // Query B — demanda por município
        supabase
          .from('queue_entries')
          .select('municipio_paciente, prioridade_codigo, status_local')
          .gte('created_at', dateISO),

        // Query C — ranking de UBS
        supabase
          .from('v_dashboard_fila')
          .select('ubs_origem, prioridade_codigo, status_local')
          .gte('created_at', dateISO),

        // Query D — absenteísmo por semana
        supabase
          .from('appointments')
          .select('scheduled_at, st_falta_registrada')
          .gte('scheduled_at', dateISO)
          .order('scheduled_at', { ascending: true }),
      ])

      const primeiroErro = [resA, resB, resC, resD].find(r => r.error)
      if (primeiroErro) {
        setError(primeiroErro.error.message)
        setLoading(false)
        return
      }

      // ── Chart A: por unidade executante ──────────────────────────────────────
      const mapA = {}
      for (const r of resA.data ?? []) {
        const nome = r.nome_unidade_executante
        if (!mapA[nome]) mapA[nome] = { nome, total: 0, faltas: 0, realizados: 0 }
        mapA[nome].total++
        if (Number(r.st_falta_registrada) === 1) mapA[nome].faltas++
        if (r.status === 'realizado') mapA[nome].realizados++
      }
      const chartA = Object.values(mapA)
        .sort((a, b) => b.total - a.total)
        .slice(0, 7)

      // ── Chart B: por município (top 10, invertido para barra horizontal) ─────
      const mapB = {}
      for (const r of resB.data ?? []) {
        const m = r.municipio_paciente || 'Desconhecido'
        if (!mapB[m]) mapB[m] = { municipio: trunc(m, 15), total: 0, urgentes: 0 }
        mapB[m].total++
        if (Number(r.prioridade_codigo) <= 2) mapB[m].urgentes++
      }
      const chartB = Object.values(mapB)
        .sort((a, b) => b.total - a.total)
        .slice(0, 10)
        .map(r => ({ ...r, rotina: r.total - r.urgentes }))
        .reverse()

      // ── Chart C: por UBS (top 8) ──────────────────────────────────────────────
      const mapC = {}
      for (const r of resC.data ?? []) {
        const ubs = r.ubs_origem || 'Desconhecida'
        if (!mapC[ubs]) mapC[ubs] = { ubs: trunc(ubs, 22), total: 0, urgentes: 0 }
        mapC[ubs].total++
        if (Number(r.prioridade_codigo) <= 2) mapC[ubs].urgentes++
      }
      const chartC = Object.values(mapC)
        .sort((a, b) => b.total - a.total)
        .slice(0, 8)
        .map(r => ({ ...r, rotina: r.total - r.urgentes }))
        .reverse()

      // ── Chart D: absenteísmo semanal ──────────────────────────────────────────
      const mapD = {}
      for (const r of resD.data ?? []) {
        if (!r.scheduled_at) continue
        const d = new Date(r.scheduled_at)
        const day = d.getDay()
        const diffToMon = day === 0 ? -6 : 1 - day
        d.setDate(d.getDate() + diffToMon)
        d.setHours(0, 0, 0, 0)
        const key = d.toISOString()
        if (!mapD[key]) mapD[key] = { _date: d, total: 0, faltas: 0 }
        mapD[key].total++
        if (Number(r.st_falta_registrada) === 1) mapD[key].faltas++
      }
      const chartD = Object.values(mapD)
        .sort((a, b) => a._date - b._date)
        .map(r => ({
          semana: r._date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }),
          total: r.total,
          faltas: r.faltas,
          taxa: r.total > 0 ? Math.round(r.faltas / r.total * 1000) / 10 : 0,
        }))

      setCharts({ A: chartA, B: chartB, C: chartC, D: chartD })
    } catch (e) {
      setError(e?.message ?? 'Erro desconhecido')
    } finally {
      setLoading(false)
    }
  }, [periodo])

  useEffect(() => { fetchCharts() }, [fetchCharts])

  return { charts, loading, error, refresh: fetchCharts, periodo, setPeriodo }
}
