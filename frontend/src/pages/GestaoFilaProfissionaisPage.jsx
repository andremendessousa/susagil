import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import {
  Stethoscope, Send, CheckCircle, Clock, AlertTriangle,
  Loader, ChevronDown, XCircle, Zap, Users,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { executarRiscoCancelamento } from '../lib/orquestracao'
import { useKpiProfissionais } from '../hooks/useKpiProfissionais'

// ─── Constantes ───────────────────────────────────────────────────────────────

const TIPO_CONFIG = {
  medico:           { label: 'Médico',          bg: 'bg-blue-100 text-blue-800'    },
  tecnico:          { label: 'Técnico',          bg: 'bg-indigo-100 text-indigo-800' },
  clinica_parceira: { label: 'Clínica Parceira', bg: 'bg-violet-100 text-violet-800' },
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fmt(iso) {
  if (!iso) return '—'
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }).format(new Date(iso))
}

function fmtDia(iso) {
  if (!iso) return '—'
  return new Intl.DateTimeFormat('pt-BR', {
    weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric',
  }).format(new Date(iso))
}

function horasAte(iso) {
  if (!iso) return null
  return Math.max(0, Math.round((new Date(iso) - Date.now()) / 3_600_000))
}

function tempoDesde(iso) {
  if (!iso) return null
  const diff = (Date.now() - new Date(iso)) / 3_600_000
  const h = Math.floor(diff)
  const m = Math.round((diff - h) * 60)
  return h === 0 ? `${Math.max(1, m)}min` : `${h}h${m > 0 ? ` ${m}min` : ''}`
}

// ─── KPI styles ─────────────────────────────────────────────────────────────

const KPI_STYLES_PROF = {
  ok:     { border: 'border-l-4 border-green-500',  iconBg: 'bg-green-50',  iconColor: 'text-green-600',  bar: 'bg-green-500'  },
  atencao:{ border: 'border-l-4 border-amber-500',  iconBg: 'bg-amber-50',  iconColor: 'text-amber-600',  bar: 'bg-amber-500'  },
  critico:{ border: 'border-l-4 border-red-500',    iconBg: 'bg-red-50',    iconColor: 'text-red-600',    bar: 'bg-red-500'    },
  neutro: { border: 'border-l-4 border-gray-200',   iconBg: 'bg-gray-50',   iconColor: 'text-gray-400',   bar: 'bg-gray-200'   },
  proteg: { border: 'border-l-4 border-violet-500', iconBg: 'bg-violet-50', iconColor: 'text-violet-600', bar: 'bg-violet-500' },
}

// ─── KpiCardProf ──────────────────────────────────────────────────────────────
// Espelha o padrão visual do KpiCard do DashboardPage (borda colorida, barra de
// progresso) sem criar dependência entre páginas.

function KpiCardProf({ icon: Icon, label, sublabel, value, style, barPct, loading }) {
  return (
    <div className={`card p-5 ${style.border}`}>
      <div className={`inline-flex items-center justify-center w-9 h-9 rounded-lg ${style.iconBg} mb-3`}>
        <Icon size={18} className={style.iconColor} />
      </div>
      <p className="text-2xl font-bold text-gray-900 leading-none">
        {loading ? <span className="text-gray-300">—</span> : value}
      </p>
      <p className="text-sm font-medium text-gray-700 mt-1">{label}</p>
      {sublabel && <p className="text-xs text-gray-400 mt-0.5">{sublabel}</p>}
      <div className="mt-3 h-1.5 w-full bg-gray-100 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-700 ${style.bar}`}
          style={{ width: `${barPct ?? 2}%` }}
        />
      </div>
    </div>
  )
}

// ─── Template de mensagem institucional ──────────────────────────────────────

function gerarTemplateProfissional({ nome, cargo, equipment_nome, ubs_nome, scheduled_at, count }) {
  // ── Data e horário separados ────────────────────────────────────────────────
  const dt = scheduled_at ? new Date(scheduled_at) : null
  const dataExtenso = dt
    ? new Intl.DateTimeFormat('pt-BR', {
        weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric',
      }).format(dt)
    : '—'
  const horario = dt
    ? new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' }).format(dt)
    : '—'

  // ── Protocolo de rastreio NMC-YYYYMMDD-XXXX ────────────────────────────────
  const hoje    = new Date()
  const yyyymmdd = [
    hoje.getFullYear(),
    String(hoje.getMonth() + 1).padStart(2, '0'),
    String(hoje.getDate()).padStart(2, '0'),
  ].join('')
  const seq       = String(Math.floor(Math.random() * 9000) + 1000) // 1000-9999
  const protocolo = `NMC-${yyyymmdd}-${seq}`

  return [
    '[Secretaria Municipal de Saúde — Montes Claros/MG]',
    '🔔 *Solicitação de Confirmação de Agenda*',
    '',
    `Protocolo: *${protocolo}*`,
    '',
    `Prezado(a) *${nome}*${ cargo ? ` (${cargo})` : '' },`,
    '',
    'Identificamos paciente(s) agendado(s) para o próximo turno sob responsabilidade do seu serviço:',
    '',
    `📅 *Data:* ${dataExtenso}`,
    `⏰ *Horário:* ${horario}`,
    `🏥 *Unidade:* ${ubs_nome}`,
    `🔬 *Serviço/Equipamento:* ${equipment_nome}`,
    `👥 *Pacientes agendados:* ${count} paciente(s)`,
    '',
    'Por favor, *confirme sua disponibilidade* respondendo:',
    '✅ *1 — CONFIRMO* disponibilidade para esta agenda',
    '⚠️ *2 — REPORTAR IMPEDIMENTO* (manutenção, ausência, insumos ou outro imprevisto)',
    '',
    '_Sistema de Regulação SUS Raio-X_',
    '_Secretaria Municipal de Saúde · Montes Claros/MG · CPSI 004/2026_',
  ].join('\n')
}

// ─── Toast ────────────────────────────────────────────────────────────────────

function Toast({ message, onDone }) {
  useEffect(() => {
    const t = setTimeout(onDone, 3500)
    return () => clearTimeout(t)
  }, [onDone])
  return (
    <div className="fixed bottom-6 right-6 z-50 bg-teal-800 text-white text-sm font-medium px-5 py-3 rounded-xl shadow-lg flex items-center gap-2">
      <CheckCircle size={14} />
      {message}
    </div>
  )
}

// ─── SimularMenu ─────────────────────────────────────────────────────────────

function SimularMenu({ notif, onSimular, loading }) {
  const [open, setOpen] = useState(false)
  const [showMotivo, setShowMotivo] = useState(false)
  const [motivo, setMotivo] = useState('')
  const ref = useRef(null)

  useEffect(() => {
    if (!open) { setShowMotivo(false); setMotivo('') }
  }, [open])

  useEffect(() => {
    if (!open) return
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false) }
    document.addEventListener('mousedown', h)
    return () => document.removeEventListener('mousedown', h)
  }, [open])

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((p) => !p)}
        disabled={loading}
        title="Esta ação simula o recebimento da resposta via WhatsApp para demonstração do fluxo."
        className="flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium text-indigo-700 bg-indigo-50 border border-indigo-200 rounded-lg hover:bg-indigo-100 transition-colors disabled:opacity-50"
      >
        {loading ? <Loader size={11} className="animate-spin" /> : <Zap size={11} />}
        Simular
        <ChevronDown size={10} className={`transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <div className="absolute right-0 top-full mt-1 z-30 bg-white border border-gray-200 rounded-xl shadow-lg min-w-[248px] py-1">
          <div className="px-3 py-2 border-b border-gray-100">
            <p className="text-[10px] text-gray-400 font-medium uppercase tracking-wide">Simular resposta do profissional</p>
          </div>
          <button
            onClick={() => { setOpen(false); onSimular(notif, 'confirmou_disponibilidade', null) }}
            className="w-full text-left px-3 py-2.5 text-xs text-gray-700 hover:bg-green-50 flex items-center gap-2 transition-colors"
          >
            <CheckCircle size={13} className="text-green-600 flex-shrink-0" />
            <span><strong>1</strong> — Confirmou disponibilidade</span>
          </button>
          {!showMotivo ? (
            <button
              onClick={() => setShowMotivo(true)}
              className="w-full text-left px-3 py-2.5 text-xs text-gray-700 hover:bg-red-50 flex items-center gap-2 transition-colors"
            >
              <XCircle size={13} className="text-red-600 flex-shrink-0" />
              <span><strong>2</strong> — Reportar impedimento</span>
            </button>
          ) : (
            <div className="px-3 py-2.5 space-y-2 border-t border-gray-100">
              <p className="text-[10px] text-gray-500 font-medium">Motivo do impedimento:</p>
              <select
                className="w-full border border-gray-200 rounded px-2 py-1.5 text-xs text-gray-900 focus:outline-none focus:ring-1 focus:ring-red-400"
                value={motivo}
                onChange={(e) => setMotivo(e.target.value)}
              >
                <option value="">Selecione o motivo…</option>
                <option value="Equipamento em manutenção">Equipamento em manutenção</option>
                <option value="Ausência do profissional">Ausência do profissional</option>
                <option value="Falta de insumos">Falta de insumos</option>
                <option value="Outro imprevisto">Outro imprevisto</option>
              </select>
              <button
                disabled={!motivo}
                onClick={() => { setOpen(false); onSimular(notif, 'reportou_indisponibilidade', motivo) }}
                className="w-full px-2 py-1.5 text-xs font-medium text-white bg-red-600 rounded hover:bg-red-700 disabled:opacity-40 transition-colors"
              >
                Confirmar impedimento
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// ─── GestaoFilaProfissionaisPage ──────────────────────────────────────────────

export default function GestaoFilaProfissionaisPage() {
  const [agendamentos, setAgendamentos]   = useState([])
  const [profissionais, setProfissionais] = useState([])
  const [notifProf, setNotifProf]         = useState([])
  const [loading, setLoading]             = useState(true)
  const [savingId, setSavingId]           = useState(null)   // grupo.key ou notif.id
  const [savingSimulacao, setSavingSimulacao] = useState(null)
  const [toast, setToast]                 = useState(null)

  const { kpis: kpisProfissionais, loading: loadingKpis } = useKpiProfissionais()

  const showToast = (msg) => setToast(msg)

  // ── Fetch ───────────────────────────────────────────────────────────────────

  const fetchAll = useCallback(async () => {
    setLoading(true)
    const limite72h = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString()

    const [apptRes, notifRes, profRes] = await Promise.all([
      // Agendamentos futuros nas próximas 72h
      supabase
        .from('appointments')
        .select(`
          id, scheduled_at,
          equipment ( id, nome, ubs_id, profissional_nome, ubs ( nome ) )
        `)
        .eq('status', 'agendado')
        .gte('scheduled_at', new Date().toISOString())
        .lte('scheduled_at', limite72h)
        .order('scheduled_at', { ascending: true }),

      // Confirmações enviadas a profissionais
      supabase
        .from('professional_confirmations')
        .select(`
          id, appointment_id, profissional_id, status_resposta,
          motivo_indisponibilidade, enviado_at, respondido_at, mensagem,
          profissionais ( nome, tipo, especialidade, cargo, telefone ),
          appointments (
            scheduled_at,
            equipment ( nome, profissional_nome, ubs ( nome ) )
          )
        `)
        .order('enviado_at', { ascending: false })
        .limit(200),

      // Cadastro de profissionais ativos
      supabase
        .from('profissionais')
        .select('id, nome, tipo, especialidade, cargo, telefone, ubs_id')
        .eq('ativo', true),
    ])

    setAgendamentos(apptRes.data ?? [])
    setProfissionais(profRes.data ?? [])

    const normalizedNotifs = (notifRes.data ?? []).map((n) => ({
      ...n,
      prof_nome:      n.profissionais?.nome ?? n.appointments?.equipment?.profissional_nome ?? '—',
      prof_tipo:      n.profissionais?.tipo  ?? null,
      prof_cargo:     n.profissionais?.cargo ?? null,
      prof_telefone:  n.profissionais?.telefone ?? null,
      scheduled_at:   n.appointments?.scheduled_at ?? null,
      equipment_nome: n.appointments?.equipment?.nome ?? '—',
      ubs_nome:       n.appointments?.equipment?.ubs?.nome ?? '—',
    }))
    setNotifProf(normalizedNotifs)
    setLoading(false)
  }, [])

  useEffect(() => { fetchAll() }, [fetchAll])

  // Realtime: atualiza quando appointments ou notificações mudam
  useEffect(() => {
    const ch = supabase
      .channel('prof-agenda-rt')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'professional_confirmations' }, fetchAll)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, fetchAll)
      .subscribe()
    return () => supabase.removeChannel(ch)
  }, [fetchAll])

  // ── Estado derivado ──────────────────────────────────────────────────────────

  // Agrupa appointments por (equipment_id, dia) → um card por turno
  const grupos = useMemo(() => {
    const map = new Map()
    for (const a of agendamentos) {
      const eqId = a.equipment?.id
      if (!eqId) continue
      const day = new Date(a.scheduled_at).toISOString().slice(0, 10)
      const key = `${eqId}__${day}`

      if (!map.has(key)) {
        // Match profissional: (1) pelo nome exato, (2) primeiro médico na mesma UBS, (3) qualquer na UBS
        const profNome = (a.equipment?.profissional_nome ?? '').trim().toLowerCase()
        const prof =
          profissionais.find((p) => profNome && p.nome.trim().toLowerCase() === profNome) ??
          profissionais.find((p) => p.ubs_id === a.equipment?.ubs_id && p.tipo === 'medico') ??
          profissionais.find((p) => p.ubs_id === a.equipment?.ubs_id) ??
          null

        map.set(key, {
          key,
          equipment_id:      eqId,
          equipment_nome:    a.equipment?.nome ?? '—',
          ubs_nome:          a.equipment?.ubs?.nome ?? '—',
          profissional_nome: prof?.nome ?? a.equipment?.profissional_nome ?? '—',
          profissional:      prof,
          day,
          first_scheduled_at: a.scheduled_at,
          appointment_ids:   [],
        })
      }
      map.get(key).appointment_ids.push(a.id)
    }
    return [...map.values()].sort(
      (a, b) => new Date(a.first_scheduled_at) - new Date(b.first_scheduled_at)
    )
  }, [agendamentos, profissionais])

  // Set de appointment_ids que já têm notificação de profissional
  const notifApptIds = useMemo(
    () => new Set(notifProf.map((n) => n.appointment_id).filter(Boolean)),
    [notifProf]
  )

  // Board 1: grupos SEM notificação de profissional
  const board1 = useMemo(
    () => grupos.filter((g) => !g.appointment_ids.some((id) => notifApptIds.has(id))),
    [grupos, notifApptIds]
  )

  // Board 2: notificações aguardando resposta
  const board2 = useMemo(
    () => notifProf.filter((n) => !n.status_resposta),
    [notifProf]
  )

  // Board 3: notificações com resposta
  const board3 = useMemo(
    () => notifProf.filter((n) => !!n.status_resposta),
    [notifProf]
  )

  // ── Ações ────────────────────────────────────────────────────────────────────

  async function solicitarConfirmacao(grupo) {
    setSavingId(grupo.key)
    const prof = grupo.profissional
    const mensagem = gerarTemplateProfissional({
      nome:           grupo.profissional_nome,
      cargo:          prof?.cargo ?? null,
      equipment_nome: grupo.equipment_nome,
      ubs_nome:       grupo.ubs_nome,
      scheduled_at:   grupo.first_scheduled_at,
      count:          grupo.appointment_ids.length,
    })

    const { error } = await supabase.from('professional_confirmations').insert({
      appointment_id:   grupo.appointment_ids[0],
      profissional_id:  prof?.id ?? null,
      tipo:             'lembrete_manual',
      mensagem,
      telefone_destino: prof?.telefone ?? '',
      enviado_at:       new Date().toISOString(),
      data_source:      'manual',
    })

    if (error) {
      console.error('[ProfissionaisPage] solicitarConfirmacao:', error)
      showToast('Erro ao enviar solicitação')
    } else {
      showToast(`Confirmação solicitada — ${grupo.profissional_nome}`)
    }
    setSavingId(null)
    await fetchAll()
  }

  async function reenviarSolicitacao(notif) {
    setSavingId(notif.id)
    const { error } = await supabase.from('professional_confirmations').insert({
      appointment_id:   notif.appointment_id,
      profissional_id:  notif.profissional_id,
      tipo:             'lembrete_manual',
      mensagem:         notif.mensagem,
      telefone_destino: notif.prof_telefone ?? '',
      enviado_at:       new Date().toISOString(),
      data_source:      'manual',
    })

    if (error) {
      console.error('[ProfissionaisPage] reenviarSolicitacao:', error)
      showToast('Erro ao reenviar solicitação')
    } else {
      showToast(`Reenvio realizado — ${notif.prof_nome}`)
    }
    setSavingId(null)
    await fetchAll()
  }

  async function simularResposta(notif, resposta, motivo) {
    setSavingSimulacao(notif.id)
    const { error } = await supabase
      .from('professional_confirmations')
      .update({
        status_resposta:          resposta,
        motivo_indisponibilidade: motivo ?? null,
        respondido_at:            new Date().toISOString(),
      })
      .eq('id', notif.id)

    if (error) {
      console.error('[ProfissionaisPage] simularResposta:', error)
      showToast('Erro ao registrar resposta')
    } else if (resposta === 'confirmou_disponibilidade') {
      showToast(`✅ Disponibilidade confirmada — ${notif.prof_nome}`)
    } else {
      // ── Impedimento: notifica pacientes preventivamente ──────────────────
      const { totalAvisados, erro: erroRisco } = await executarRiscoCancelamento(
        notif.appointment_id,
        {
          profNome:      notif.prof_nome,
          equipmentNome: notif.equipment_nome,
          ubsNome:       notif.ubs_nome,
          motivo,
        }
      )
      if (erroRisco) {
        console.warn('[ProfissionaisPage] executarRiscoCancelamento:', erroRisco)
      }
      const sufixoPacientes = totalAvisados > 0
        ? ` · ${totalAvisados} paciente(s) avisado(s) preventivamente`
        : ''
      showToast(
        `⚠️ Impedimento registrado — ${notif.prof_nome}${motivo ? `: ${motivo}` : ''}${sufixoPacientes}`
      )
    }
    setSavingSimulacao(null)
    await fetchAll()
  }

  // ── KPI derivados ─────────────────────────────────────────────────────────────

  const pctConfirmadas  = kpisProfissionais?.agendas_confirmadas_pct ?? null
  const equipConf       = Number(kpisProfissionais?.equip_confirmaram ?? 0)
  const equipTotal      = Number(kpisProfissionais?.equip_com_agenda  ?? 0)
  const indispCount     = Number(kpisProfissionais?.indisponibilidades_count ?? 0)
  const pacProtegidos   = Number(kpisProfissionais?.pacientes_protegidos ?? 0)

  const statusConf  = pctConfirmadas == null ? 'neutro'
                    : pctConfirmadas >= 80    ? 'ok'
                    : pctConfirmadas >= 40    ? 'atencao'
                    : 'critico'
  const statusIndisp = indispCount === 0 ? 'ok' : indispCount <= 2 ? 'atencao' : 'critico'

  // ── Render ────────────────────────────────────────────────────────────────────

  return (
    <>
      {toast && <Toast message={toast} onDone={() => setToast(null)} />}

      <div className="space-y-6">

        {/* Cabeçalho */}
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-xl font-semibold text-gray-900">Gestão da Fila — Profissionais</h1>
            <p className="text-sm text-gray-500 mt-0.5">
              Confirmação de agenda e disponibilidade da rede prestadora
            </p>
          </div>
          {board1.length > 0 && (
            <div className="flex items-center gap-2 px-3 py-1.5 bg-amber-50 border border-amber-200 rounded-lg text-xs font-medium text-amber-700 flex-shrink-0">
              <AlertTriangle size={13} />
              {board1.length} turno{board1.length !== 1 ? 's' : ''} sem confirmação
            </div>
          )}
        </div>

        {/* KPIs — BI */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">

          {/* KPI 1 — Agendas confirmadas */}
          <KpiCardProf
            icon={CheckCircle}
            label="Agendas confirmadas"
            sublabel={
              equipTotal > 0
                ? `${equipConf} de ${equipTotal} nos próximos 3 dias`
                : 'Nenhuma agenda no período'
            }
            value={pctConfirmadas != null ? `${pctConfirmadas}%` : equipTotal === 0 ? '—' : '0%'}
            style={KPI_STYLES_PROF[statusConf]}
            barPct={pctConfirmadas ?? 2}
            loading={loadingKpis}
          />

          {/* KPI 2 — Indisponibilidades reportadas */}
          <KpiCardProf
            icon={AlertTriangle}
            label="Indisponibilidades reportadas"
            sublabel="Últimos 30 dias"
            value={indispCount}
            style={KPI_STYLES_PROF[statusIndisp]}
            barPct={indispCount === 0 ? 2 : Math.min(indispCount * 20, 100)}
            loading={loadingKpis}
          />

          {/* KPI 3 — Pacientes protegidos (o mais poderoso para o pitch) */}
          <KpiCardProf
            icon={Users}
            label="Pacientes protegidos"
            sublabel="Deslocamentos prevenidos por aviso antecipado"
            value={pacProtegidos}
            style={KPI_STYLES_PROF.proteg}
            barPct={Math.max(Math.min(pacProtegidos * 10, 100), 2)}
            loading={loadingKpis}
          />

        </div>

        {/* ── Board 1: Pendente de Confirmação de Agenda ──────────────────────── */}
        <div className="card">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center gap-2">
            <Stethoscope size={15} className="text-amber-500" />
            <h2 className="text-sm font-semibold text-gray-900">Pendente de Confirmação de Agenda</h2>
            {board1.length > 0 && (
              <span className="badge bg-amber-100 text-amber-700">{board1.length}</span>
            )}
            {loading && <Loader size={14} className="animate-spin text-gray-400 ml-auto" />}
          </div>
          <p className="px-5 pt-3 pb-1 text-xs text-gray-400">
            Agendamentos nas próximas 72h cujos profissionais ou clínicas ainda não confirmaram disponibilidade.
          </p>

          {!loading && board1.length === 0 ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">
              Todos os profissionais com agenda nas próximas 72h foram notificados
            </div>
          ) : (
            <div className="divide-y divide-gray-50">
              {board1.map((g) => {
                const h = horasAte(g.first_scheduled_at)
                const urgente = h !== null && h <= 24
                const tipoCfg = g.profissional ? TIPO_CONFIG[g.profissional.tipo] : null
                return (
                  <div key={g.key} className="px-5 py-4 flex items-center justify-between gap-4">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <p className="text-sm font-medium text-gray-900 truncate">{g.profissional_nome}</p>
                        {tipoCfg && (
                          <span className={`badge flex-shrink-0 ${tipoCfg.bg}`}>{tipoCfg.label}</span>
                        )}
                      </div>
                      <p className="text-xs text-gray-500">{g.equipment_nome} · {g.ubs_nome}</p>
                      <p className="text-xs text-gray-400 mt-0.5">
                        {fmtDia(g.first_scheduled_at)} · {g.appointment_ids.length} paciente(s) agendado(s)
                      </p>
                    </div>
                    <div className="flex items-center gap-3 flex-shrink-0">
                      {h !== null && (
                        <span className={`badge ${urgente ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
                          em {h}h
                        </span>
                      )}
                      <button
                        onClick={() => solicitarConfirmacao(g)}
                        disabled={savingId === g.key}
                        className="btn-primary flex items-center gap-1.5 py-1.5 text-xs"
                      >
                        {savingId === g.key
                          ? <Loader size={12} className="animate-spin" />
                          : <Send size={12} />}
                        Solicitar Confirmação
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        {/* ── Board 2: Aguardando Resposta ────────────────────────────────────── */}
        <div className="card">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center gap-2">
            <Clock size={15} className="text-blue-500" />
            <h2 className="text-sm font-semibold text-gray-900">Aguardando Resposta</h2>
            {board2.length > 0 && (
              <span className="badge bg-blue-100 text-blue-700">{board2.length}</span>
            )}
            {loading && <Loader size={14} className="animate-spin text-gray-400 ml-auto" />}
          </div>
          <p className="px-5 pt-3 pb-1 text-xs text-gray-400">
            Solicitação enviada via WhatsApp. Aguardando confirmação ou reporte de impedimento.
          </p>

          {board2.length === 0 ? (
            <div className="px-5 py-6 text-center text-sm text-gray-400">
              Nenhuma solicitação aguardando resposta
            </div>
          ) : (
            <div className="divide-y divide-gray-50">
              {board2.map((n) => {
                const tipoCfg = n.prof_tipo ? TIPO_CONFIG[n.prof_tipo] : null
                return (
                  <div key={n.id} className="px-5 py-4 flex items-center justify-between gap-4">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <p className="text-sm font-medium text-gray-900 truncate">{n.prof_nome}</p>
                        {tipoCfg && (
                          <span className={`badge flex-shrink-0 ${tipoCfg.bg}`}>{tipoCfg.label}</span>
                        )}
                      </div>
                      <p className="text-xs text-gray-500">{n.equipment_nome} · {n.ubs_nome}</p>
                      {n.scheduled_at && (
                        <p className="text-xs text-gray-400 mt-0.5">{fmt(n.scheduled_at)}</p>
                      )}
                    </div>
                    <div className="flex items-center gap-3 flex-shrink-0">
                      {n.enviado_at && (
                        <span className="badge bg-blue-100 text-blue-700">
                          {tempoDesde(n.enviado_at)} sem resposta
                        </span>
                      )}
                      <button
                        onClick={() => reenviarSolicitacao(n)}
                        disabled={savingId === n.id}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-blue-700 bg-blue-50 border border-blue-200 rounded-lg hover:bg-blue-100 transition-colors disabled:opacity-50"
                      >
                        {savingId === n.id
                          ? <Loader size={12} className="animate-spin" />
                          : <Send size={12} />}
                        Reenviar
                      </button>
                      <SimularMenu
                        notif={n}
                        onSimular={simularResposta}
                        loading={savingSimulacao === n.id}
                      />
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        {/* ── Board 3: Status Confirmado ───────────────────────────────────────── */}
        <div className="card">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center gap-2">
            <CheckCircle size={15} className="text-teal-600" />
            <h2 className="text-sm font-semibold text-gray-900">Status Confirmado</h2>
            {board3.length > 0 && (
              <span className="badge bg-teal-100 text-teal-700">{board3.length}</span>
            )}
          </div>

          {board3.length === 0 ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">
              Nenhuma resposta registrada ainda
            </div>
          ) : (
            <div className="divide-y divide-gray-50">
              {board3.map((n) => {
                const confirmou = n.status_resposta === 'confirmou_disponibilidade'
                const tipoCfg = n.prof_tipo ? TIPO_CONFIG[n.prof_tipo] : null
                return (
                  <div
                    key={n.id}
                    className={`px-5 py-4 ${confirmou ? 'bg-green-50/40' : 'bg-red-50/40'}`}
                  >
                    <div className="flex items-center justify-between gap-4">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <p className="text-sm font-medium text-gray-900 truncate">{n.prof_nome}</p>
                          {tipoCfg && (
                            <span className={`badge flex-shrink-0 ${tipoCfg.bg}`}>{tipoCfg.label}</span>
                          )}
                          <span className={`badge flex-shrink-0 ${confirmou ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800'}`}>
                            {confirmou ? 'Disponível' : 'Indisponível'}
                          </span>
                        </div>
                        <p className="text-xs text-gray-500">{n.equipment_nome} · {n.ubs_nome}</p>
                        {n.scheduled_at && (
                          <p className="text-xs text-gray-400 mt-0.5">{fmt(n.scheduled_at)}</p>
                        )}
                        {!confirmou && n.motivo_indisponibilidade && (
                          <p className="text-xs text-red-700 font-medium mt-1">
                            ⚠️ {n.motivo_indisponibilidade}
                          </p>
                        )}
                      </div>
                      <div className="flex-shrink-0 text-right">
                        {n.respondido_at && (
                          <p className="text-xs text-gray-400">{fmt(n.respondido_at)}</p>
                        )}
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

      </div>
    </>
  )
}
