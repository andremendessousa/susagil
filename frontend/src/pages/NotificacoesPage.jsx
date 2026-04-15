import { useState, useEffect, useCallback, useRef } from 'react'
import { Bell, Send, Users, CheckCircle, Clock, AlertTriangle, Loader, X, ChevronDown, XCircle, Zap, Sparkles } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { executarReaproveitamento } from '../lib/orquestracao'
import { useNotifications } from '../hooks/useNotifications'
import { useKpiConfigs } from '../hooks/useKpiConfigs'
import { useAuth } from '../hooks/useAuth'

// ─── Constantes ───────────────────────────────────────────────────────────────

const TIPO_BADGE = {
  '72h':             'bg-blue-100 text-blue-800',
  '24h':             'bg-amber-100 text-amber-800',
  '2h':              'bg-red-100 text-red-800',
  lembrete_manual:   'bg-gray-100 text-gray-600',
}

const RESPOSTA_BADGE = {
  confirmou:   'bg-green-100 text-green-800',
  cancelou:    'bg-red-100 text-red-800',
}

const TIPOS_NOTIFICACAO = [
  { value: '72h',           label: '72 horas antes' },
  { value: '24h',           label: '24 horas antes' },
  { value: '2h',            label: '2 horas antes'  },
  { value: 'lembrete_manual', label: 'Lembrete manual' },
]

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatarDataHora(iso) {
  if (!iso) return '—'
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }).format(new Date(iso))
}

function horasRestantes(scheduledAt) {
  if (!scheduledAt) return null
  const diff = (new Date(scheduledAt) - Date.now()) / (1000 * 60 * 60)
  return Math.max(0, Math.round(diff))
}

// ─── Toast ────────────────────────────────────────────────────────────────────

function Toast({ message, special, onDone }) {
  useEffect(() => {
    const t = setTimeout(onDone, special ? 5000 : 3500)
    return () => clearTimeout(t)
  }, [onDone, special])
  return (
    <div className={`fixed bottom-6 right-6 z-50 text-white text-sm font-medium px-5 py-3 rounded-xl shadow-lg flex items-center gap-2 transition-all ${
      special
        ? 'bg-emerald-700 border border-emerald-400 animate-pulse'
        : 'bg-blue-800'
    }`}>
      {special ? <Sparkles size={15} className="text-emerald-200" /> : <CheckCircle size={14} />}
      {message}
    </div>
  )
}

// ─── Modal de notificação em massa ────────────────────────────────────────────

function ModalMassa({ vagasEmRisco, onClose, onConfirm, saving }) {
  const [tipoSelecionado, setTipoSelecionado] = useState('lembrete_manual')

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center bg-black/40">
      <div className="card w-full max-w-md p-6 space-y-5">
        <div className="flex items-center justify-between">
          <h3 className="text-base font-semibold text-gray-900">Notificar em massa</h3>
          <button onClick={onClose} className="p-1 rounded hover:bg-gray-100">
            <X size={16} className="text-gray-400" />
          </button>
        </div>

        <p className="text-sm text-gray-600">
          <span className="font-semibold text-blue-700">{vagasEmRisco.length} paciente{vagasEmRisco.length !== 1 ? 's' : ''}</span>
          {' '}sem confirmação serão notificados via WhatsApp.
        </p>

        <div>
          <label className="block text-xs font-medium text-gray-700 mb-1">Tipo de notificação</label>
          <select
            value={tipoSelecionado}
            onChange={(e) => setTipoSelecionado(e.target.value)}
            className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
          >
            {TIPOS_NOTIFICACAO.map(({ value, label }) => (
              <option key={value} value={value}>{label}</option>
            ))}
          </select>
        </div>

        <div className="flex gap-3 justify-end pt-2">
          <button onClick={onClose} className="btn-ghost">Cancelar</button>
          <button
            onClick={() => onConfirm(tipoSelecionado)}
            disabled={saving}
            className="btn-primary flex items-center gap-2"
          >
            {saving ? <Loader size={14} className="animate-spin" /> : <Send size={14} />}
            {saving ? 'Enviando…' : 'Confirmar'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ─── SimularRespostaMenu ─────────────────────────────────────────────────────

function SimularRespostaMenu({ notif, onSimular, loading }) {
  const [aberto, setAberto] = useState(false)
  const ref = useRef(null)

  useEffect(() => {
    if (!aberto) return
    function handler(e) {
      if (ref.current && !ref.current.contains(e.target)) setAberto(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [aberto])

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setAberto(prev => !prev)}
        disabled={loading}
        title="Esta ação simula o recebimento do Webhook da API para demonstração do funcionamento da comunicação com pacientes."
        className="flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium text-indigo-700 bg-indigo-50 border border-indigo-200 rounded-lg hover:bg-indigo-100 transition-colors disabled:opacity-50"
      >
        {loading
          ? <Loader size={11} className="animate-spin" />
          : <Zap size={11} />}
        Simular
        <ChevronDown size={10} className={`transition-transform ${aberto ? 'rotate-180' : ''}`} />
      </button>
      {aberto && (
        <div className="absolute right-0 top-full mt-1 z-30 bg-white border border-gray-200 rounded-xl shadow-lg min-w-[200px] py-1">
          <div className="px-3 py-2 border-b border-gray-100">
            <p className="text-[10px] text-gray-400 font-medium uppercase tracking-wide">Simular resposta do paciente</p>
          </div>
          <button
            onClick={() => { setAberto(false); onSimular(notif, 'confirmou') }}
            className="w-full text-left px-3 py-2.5 text-xs text-gray-700 hover:bg-green-50 flex items-center gap-2 transition-colors"
          >
            <CheckCircle size={13} className="text-green-600 flex-shrink-0" />
            <span><strong>1</strong> — Confirmou presença</span>
          </button>
          <button
            onClick={() => { setAberto(false); onSimular(notif, 'cancelou') }}
            className="w-full text-left px-3 py-2.5 text-xs text-gray-700 hover:bg-red-50 flex items-center gap-2 transition-colors"
          >
            <XCircle size={13} className="text-red-600 flex-shrink-0" />
            <span><strong>2</strong> — Cancelou / não precisa mais</span>
          </button>
        </div>
      )}
    </div>
  )
}

// ─── NotificacoesPage ─────────────────────────────────────────────────────────

export default function NotificacoesPage() {
  const { user } = useAuth()
  const { notifications, stats, loading, error: notifError, refresh } = useNotifications()
  const { configs } = useKpiConfigs()

  const [vagasEmRisco, setVagasEmRisco] = useState([])
  const [loadingVagas, setLoadingVagas] = useState(true)
  const [savingId, setSavingId] = useState(null)
  const [savingMassa, setSavingMassa] = useState(false)
  const [savingSimulacao, setSavingSimulacao] = useState(null)
  const [alertaCancelamento, setAlertaCancelamento] = useState(null)
  const [showModal, setShowModal] = useState(false)
  const [toast, setToast] = useState(null)          // { message, special }
  const showToast = (message, special = false) => setToast({ message, special })

  // || 48: guarda contra valor_meta = 0 no banco (vagas_risco_horas pode existir com 0)
  const horasConfig = configs?.vagas_risco_horas?.valor_meta || 48

  // ── Vagas em risco ─────────────────────────────────────────────────────────

  const fetchVagas = useCallback(async () => {
    // Aguardar configs carregar para usar horasConfig definitivo
    if (configs === null) return
    setLoadingVagas(true)
    const limite = new Date(Date.now() + horasConfig * 60 * 60 * 1000).toISOString()

    // appointments não tem patient_id direto — navega via queue_entries
    const { data, error } = await supabase
      .from('appointments')
      .select(`
        id, scheduled_at, st_paciente_avisado,
        queue_entries ( patient_id, patients ( id, nome, telefone ) ),
        equipment ( nome )
      `)
      .eq('status', 'agendado')
      .eq('st_paciente_avisado', 0)
      .gte('scheduled_at', new Date().toISOString())
      .lte('scheduled_at', limite)
      .order('scheduled_at', { ascending: true })

    if (!error) {
      setVagasEmRisco(
        (data || []).map((a) => ({
          ...a,
          paciente_nome:    a.queue_entries?.patients?.nome     ?? '—',
          paciente_id:      a.queue_entries?.patients?.id       ?? null,
          telefone:         a.queue_entries?.patients?.telefone ?? null,
          equipamento_nome: a.equipment?.nome ?? '—',
        }))
      )
    }
    setLoadingVagas(false)
  }, [horasConfig, configs])

  useEffect(() => { fetchVagas() }, [fetchVagas])

  // ── Simular resposta do paciente (demo) ───────────────────────────────

  async function simularResposta(notif, resposta) {
    setSavingSimulacao(notif.id)
    try {
      // 1 — Registra resposta na notificação
      await supabase
        .from('notification_log')
        .update({
          resposta_paciente: resposta,
          respondido_at:     new Date().toISOString(),
        })
        .eq('id', notif.id)

      if (resposta === 'confirmou') {
        if (notif.appointment_id) {
          await supabase
            .from('appointments')
            .update({ status: 'confirmado' })
            .eq('id', notif.appointment_id)
        }
        showToast('Confirmação de presença registrada')

      } else {
        // ── ORQUESTRAÇÃO INTELIGENTE (via módulo centralizado) ────────────────

        // 2 — Cancela agendamento atual
        // (o RPC trata queue_entries; aqui só atualizamos appointments.status)
        if (notif.appointment_id) {
          await supabase
            .from('appointments')
            .update({ status: 'cancelado' })
            .eq('id', notif.appointment_id)
        }

        // 3 — Delega ao módulo centralizado de reaproveitamento
        const { nomeConvocado, erro } = notif.appointment_id
          ? await executarReaproveitamento(notif.appointment_id)
          : { nomeConvocado: null, erro: null }

        setAlertaCancelamento(notif.paciente_nome)

        if (nomeConvocado) {
          showToast(
            `Vaga reocupada automaticamente! Paciente ${nomeConvocado} convocado do topo da fila.`,
            true
          )
        } else if (erro) {
          showToast(`Cancelamento registrado — orquestração falhou: ${erro}`)
          console.error('[NotificacoesPage] reaproveitamento:', erro)
        } else {
          showToast('Cancelamento registrado — fila vazia para este procedimento')
        }
      }
    } finally {
      setSavingSimulacao(null)
      await refresh()
    }
  }

  // ── Notificar individualmente ──────────────────────────────────────────────

  async function notificarVaga(vaga) {
    setSavingId(vaga.id)

    const { error: errLog } = await supabase
      .from('notification_log')
      .insert({
        patient_id:       vaga.paciente_id,
        appointment_id:   vaga.id,
        tipo:             'lembrete_manual',
        canal:            'whatsapp',
        mensagem:         `Lembrete: você tem um agendamento em ${vaga.equipamento_nome} para ${formatarDataHora(vaga.scheduled_at)}. Confirme presença respondendo 1.`,
        telefone_destino: vaga.telefone ?? '',
        enviado_at:       new Date().toISOString(),
        entregue:         false,
        data_source:      'manual',
      })

    if (!errLog) {
      await supabase
        .from('appointments')
        .update({ st_paciente_avisado: 1 })
        .eq('id', vaga.id)
    }

    setSavingId(null)
    await Promise.all([fetchVagas(), refresh()])
    showToast('Notificação registrada')
  }

  // ── Notificar em massa ─────────────────────────────────────────────────────

  async function notificarMassa(tipo) {
    setSavingMassa(true)

    const registros = vagasEmRisco.map((v) => ({
      patient_id:       v.paciente_id,
      appointment_id:   v.id,
      tipo,
      canal:            'whatsapp',
      mensagem:         `Lembrete: você tem um agendamento em ${v.equipamento_nome} para ${formatarDataHora(v.scheduled_at)}. Confirme presença respondendo 1.`,
      telefone_destino: v.telefone ?? '',
      enviado_at:       new Date().toISOString(),
      entregue:         false,
      data_source:      'manual',
    }))

    const { error: errLog } = await supabase
      .from('notification_log')
      .insert(registros)

    if (!errLog) {
      const ids = vagasEmRisco.map((v) => v.id)
      await supabase
        .from('appointments')
        .update({ st_paciente_avisado: 1 })
        .in('id', ids)
    }

    setSavingMassa(false)
    setShowModal(false)
    await Promise.all([fetchVagas(), refresh()])
    showToast(`${registros.length} notificações registradas`)
  }

  // ─── Render ────────────────────────────────────────────────────────────────

  const kpiCards = [
    {
      label:   'Enviadas hoje',
      value:   stats.total_hoje,
      icon:    Send,
      color:   'text-blue-700',
      bg:      'bg-blue-50',
    },
    {
      label:   'Taxa de confirmação',
      value:   stats.taxa_confirmacao != null ? `${stats.taxa_confirmacao}%` : '—',
      icon:    CheckCircle,
      color:   'text-green-700',
      bg:      'bg-green-50',
    },
    {
      label:   'Sem resposta (>2h)',
      value:   stats.sem_resposta,
      icon:    AlertTriangle,
      color:   stats.sem_resposta > 0 ? 'text-amber-600' : 'text-gray-400',
      bg:      stats.sem_resposta > 0 ? 'bg-amber-50'   : 'bg-gray-50',
    },
  ]

  return (
    <>
      {toast && <Toast message={toast.message} special={toast.special} onDone={() => setToast(null)} />}
      {showModal && (
        <ModalMassa
          vagasEmRisco={vagasEmRisco}
          onClose={() => setShowModal(false)}
          onConfirm={notificarMassa}
          saving={savingMassa}
        />
      )}

      <div className="space-y-6">
        {/* Cabeçalho */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-semibold text-gray-900">Notificações</h1>
            <p className="text-sm text-gray-500 mt-0.5">
              Comunicação com pacientes via WhatsApp — janela de {horasConfig}h
            </p>
          </div>
          {vagasEmRisco.length > 0 && (
            <button
              onClick={() => setShowModal(true)}
              className="btn-primary flex items-center gap-2"
            >
              <Users size={15} />
              Notificar em massa ({vagasEmRisco.length})
            </button>
          )}
        </div>

        {/* Alerta visual de cancelamento */}
        {alertaCancelamento && (
          <div className="flex items-start gap-3 bg-amber-50 border border-amber-300 rounded-xl px-5 py-4">
            <Zap size={18} className="text-amber-600 flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm font-semibold text-amber-900">
                Vaga liberada para o motor de redistribuição
              </p>
              <p className="text-xs text-amber-700 mt-0.5">
                <strong>{alertaCancelamento}</strong> confirmou cancelamento via WhatsApp.
                A vaga está disponível para reaproveitamento imediato.
              </p>
            </div>
            <button
              onClick={() => setAlertaCancelamento(null)}
              className="p-1 rounded hover:bg-amber-100 text-amber-500"
            >
              <X size={14} />
            </button>
          </div>
        )}

        {/* ── Seção 1: KPIs de comunicação ────────────────────────────────── */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {kpiCards.map(({ label, value, icon: Icon, color, bg }) => (
            <div key={label} className="card p-5">
              <div className={`inline-flex p-2 rounded-lg ${bg} mb-3`}>
                <Icon size={18} className={color} />
              </div>
              <p className="text-2xl font-bold text-gray-900">{loading ? '…' : value}</p>
              <p className="text-sm font-medium text-gray-600 mt-1">{label}</p>
            </div>
          ))}
        </div>

        {/* ── Seção 2: Vagas sem confirmação ───────────────────────────────── */}
        <div className="card">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Clock size={15} className="text-red-500" />
              <h2 className="text-sm font-semibold text-gray-900">Vagas sem confirmação</h2>
              {vagasEmRisco.length > 0 && (
                <span className="badge bg-red-100 text-red-700">{vagasEmRisco.length}</span>
              )}
            </div>
            {loadingVagas && <Loader size={14} className="animate-spin text-gray-400" />}
          </div>

          {!loadingVagas && vagasEmRisco.length === 0 ? (
            <div className="px-5 py-8 text-center text-sm text-gray-400">
              Nenhuma vaga em risco nas próximas {horasConfig}h
            </div>
          ) : (
            <div className="divide-y divide-gray-50">
              {vagasEmRisco.map((vaga) => {
                const hRestantes = horasRestantes(vaga.scheduled_at)
                const urgente = hRestantes !== null && hRestantes <= 24
                return (
                  <div
                    key={vaga.id}
                    className="px-5 py-4 flex items-center justify-between gap-4"
                  >
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-gray-900 truncate">
                        {vaga.paciente_nome}
                      </p>
                      <p className="text-xs text-gray-500 mt-0.5">
                        {vaga.equipamento_nome} · {formatarDataHora(vaga.scheduled_at)}
                      </p>
                    </div>
                    <div className="flex items-center gap-3 flex-shrink-0">
                      {hRestantes !== null && (
                        <span className={`badge ${urgente ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
                          {hRestantes}h rest.
                        </span>
                      )}
                      <button
                        onClick={() => notificarVaga(vaga)}
                        disabled={savingId === vaga.id}
                        className="btn-primary flex items-center gap-1.5 py-1.5 text-xs"
                      >
                        {savingId === vaga.id
                          ? <Loader size={12} className="animate-spin" />
                          : <Bell size={12} />}
                        Notificar
                      </button>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        {/* ── Seção 3: Histórico de notificações ───────────────────────────── */}
        <div className="card">
          <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-gray-900">Histórico</h2>
            {loading && <Loader size={14} className="animate-spin text-gray-400" />}
          </div>
          {notifError && (
            <div className="px-5 py-4 text-xs text-red-600 bg-red-50 flex items-center gap-2">
              <AlertTriangle size={13} />
              Erro ao carregar notificações: {notifError}
            </div>
          )}
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-xs text-gray-500 uppercase tracking-wide">
              <tr>
                <th className="px-5 py-3 text-left">Paciente</th>
                <th className="px-5 py-3 text-left">Tipo</th>
                <th className="px-5 py-3 text-left">Equipamento</th>
                <th className="px-5 py-3 text-left">Enviado em</th>
                <th className="px-5 py-3 text-left">Resposta</th>
                <th className="px-5 py-3 text-left">Ação Simulada</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {notifications.map((n) => {
                const cancelou = n.resposta_paciente === 'cancelou'
                const confirmou = n.resposta_paciente === 'confirmou'
                return (
                  <tr
                    key={n.id}
                    className={`transition-colors ${
                      cancelou  ? 'bg-red-50 hover:bg-red-50' :
                      confirmou ? 'bg-green-50/40 hover:bg-green-50/60' :
                      'hover:bg-gray-50'
                    }`}
                  >
                    <td className="px-5 py-3">
                      <div className="flex items-center gap-2">
                        <span className="font-medium text-gray-900">{n.paciente_nome}</span>
                        {cancelou && (
                          <span className="badge bg-red-200 text-red-800 text-[10px] font-bold">Vaga Recuperada</span>
                        )}
                      </div>
                    </td>
                    <td className="px-5 py-3">
                      <span className={`badge ${TIPO_BADGE[n.tipo] ?? 'bg-gray-100 text-gray-600'}`}>
                        {n.tipo}
                      </span>
                    </td>
                    <td className="px-5 py-3 text-gray-500">{n.equipamento_nome}</td>
                    <td className="px-5 py-3 text-gray-500">{formatarDataHora(n.enviado_at)}</td>
                    <td className="px-5 py-3">
                      {n.resposta_paciente ? (
                        <span className={`badge ${RESPOSTA_BADGE[n.resposta_paciente] ?? 'bg-gray-100 text-gray-600'}`}>
                          {n.resposta_paciente}
                        </span>
                      ) : (
                        <span className="badge bg-gray-100 text-gray-500">sem resposta</span>
                      )}
                    </td>
                    <td className="px-5 py-3">
                      {!n.resposta_paciente && (
                        <SimularRespostaMenu
                          notif={n}
                          onSimular={simularResposta}
                          loading={savingSimulacao === n.id}
                        />
                      )}
                    </td>
                  </tr>
                )
              })}
              {!loading && notifications.length === 0 && (
                <tr>
                  <td colSpan={6} className="px-5 py-8 text-center text-gray-400 text-sm">
                    Nenhuma notificação registrada
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </>
  )
}
