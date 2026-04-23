import { useState, useEffect, useCallback, useRef } from 'react'
import {
  MessageSquare, Search, CheckCheck, X,
  Phone, Video, MoreVertical, Loader, Check,
  ShieldAlert, Users, Building2,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { executarReaproveitamento } from '../lib/orquestracao'
import { useEscopo } from '../contexts/EscopoContext'
import { UBS_REGIONAL_INDEPENDENCIA } from '../constants/macrorregiao'

// ─── Helpers ──────────────────────────────────────────────────────────────────

function formatarHora(iso) {
  if (!iso) return ''
  return new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' }).format(new Date(iso))
}

function formatarDataRelativa(iso) {
  if (!iso) return ''
  const d = new Date(iso)
  const hoje = new Date()
  const ontem = new Date(hoje); ontem.setDate(hoje.getDate() - 1)
  if (d.toDateString() === hoje.toDateString()) return 'Hoje'
  if (d.toDateString() === ontem.toDateString()) return 'Ontem'
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
}

function formatarDataHora(iso) {
  if (!iso) return '—'
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
  }).format(new Date(iso))
}

function mascaraCNS(cns) {
  if (!cns) return null
  const s = String(cns).replace(/\D/g, '')
  if (s.length < 15) return s
  return `${s.slice(0, 3)} ${s.slice(3, 7)} ${s.slice(7, 11)} ${s.slice(11, 15)}`
}

// ─── Templates institucionais GovTech ────────────────────────────────────────

const INST_HEADER = '[Secretaria Municipal de Saúde — Montes Claros/MG]'
const INST_FOOTER = 'Secretaria Municipal de Saúde — Montes Claros/MG\nEsta mensagem é oficial. Seus dados são tratados conforme a LGPD (Lei 13.709/2018).'

// Gera texto da mensagem do sistema a partir do notification_log
function gerarMensagemSistema(notif) {
  if (notif.mensagem) return notif.mensagem
  const nome    = notif.paciente_nome ?? 'Paciente'
  const proc    = notif.equipamento_nome ?? 'procedimento solicitado'
  const dataStr = notif.scheduled_at ? formatarDataHora(notif.scheduled_at) : 'data a confirmar'
  const urgencia =
    notif.tipo === '2h'
      ? '\n\n🚨 *URGENTE — CONFIRMAÇÃO FINAL:* Esta é a última notificação. A não confirmação em até *2 horas* implicará na liberação automática da sua vaga ao próximo paciente na fila de espera.'
      : notif.tipo === '24h'
      ? '\n\n⚡ *ATENÇÃO:* Seu agendamento é amanhã. Confirme sua presença para garantir a vaga.'
      : ''
  return `${INST_HEADER}\n\nPrezado(a) *${nome}*,\n\nIdentificamos seu agendamento:\n📋 *Procedimento:* ${proc}\n📅 *Data/Hora:* ${dataStr}\n🏥 *Unidade:* Serviço de Regulação — Montes Claros\n\nPor favor, *confirme sua presença* selecionando uma das opções abaixo:\n\n✅ *[1 - SIM, CONFIRMO]* minha presença\n❌ *[2 - NÃO, PRECISO CANCELAR]* este agendamento${urgencia}\n\n${INST_FOOTER}`
}

// Template de confirmação de agendamento (disparo manual pelo operador)
function gerarTemplateConfirmacao(notif) {
  const nome    = notif?.paciente_nome ?? 'Paciente'
  const proc    = notif?.equipamento_nome ?? 'procedimento'
  const dataStr = notif?.scheduled_at ? formatarDataHora(notif.scheduled_at) : 'data a confirmar'
  return `${INST_HEADER}\n\nPrezado(a) *${nome}*, identificamos seu agendamento de *${proc}* para o dia *${dataStr}* na Unidade de referência Municipal.\n\nPor favor, selecione uma opção:\n✅ *[1 - SIM, CONFIRMO]* minha presença\n❌ *[2 - NÃO, PRECISO CANCELAR]* este agendamento\n\n${INST_FOOTER}`
}

// Template de reuso / antecipação de vaga (disparo manual pelo operador)
function gerarTemplateReuso(notif) {
  const dataStr = notif?.scheduled_at ? formatarDataHora(notif.scheduled_at) : 'horário disponível'
  return `${INST_HEADER}\n\n⚠️ *AVISO DE VAGA DISPONÍVEL*\n\nIdentificamos que o horário de *${dataStr}* está disponível para o seu procedimento. Esta é uma oportunidade de antecipação do seu exame na fila de espera.\n\nDeseja aceitar esta vaga?\n✅ *[1 - SIM, ACEITO]* a antecipação\n❌ *[2 - NÃO, MANTER]* meu agendamento original\n\n${INST_FOOTER}`
}

const RESPOSTA_TEXT = {
  confirmou: '✅ Sim, confirmo minha presença!',
  cancelou:  '❌ Não poderei comparecer, preciso cancelar.',
}

const TIPO_LABEL = {
  '72h':           '72h antes',
  '24h':           '24h antes',
  '2h':            '2h antes',
  lembrete_manual: 'Lembrete',
}

// Dedup: retorna a notificação mais recente por patient_id
function deduplicarPorPaciente(notifs) {
  const map = new Map()
  for (const n of notifs) {
    const pid = n.patient_id
    if (!map.has(pid) || new Date(n.enviado_at) > new Date(map.get(pid).enviado_at)) {
      map.set(pid, n)
    }
  }
  return [...map.values()]
}

// ─── Badge de status (NOC) ───────────────────────────────────────────────────────────────────

function StatusBadge({ resposta, tipo, scheduledAt }) {
  if (resposta === 'sem_notificacao')
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-slate-100 text-slate-500 border border-slate-200">Ag. Notif.</span>
  if (resposta === 'confirmou')
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-green-100 text-green-700">Confirmado</span>
  if (resposta === 'cancelou')
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-red-100 text-red-700">Cancelado</span>
  // Em Risco: tipo 2h/24h sem confirmação, ou < 24h para o agendamento
  const diffMs = scheduledAt ? new Date(scheduledAt) - new Date() : Infinity
  const isRisk = tipo === '2h' || tipo === '24h' || diffMs < 24 * 60 * 60 * 1000
  if (isRisk)
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-orange-100 text-orange-700">Em Risco</span>
  return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-yellow-100 text-yellow-700">Pendente</span>
}

// ─── ContactItem ──────────────────────────────────────────────────────────────

function ContactItem({ notif, active, onClick }) {
  const inicial = (notif.paciente_nome ?? '?')[0].toUpperCase()
  // Preview: resposta do paciente > label do tipo de notif > nome do procedimento > data agendada
  const temResposta = notif.resposta_paciente && notif.resposta_paciente !== 'sem_notificacao'
  const preview = temResposta
    ? RESPOSTA_TEXT[notif.resposta_paciente]
    : TIPO_LABEL[notif.tipo]
      ?? (notif.equipamento_nome ? `📋 ${notif.equipamento_nome}` : null)
      ?? (notif.scheduled_at ? `📅 ${formatarDataHora(notif.scheduled_at)}` : 'Aguardando notificação')

  return (
    <button
      onClick={onClick}
      className={`w-full text-left flex items-center gap-3 px-4 py-3 transition-colors border-b border-gray-100 ${
        active ? 'bg-[#f0f2f5]' : 'hover:bg-[#f5f6f6]'
      }`}
    >
      <div className="flex-shrink-0 w-10 h-10 rounded-full bg-green-700 flex items-center justify-center text-white text-sm font-bold">
        {inicial}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex justify-between items-baseline gap-1">
          <p className="text-sm font-medium text-gray-900 truncate">{notif.paciente_nome}</p>
          <span className={`text-[10px] flex-shrink-0 ${
            notif.resposta_paciente === null || notif.resposta_paciente === 'sem_notificacao'
              ? 'text-green-700 font-semibold'
              : 'text-gray-400'
          }`}>
            {formatarDataRelativa(notif.enviado_at)}
          </span>
        </div>
        <div className="flex items-center justify-between mt-0.5 gap-1">
          <p className="text-xs text-gray-500 truncate">{preview}</p>
          <StatusBadge resposta={notif.resposta_paciente} tipo={notif.tipo} scheduledAt={notif.scheduled_at} />
        </div>
      </div>
    </button>
  )
}

// ─── Balões de mensagem ───────────────────────────────────────────────────────

// Mensagem enviada pelo sistema (balão verde, direita)
function SysBubble({ text, time, delivered = true }) {
  return (
    <div className="flex justify-end mb-2">
      <div className="max-w-[65%]">
        <div
          className="rounded-lg rounded-tr-none px-3 py-2 shadow-sm text-sm text-gray-900 whitespace-pre-wrap"
          style={{ backgroundColor: '#dcf8c6' }}
        >
          {text}
        </div>
        <p className="text-[10px] text-gray-400 text-right mt-0.5 flex items-center justify-end gap-1">
          {time}
          {delivered
            ? <CheckCheck size={11} className="text-blue-500" />
            : <Check size={11} className="text-gray-400" />}
        </p>
      </div>
    </div>
  )
}

// Mensagem do paciente (balão branco, esquerda)
function PatientBubble({ text, time }) {
  return (
    <div className="flex justify-start mb-2">
      <div className="max-w-[65%]">
        <div className="bg-white rounded-lg rounded-tl-none px-3 py-2 shadow-sm text-sm text-gray-900 border border-gray-100 whitespace-pre-wrap">
          {text}
        </div>
        <p className="text-[10px] text-gray-400 mt-0.5">{time}</p>
      </div>
    </div>
  )
}

// ─── Divisor de data ──────────────────────────────────────────────────────────

function DateDivider({ label }) {
  return (
    <div className="flex items-center gap-3 my-4">
      <div className="flex-1 h-px bg-gray-300/50" />
      <span className="text-[10px] text-gray-500 bg-[#e5ddd5] px-2 py-0.5 rounded-full">{label}</span>
      <div className="flex-1 h-px bg-gray-300/50" />
    </div>
  )
}

// ─── PainelPaciente — Simulação do canal WhatsApp do paciente ───────────────

function PainelPaciente({ notif, pacienteNome, saving, resultado, chatNotifs, onConfirmar, onCancelar }) {
  const [doubleCheck, setDoubleCheck] = useState(false)
  const [animating, setAnimating] = useState(false)

  useEffect(() => {
    setDoubleCheck(false)
  }, [notif?.id, resultado])

  useEffect(() => {
    if (resultado?.tipo === 'cancelou' && resultado?.nomeConvocado) {
      setAnimating(true)
      const t = setTimeout(() => setAnimating(false), 1200)
      return () => clearTimeout(t)
    }
  }, [resultado])

  const ultimaRespondida = [...(chatNotifs ?? [])].reverse().find(n => n.resposta_paciente) ?? null
  const inicial = (pacienteNome || '?')[0].toUpperCase()

  return (
    <div className="w-80 flex-shrink-0 flex flex-col overflow-hidden" style={{ backgroundColor: '#1a1a2e' }}>

      {/* Header WhatsApp */}
      <div
        className="flex items-center gap-3 px-4 py-3 flex-shrink-0"
        style={{ backgroundColor: '#075e54' }}
      >
        <div className="w-9 h-9 rounded-full bg-green-500 flex items-center justify-center text-white text-sm font-bold flex-shrink-0">
          {inicial}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-white truncate">{pacienteNome || '—'}</p>
          <p className="text-[10px] text-green-200">Canal WhatsApp — Simulação</p>
        </div>
      </div>

      {/* Corpo */}
      <div
        className="flex-1 overflow-y-auto px-3 py-4 flex flex-col gap-3"
        style={{ backgroundColor: '#0d1117' }}
      >
        {resultado ? (
          resultado.tipo === 'confirmou' ? (
            /* ── Resultado: Confirmação ── */
            <div className="flex flex-col items-center gap-4 pt-6">
              <div className="w-16 h-16 rounded-full flex items-center justify-center" style={{ backgroundColor: '#25d36640' }}>
                <Check size={30} className="text-green-400" />
              </div>
              <div className="text-center">
                <p className="text-base font-bold text-green-400">Agendamento confirmado!</p>
                <p className="text-xs text-gray-400 mt-1">Presença registrada com sucesso</p>
              </div>
              <div className="w-full rounded-xl px-4 py-3 text-center" style={{ backgroundColor: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
                <p className="text-[11px] text-gray-300">
                  Notificação de confirmação enviada ao serviço de regulação e registrada no histórico do paciente.
                </p>
              </div>
            </div>
          ) : (
            /* ── Resultado: Cancelamento (visão do paciente) ── */
            <div className="flex flex-col items-center gap-4 pt-6">
              <div className="w-16 h-16 rounded-full flex items-center justify-center" style={{ backgroundColor: '#dc262640' }}>
                <X size={30} className="text-red-400" />
              </div>
              <div className="text-center">
                <p className="text-base font-bold text-red-400">Agendamento cancelado</p>
                <p className="text-xs text-gray-400 mt-1">Sua desistência foi registrada no sistema.</p>
                {resultado.nomeConvocado && (
                  <p className="text-xs mt-1.5" style={{ color: '#4ade80' }}>Sua vaga foi para o próximo da fila.</p>
                )}
              </div>
              <div className="w-full flex justify-end">
                <div
                  className="max-w-[85%] rounded-lg rounded-tr-none px-3 py-2 text-xs"
                  style={{ backgroundColor: '#dcf8c6', color: '#111' }}
                >
                  ❌ Não poderei comparecer, preciso cancelar.
                </div>
              </div>
            </div>
          )
        ) : notif ? (
          /* ── Notificação pendente: simular resposta ── */
          <>
            {/* Bubble recebida pelo paciente */}
            <div className="flex justify-start">
              <div
                className="max-w-[90%] rounded-lg rounded-tl-none px-3 py-2 shadow-sm text-xs leading-relaxed whitespace-pre-wrap"
                style={{ backgroundColor: '#1e3a2f', color: '#d1fae5', border: '1px solid rgba(255,255,255,0.08)' }}
              >
                {gerarMensagemSistema(notif)}
              </div>
            </div>

            {/* Botões de resposta */}
            {!doubleCheck ? (
              <div className="flex flex-col gap-2 mt-1">
                <button
                  onClick={() => onConfirmar(notif)}
                  disabled={saving}
                  className="w-full py-3 rounded-xl text-sm font-bold text-white transition-all disabled:opacity-50 active:scale-95"
                  style={{ backgroundColor: '#25d366' }}
                >
                  {saving
                    ? <Loader size={14} className="animate-spin mx-auto" />
                    : '1  ✅  SIM, CONFIRMO'}
                </button>
                <button
                  onClick={() => setDoubleCheck(true)}
                  disabled={saving}
                  className="w-full py-3 rounded-xl text-sm font-bold text-white bg-red-600 hover:bg-red-700 transition-all disabled:opacity-50 active:scale-95"
                >
                  2  ❌  NÃO, CANCELAR
                </button>
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                <div
                  className="flex items-start gap-2 rounded-xl px-3 py-2.5"
                  style={{ backgroundColor: '#3b0000', border: '1px solid rgba(220,38,38,0.4)' }}
                >
                  <ShieldAlert size={13} className="text-red-400 flex-shrink-0 mt-0.5" />
                  <p className="text-[11px] text-red-300 leading-snug">
                    AÇÃO IRREVERSÍVEL — a vaga será redirecionada ao próximo paciente qualificado na fila. Confirme a desistência:
                  </p>
                </div>
                <button
                  onClick={() => onCancelar(notif)}
                  disabled={saving}
                  className="w-full py-2.5 rounded-xl text-xs font-bold text-white bg-red-600 hover:bg-red-700 transition-all disabled:opacity-50 active:scale-95"
                >
                  {saving
                    ? <Loader size={12} className="animate-spin mx-auto" />
                    : 'CONFIRMAR DESISTÊNCIA'}
                </button>
                <button
                  onClick={() => setDoubleCheck(false)}
                  disabled={saving}
                  className="w-full py-2.5 rounded-xl text-xs font-medium transition-all disabled:opacity-40"
                  style={{ color: '#9ca3af', border: '1px solid rgba(255,255,255,0.12)' }}
                >
                  ← MANTER AGENDAMENTO
                </button>
              </div>
            )}
          </>
        ) : ultimaRespondida ? (
          /* ── Já respondido: última interação ── */
          <div className="flex flex-col items-center gap-3 pt-6">
            <div
              className="w-12 h-12 rounded-full flex items-center justify-center"
              style={{ backgroundColor: ultimaRespondida.resposta_paciente === 'confirmou' ? '#25d36620' : '#dc262620' }}
            >
              {ultimaRespondida.resposta_paciente === 'confirmou'
                ? <Check size={22} className="text-green-400" />
                : <X size={22} className="text-red-400" />}
            </div>
            <div className="text-center">
              <p className="text-[10px] uppercase tracking-wide text-gray-500 mb-1">Última resposta</p>
              <p className={`text-sm font-bold ${ultimaRespondida.resposta_paciente === 'confirmou' ? 'text-green-400' : 'text-red-400'}`}>
                {ultimaRespondida.resposta_paciente === 'confirmou' ? 'Confirmou presença' : 'Cancelou agendamento'}
              </p>
              {ultimaRespondida.respondido_at && (
                <p className="text-[10px] text-gray-600 mt-1">{formatarDataHora(ultimaRespondida.respondido_at)}</p>
              )}
            </div>
          </div>
        ) : (
          /* ── Sem notificações ── */
          <div className="flex flex-col items-center justify-center gap-3 py-10 h-full">
            <Check size={28} className="text-gray-700" />
            <p className="text-xs text-center text-gray-600">Sem notificações pendentes</p>
          </div>
        )}
      </div>

      {/* Footer */}
      <div
        className="flex-shrink-0 flex items-center justify-center px-3 py-2"
        style={{ borderTop: '1px solid rgba(255,255,255,0.05)' }}
      >
        <p className="text-[9px] uppercase tracking-widest text-gray-700 select-none">
          Simulação — Canal WhatsApp
        </p>
      </div>

    </div>
  )
}

// ─── Profissionais: badge, lista, painel ──────────────────────────────────────

const TIPO_CONFIG_PROF = {
  medico:           { label: 'Médico',          bg: 'bg-blue-100 text-blue-700'    },
  tecnico:          { label: 'Técnico',          bg: 'bg-indigo-100 text-indigo-700' },
  clinica_parceira: { label: 'Clínica Parceira', bg: 'bg-violet-100 text-violet-700' },
}

const STATUS_TEXT_PROF = {
  confirmou_disponibilidade:  '✅ Confirmo disponibilidade para esta agenda.',
  reportou_indisponibilidade: '⚠️ Impedimento reportado.',
}

function StatusBadgeProf({ status }) {
  if (status === 'confirmou_disponibilidade')
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-green-100 text-green-700">Confirmado</span>
  if (status === 'reportou_indisponibilidade')
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-red-100 text-red-700">Impedimento</span>
  if (status === null)
    return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-yellow-100 text-yellow-700">Pendente</span>
  return <span className="inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-medium bg-slate-100 text-slate-500">Ag. Notif.</span>
}

function ContactItemProfissional({ prof, active, onClick }) {
  const inicial = (prof.nome ?? '?')[0].toUpperCase()
  const conf    = prof.ultima_conf
  const tipoCfg = TIPO_CONFIG_PROF[prof.tipo] ?? { label: prof.tipo, bg: 'bg-gray-100 text-gray-600' }
  const preview = conf
    ? (conf.appointments?.equipment?.nome ?? 'Confirmação enviada')
    : (prof.especialidade ?? prof.cargo ?? '—')

  return (
    <button
      onClick={onClick}
      className={`w-full text-left flex items-center gap-3 px-4 py-3 transition-colors border-b border-gray-100 ${
        active ? 'bg-[#f0f2f5]' : 'hover:bg-[#f5f6f6]'
      }`}
    >
      <div className="flex-shrink-0 w-10 h-10 rounded-full bg-violet-700 flex items-center justify-center text-white text-sm font-bold">
        {inicial}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex justify-between items-baseline gap-1">
          <p className="text-sm font-medium text-gray-900 truncate">{prof.nome}</p>
          <span className="text-[10px] text-gray-400 flex-shrink-0">
            {conf?.enviado_at ? formatarDataRelativa(conf.enviado_at) : ''}
          </span>
        </div>
        <div className="flex items-center justify-between mt-0.5 gap-1">
          <p className="text-xs text-gray-500 truncate">{preview}</p>
          <StatusBadgeProf status={conf ? conf.status_resposta : undefined} />
        </div>
        <span className={`mt-0.5 inline-flex items-center px-1.5 py-0.5 rounded-full text-[9px] font-medium ${tipoCfg.bg}`}>
          {tipoCfg.label}
        </span>
      </div>
    </button>
  )
}

function ProfBubble({ text, time }) {
  return (
    <div className="flex justify-start mb-2">
      <div className="max-w-[65%]">
        <div className="bg-white rounded-lg rounded-tl-none px-3 py-2 shadow-sm text-sm text-gray-900 border border-gray-100 whitespace-pre-wrap">
          {text}
        </div>
        <p className="text-[10px] text-gray-400 mt-0.5">{time}</p>
      </div>
    </div>
  )
}

function PainelProfissional({ prof, pendingConf, saving, onConfirmar, onImpedimento }) {
  const [showMotivo, setShowMotivo] = useState(false)
  const [motivo, setMotivo]         = useState('')

  useEffect(() => {
    setShowMotivo(false)
    setMotivo('')
  }, [pendingConf?.id])

  const inicial = (prof?.nome ?? '?')[0].toUpperCase()

  return (
    <div className="w-80 flex-shrink-0 flex flex-col overflow-hidden" style={{ backgroundColor: '#1a1a2e' }}>

      {/* Header */}
      <div
        className="flex items-center gap-3 px-4 py-3 flex-shrink-0"
        style={{ backgroundColor: '#3b0764' }}
      >
        <div className="w-9 h-9 rounded-full bg-violet-500 flex items-center justify-center text-white text-sm font-bold flex-shrink-0">
          {inicial}
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-semibold text-white truncate">{prof?.nome || '—'}</p>
          <p className="text-[10px] text-violet-300">Canal WhatsApp — Profissional</p>
        </div>
      </div>

      {/* Corpo */}
      <div
        className="flex-1 overflow-y-auto px-3 py-4 flex flex-col gap-3"
        style={{ backgroundColor: '#0d1117' }}
      >
        {pendingConf ? (
          <>
            {/* Mensagem enviada */}
            <div className="flex justify-start">
              <div
                className="max-w-[92%] rounded-lg rounded-tl-none px-3 py-2 shadow-sm text-xs leading-relaxed whitespace-pre-wrap"
                style={{ backgroundColor: '#2d1b4e', color: '#e9d5ff', border: '1px solid rgba(167,139,250,0.2)' }}
              >
                {pendingConf.mensagem ?? '(sem mensagem)'}
              </div>
            </div>

            {/* Botões de resposta */}
            {!showMotivo ? (
              <div className="flex flex-col gap-2 mt-1">
                <button
                  onClick={() => onConfirmar(pendingConf)}
                  disabled={saving}
                  className="w-full py-3 rounded-xl text-sm font-bold text-white transition-all disabled:opacity-50 active:scale-95"
                  style={{ backgroundColor: '#6d28d9' }}
                >
                  {saving
                    ? <Loader size={14} className="animate-spin mx-auto" />
                    : '1  ✅  CONFIRMAR DISPONIBILIDADE'}
                </button>
                <button
                  onClick={() => setShowMotivo(true)}
                  disabled={saving}
                  className="w-full py-3 rounded-xl text-sm font-bold text-white bg-red-700 hover:bg-red-800 transition-all disabled:opacity-50 active:scale-95"
                >
                  2  ⚠️  REPORTAR IMPEDIMENTO
                </button>
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                <div
                  className="flex items-start gap-2 rounded-xl px-3 py-2.5"
                  style={{ backgroundColor: '#3b0000', border: '1px solid rgba(220,38,38,0.4)' }}
                >
                  <ShieldAlert size={13} className="text-red-400 flex-shrink-0 mt-0.5" />
                  <p className="text-[11px] text-red-300 leading-snug">
                    Descreva o motivo. Os pacientes agendados serão alertados.
                  </p>
                </div>
                <select
                  className="w-full border border-gray-600 rounded px-2 py-2 text-xs text-gray-200 bg-gray-800 focus:outline-none focus:ring-1 focus:ring-red-400"
                  value={motivo}
                  onChange={(e) => setMotivo(e.target.value)}
                >
                  <option value="">Selecione o motivo…</option>
                  <option value="Equipamento em manutenção">Equipamento em manutenção</option>
                  <option value="Ausência do profissional">Ausência do profissional</option>
                  <option value="Falta de insumos">Falta de insumos</option>
                  <option value="Agenda suspensa">Agenda suspensa</option>
                  <option value="Outro imprevisto">Outro imprevisto</option>
                </select>
                <button
                  disabled={!motivo || saving}
                  onClick={() => { setShowMotivo(false); onImpedimento(pendingConf, motivo) }}
                  className="w-full px-2 py-2 text-xs font-bold text-white bg-red-700 rounded hover:bg-red-800 disabled:opacity-40 transition-colors"
                >
                  {saving ? <Loader size={12} className="animate-spin mx-auto" /> : 'CONFIRMAR IMPEDIMENTO'}
                </button>
                <button
                  onClick={() => { setShowMotivo(false); setMotivo('') }}
                  disabled={saving}
                  className="w-full py-2 rounded-xl text-xs font-medium disabled:opacity-40"
                  style={{ color: '#9ca3af', border: '1px solid rgba(255,255,255,0.12)' }}
                >
                  ← VOLTAR
                </button>
              </div>
            )}
          </>
        ) : (
          <div className="flex flex-col items-center justify-center gap-3 py-10 h-full">
            <Building2 size={28} className="text-gray-700" />
            <p className="text-xs text-center text-gray-600">
              {prof ? 'Nenhuma confirmação aguardando resposta' : 'Selecione um profissional'}
            </p>
          </div>
        )}
      </div>

      {/* Footer */}
      <div
        className="flex-shrink-0 flex items-center justify-center px-3 py-2"
        style={{ borderTop: '1px solid rgba(255,255,255,0.05)' }}
      >
        <p className="text-[9px] uppercase tracking-widest text-gray-700 select-none">
          Simulação — Canal WhatsApp Profissional
        </p>
      </div>

    </div>
  )
}

// ─── WhatsappPage ─────────────────────────────────────────────────────────────

export default function WhatsappPage() {
  const { isRegionalIndependencia } = useEscopo()

  // ── Contacts ────────────────────────────────────────────────────────────────
  const [allNotifs, setAllNotifs]           = useState([])
  const [loadingContacts, setLoadingContacts] = useState(true)
  const [search, setSearch]                 = useState('')
  const [selectedPatientId, setSelectedPatientId] = useState(null)

  // ── Chat ────────────────────────────────────────────────────────────────────
  const [chatNotifs, setChatNotifs]   = useState([])
  const [loadingChat, setLoadingChat] = useState(false)
  const [savingId, setSavingId]       = useState(null)
  // Resultado da orquestração local — visível no PainelPaciente
  const [resultadoOrquestracao, setResultadoOrquestracao] = useState(null)

  const chatEndRef = useRef(null)

  // ── Profissionais tab ──────────────────────────────────────────────────────
  const [activeTab, setActiveTab]                   = useState('pacientes')
  const [profContacts, setProfContacts]             = useState([])
  const [loadingProfContacts, setLoadingProfContacts] = useState(false)
  const [selectedProfId, setSelectedProfId]         = useState(null)
  const [profChat, setProfChat]                     = useState([])
  const [loadingProfChat, setLoadingProfChat]       = useState(false)
  const [savingProfId, setSavingProfId]             = useState(null)
  const [profSearch, setProfSearch]                 = useState('')

  // ── Fetch contacts ─────────────────────────────────────────────────────────
  const fetchContacts = useCallback(async () => {
    setLoadingContacts(true)

    // Dois queries paralelos:
    // 1) notification_log — histórico de conversas e estado de resposta
    // 2) appointments ativos futuros — inclui pacientes pendentes que ainda não foram notificados
    const [notifRes, apptRes] = await Promise.all([
      supabase
        .from('notification_log')
        .select(`
          id, patient_id, tipo, canal, enviado_at, respondido_at,
          resposta_paciente, entregue, appointment_id, mensagem,
          patients ( id, nome, cns, telefone ),
          appointments ( scheduled_at, equipment ( nome ) )
        `)
        .order('enviado_at', { ascending: false })
        .limit(300),

      supabase
        .from('appointments')
        .select(`
          id, scheduled_at,
          queue_entries ( patient_id, patients ( id, nome, cns, telefone ), ubs ( nome ) ),
          equipment ( nome )
        `)
        .in('status', ['agendado', 'confirmado'])
        .gte('scheduled_at', new Date().toISOString())
        .order('scheduled_at', { ascending: true })
        .limit(200),
    ])

    // Indexa a notificação mais recente por patient_id
    const notifByPatient = new Map()
    for (const n of (notifRes.data ?? [])) {
      const pid = n.patient_id
      if (!notifByPatient.has(pid)) {
        notifByPatient.set(pid, {
          ...n,
          paciente_nome:    n.patients?.nome ?? '—',
          cns:              n.patients?.cns  ?? null,
          telefone:         n.patients?.telefone ?? null,
          scheduled_at:     n.appointments?.scheduled_at ?? null,
          equipamento_nome: n.appointments?.equipment?.nome ?? null,
        })
      }
    }

    // Constrói lista: um item por patient_id, priorizando agendamentos futuros
    const seen = new Set()
    const merged = []

    for (const appt of (apptRes.data ?? [])) {
      const pid = appt.queue_entries?.patient_id
      if (!pid || seen.has(pid)) continue
      seen.add(pid)

      const notif = notifByPatient.get(pid)
      merged.push({
        id:                notif?.id ?? null,
        patient_id:        pid,
        tipo:              notif?.tipo ?? null,
        canal:             notif?.canal ?? 'whatsapp',
        enviado_at:        notif?.enviado_at ?? appt.scheduled_at,
        respondido_at:     notif?.respondido_at ?? null,
        resposta_paciente: notif?.resposta_paciente ?? 'sem_notificacao',
        entregue:          notif?.entregue ?? null,
        appointment_id:    notif?.appointment_id ?? appt.id,
        mensagem:          notif?.mensagem ?? null,
        paciente_nome:     appt.queue_entries?.patients?.nome ?? notif?.paciente_nome ?? '—',
        cns:               appt.queue_entries?.patients?.cns  ?? notif?.cns  ?? null,
        telefone:          appt.queue_entries?.patients?.telefone ?? notif?.telefone ?? null,
        scheduled_at:      appt.scheduled_at,
        equipamento_nome:  appt.equipment?.nome ?? notif?.equipamento_nome ?? null,
        ubs_nome:          appt.queue_entries?.ubs?.nome ?? null,
      })
    }

    // Adiciona contatos históricos (notificados, mas sem agendamento futuro ativo)
    for (const [pid, notif] of notifByPatient) {
      if (seen.has(pid)) continue
      merged.push(notif)
    }

    // Pendentes primeiro; depois por enviado_at mais recente
    merged.sort((a, b) => {
      const aPend = !a.resposta_paciente
      const bPend = !b.resposta_paciente
      if (aPend !== bPend) return aPend ? -1 : 1
      return new Date(b.enviado_at ?? 0) - new Date(a.enviado_at ?? 0)
    })

    setAllNotifs(merged)
    setLoadingContacts(false)
  }, [])

  useEffect(() => { fetchContacts() }, [fetchContacts])

  // Realtime: atualiza lista de contatos quando notification_log mudar
  useEffect(() => {
    const channel = supabase
      .channel('whatsapp-contacts-rt')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notification_log' }, fetchContacts)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },    fetchContacts)
      .subscribe()
    return () => supabase.removeChannel(channel)
  }, [fetchContacts])

  // ── Contacts derivados (dedup + filtro) ────────────────────────────────────
  // allNotifs já vem deduplicado por patient_id (um item por paciente)
  const contacts = allNotifs.filter(n => {
    if (isRegionalIndependencia &&
        !UBS_REGIONAL_INDEPENDENCIA.some(u => (n.ubs_nome ?? '').includes(u))) return false
    if (!search.trim()) return true
    const q       = search.toLowerCase()
    const qDigits = q.replace(/\D/g, '')
    return (
      n.paciente_nome.toLowerCase().includes(q) ||
      (n.cns && qDigits.length > 0 && String(n.cns).replace(/\D/g, '').includes(qDigits))
    )
  })

  const pendingTotal = allNotifs.filter(n => n.resposta_paciente === null).length

  // ── Profissionais derivados ────────────────────────────────────────────
  const profContactsFiltered = profContacts.filter(p => {
    if (!profSearch.trim()) return true
    const q = profSearch.toLowerCase()
    return (
      p.nome.toLowerCase().includes(q) ||
      (p.especialidade ?? '').toLowerCase().includes(q) ||
      (p.cargo ?? '').toLowerCase().includes(q)
    )
  })
  const profPendingTotal = profContacts.filter(p => p.ultima_conf && !p.ultima_conf.status_resposta).length
  const selectedProf     = profContacts.find(p => p.id === selectedProfId) ?? null
  const pendingProfConf  = [...profChat].reverse().find(c => !c.status_resposta) ?? null

  // ── Paciente selecionado ───────────────────────────────────────────────────
  const selectedPatient = contacts.find(c => c.patient_id === selectedPatientId) ?? null

  // ── Fetch chat para o paciente selecionado ─────────────────────────────────
  const fetchChat = useCallback(async () => {
    if (!selectedPatientId) return
    setLoadingChat(true)
    const { data, error } = await supabase
      .from('notification_log')
      .select(`
        id, patient_id, tipo, enviado_at, respondido_at,
        resposta_paciente, entregue, appointment_id, mensagem,
        appointments ( scheduled_at, equipment ( nome ) )
      `)
      .eq('patient_id', selectedPatientId)
      .order('enviado_at', { ascending: true })

    if (!error) {
      setChatNotifs((data ?? []).map(n => ({
        ...n,
        scheduled_at:     n.appointments?.scheduled_at ?? null,
        equipamento_nome: n.appointments?.equipment?.nome ?? null,
        // paciente_nome injected from contact
        paciente_nome:    selectedPatient?.paciente_nome ?? '—',
      })))
    }
    setLoadingChat(false)
  // selectedPatient não é dep — usamos selectedPatientId que é estável
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedPatientId])

  useEffect(() => {
    setResultadoOrquestracao(null)
    fetchChat()
  }, [fetchChat])

  // Realtime: escuta mudanças no chat do paciente selecionado
  useEffect(() => {
    if (!selectedPatientId) return
    const channel = supabase
      .channel(`whatsapp-chat-rt-${selectedPatientId}`)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'notification_log',
        filter: `patient_id=eq.${selectedPatientId}`,
      }, fetchChat)
      .subscribe()
    return () => supabase.removeChannel(channel)
  }, [selectedPatientId, fetchChat])

  // Auto-scroll ao final do chat
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [chatNotifs])

  // ── Selecionar contato ────────────────────────────────────────────────────
  function handleSelectContact(patientId) {
    setSelectedPatientId(patientId)
  }

  // ── Confirmar presença ────────────────────────────────────────────────────
  async function handleConfirmar(notif) {
    setSavingId(notif.id)
    try {
      await supabase
        .from('notification_log')
        .update({ resposta_paciente: 'confirmou', respondido_at: new Date().toISOString() })
        .eq('id', notif.id)

      if (notif.appointment_id) {
        await supabase
          .from('appointments')
          .update({ status: 'confirmado' })
          .eq('id', notif.appointment_id)
      }
      setResultadoOrquestracao({ tipo: 'confirmou', nomeConvocado: null })
    } finally {
      await Promise.all([fetchChat(), fetchContacts()])
      setSavingId(null)
    }
  }

  // ── Cancelar: executa cancelamento + orquestração ─────────────────────────
  async function handleCancelarConfirmado(notif) {
    setSavingId(notif.id)
    try {
      await supabase
        .from('notification_log')
        .update({ resposta_paciente: 'cancelou', respondido_at: new Date().toISOString() })
        .eq('id', notif.id)

      if (notif.appointment_id) {
        await supabase
          .from('appointments')
          .update({ status: 'cancelado' })
          .eq('id', notif.appointment_id)

        const { nomeConvocado } = await executarReaproveitamento(notif.appointment_id)
        setResultadoOrquestracao({ tipo: 'cancelou', nomeConvocado: nomeConvocado ?? null })
      }
    } finally {
      await Promise.all([fetchChat(), fetchContacts()])
      setSavingId(null)
    }
  }

  // ── Profissionais: fetch contatos ───────────────────────────────────────
  const fetchProfContacts = useCallback(async () => {
    setLoadingProfContacts(true)
    const [profsRes, confsRes] = await Promise.all([
      supabase
        .from('profissionais')
        .select('id, nome, tipo, especialidade, cargo, telefone')
        .eq('ativo', true)
        .order('nome'),
      supabase
        .from('professional_confirmations')
        .select(`
          id, profissional_id, appointment_id, status_resposta,
          enviado_at, respondido_at, mensagem,
          appointments ( scheduled_at, equipment ( nome, ubs ( nome ) ) )
        `)
        .order('enviado_at', { ascending: false })
        .limit(500),
    ])
    const confByProf = new Map()
    for (const c of (confsRes.data ?? [])) {
      if (!confByProf.has(c.profissional_id)) confByProf.set(c.profissional_id, c)
    }
    const merged = (profsRes.data ?? []).map(p => ({
      ...p,
      ultima_conf: confByProf.get(p.id) ?? null,
    }))
    merged.sort((a, b) => {
      const aPend = a.ultima_conf && !a.ultima_conf.status_resposta
      const bPend = b.ultima_conf && !b.ultima_conf.status_resposta
      if (aPend !== bPend) return aPend ? -1 : 1
      return (b.ultima_conf?.enviado_at ?? '').localeCompare(a.ultima_conf?.enviado_at ?? '')
    })
    setProfContacts(merged)
    setLoadingProfContacts(false)
  }, [])

  useEffect(() => { fetchProfContacts() }, [fetchProfContacts])

  useEffect(() => {
    const ch = supabase
      .channel('whatsapp-prof-contacts-rt')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'professional_confirmations' }, fetchProfContacts)
      .subscribe()
    return () => supabase.removeChannel(ch)
  }, [fetchProfContacts])

  // ── Profissionais: fetch chat ──────────────────────────────────────────
  const fetchProfChat = useCallback(async () => {
    if (!selectedProfId) return
    setLoadingProfChat(true)
    const { data } = await supabase
      .from('professional_confirmations')
      .select(`
        id, appointment_id, profissional_id, status_resposta,
        motivo_indisponibilidade, enviado_at, respondido_at, mensagem,
        appointments ( scheduled_at, equipment ( nome, ubs ( nome ) ) )
      `)
      .eq('profissional_id', selectedProfId)
      .order('enviado_at', { ascending: true })
    setProfChat(data ?? [])
    setLoadingProfChat(false)
  }, [selectedProfId])

  useEffect(() => {
    setProfChat([])
    fetchProfChat()
  }, [fetchProfChat])

  useEffect(() => {
    if (!selectedProfId) return
    const ch = supabase
      .channel(`whatsapp-prof-chat-rt-${selectedProfId}`)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'professional_confirmations',
        filter: `profissional_id=eq.${selectedProfId}`,
      }, fetchProfChat)
      .subscribe()
    return () => supabase.removeChannel(ch)
  }, [selectedProfId, fetchProfChat])

  // ── Profissionais: handlers ────────────────────────────────────────────
  async function handleConfirmarProf(conf) {
    setSavingProfId(conf.id)
    try {
      await supabase
        .from('professional_confirmations')
        .update({ status_resposta: 'confirmou_disponibilidade', respondido_at: new Date().toISOString() })
        .eq('id', conf.id)
    } finally {
      await Promise.all([fetchProfChat(), fetchProfContacts()])
      setSavingProfId(null)
    }
  }

  async function handleImpedimentoProf(conf, motivo) {
    setSavingProfId(conf.id)
    try {
      await supabase
        .from('professional_confirmations')
        .update({
          status_resposta:          'reportou_indisponibilidade',
          motivo_indisponibilidade: motivo,
          respondido_at:            new Date().toISOString(),
        })
        .eq('id', conf.id)
    } finally {
      await Promise.all([fetchProfChat(), fetchProfContacts()])
      setSavingProfId(null)
    }
  }

  // Notificação pendente: sem resposta e agendamento ainda no futuro (ou sem data)
  const pendingNotif = [...chatNotifs].reverse().find(n =>
    !n.resposta_paciente &&
    (!n.scheduled_at || new Date(n.scheduled_at) > new Date())
  ) ?? null

  // ── Render ──────────────────────────────────────────────────────────────────
  return (
    <div className="flex -m-6 overflow-hidden rounded-none" style={{ height: 'calc(100vh - 44px)' }}>

      {/* ── COLUNA ESQUERDA: Lista de contatos ─────────────────────────────── */}
      <div className="w-72 flex-shrink-0 bg-white border-r border-gray-200 flex flex-col" style={{ borderRight: '1px solid #e9edef' }}>

        {/* Header */}
        <div className="px-4 pt-4 pb-3" style={{ backgroundColor: '#f0f2f5', borderBottom: '1px solid #e9edef' }}>
          <div className="flex items-center gap-2 mb-3">
            <div className="w-9 h-9 rounded-full bg-green-700 flex items-center justify-center flex-shrink-0">
              <MessageSquare size={16} className="text-white" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-gray-900">SUS Raio-X Bot</p>
              <p className="text-[10px] text-gray-500">Central de Comunicação</p>
            </div>
            {(activeTab === 'pacientes' ? pendingTotal : profPendingTotal) > 0 && (
              <span className={`badge text-white text-[10px] font-bold ${activeTab === 'pacientes' ? 'bg-green-600' : 'bg-violet-600'}`}>
                {activeTab === 'pacientes' ? pendingTotal : profPendingTotal}
              </span>
            )}
          </div>
          {/* Tabs */}
          <div className="flex rounded-lg overflow-hidden mb-3 border border-gray-200">
            <button
              onClick={() => setActiveTab('pacientes')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs font-medium transition-colors ${
                activeTab === 'pacientes' ? 'bg-green-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'
              }`}
            >
              <Users size={11} />
              Pacientes
            </button>
            <button
              onClick={() => setActiveTab('profissionais')}
              className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs font-medium transition-colors ${
                activeTab === 'profissionais' ? 'bg-violet-600 text-white' : 'bg-white text-gray-600 hover:bg-gray-50'
              }`}
            >
              <Building2 size={11} />
              Profissionais
            </button>
          </div>
          <div className="relative">
            <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input
              value={activeTab === 'pacientes' ? search : profSearch}
              onChange={e => activeTab === 'pacientes' ? setSearch(e.target.value) : setProfSearch(e.target.value)}
              placeholder={activeTab === 'pacientes' ? 'Buscar por nome ou CNS…' : 'Buscar por nome ou especialidade…'}
              className="w-full pl-8 pr-3 py-2 text-xs rounded-lg border-0 focus:outline-none focus:ring-1 focus:ring-green-500"
              style={{ backgroundColor: '#ffffff' }}
            />
          </div>
        </div>

        {/* Lista */}
        <div className="flex-1 overflow-y-auto" style={{ backgroundColor: '#ffffff' }}>
          {activeTab === 'pacientes' ? (
            loadingContacts ? (
              <div className="flex justify-center items-center h-32">
                <Loader size={18} className="animate-spin text-gray-400" />
              </div>
            ) : contacts.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-40 gap-2 px-4 text-center">
                <MessageSquare size={28} className="text-gray-300" />
                <p className="text-xs text-gray-400">
                  {search ? 'Nenhum resultado para a busca' : 'Nenhuma notificação encontrada'}
                </p>
              </div>
            ) : (
              contacts.map(notif => (
                <ContactItem
                  key={notif.patient_id}
                  notif={notif}
                  active={selectedPatientId === notif.patient_id}
                  onClick={() => handleSelectContact(notif.patient_id)}
                />
              ))
            )
          ) : (
            loadingProfContacts ? (
              <div className="flex justify-center items-center h-32">
                <Loader size={18} className="animate-spin text-gray-400" />
              </div>
            ) : profContactsFiltered.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-40 gap-2 px-4 text-center">
                <Building2 size={28} className="text-gray-300" />
                <p className="text-xs text-gray-400">
                  {profSearch ? 'Nenhum resultado para a busca' : 'Nenhum profissional encontrado'}
                </p>
              </div>
            ) : (
              profContactsFiltered.map(prof => (
                <ContactItemProfissional
                  key={prof.id}
                  prof={prof}
                  active={selectedProfId === prof.id}
                  onClick={() => setSelectedProfId(prof.id)}
                />
              ))
            )
          )}
        </div>
      </div>

      {/* ── COLUNA DIREITA: Chat ────────────────────────────────────────────── */}
      {activeTab === 'pacientes' ? (
        !selectedPatientId ? (
          // Estado vazio — Pacientes
          <div className="flex-1 flex flex-col items-center justify-center gap-4" style={{ backgroundColor: '#f0f2f5' }}>
            <div className="w-24 h-24 rounded-full bg-white shadow-md flex items-center justify-center">
              <MessageSquare size={40} className="text-green-600" />
            </div>
            <div className="text-center">
              <p className="text-base font-medium text-gray-700">SUS Raio-X — Comunicação Ativa</p>
              <p className="text-sm text-gray-400 mt-1 max-w-xs">
                Selecione um paciente para ver o histórico ou simule a resposta via WhatsApp
              </p>
            </div>
            {pendingTotal > 0 && (
              <div className="bg-yellow-50 border border-yellow-200 rounded-xl px-5 py-3 text-sm text-yellow-800 text-center">
                ⏳ <strong>{pendingTotal}</strong> notificação{pendingTotal > 1 ? 'ões' : ''} aguardando resposta
              </div>
            )}
          </div>
        ) : (
          <>
          {/* Centro: Chat do Operador */}
          <div className="flex-1 flex flex-col overflow-hidden">
            <div
              className="flex items-center gap-3 px-4 py-2.5 flex-shrink-0"
              style={{ backgroundColor: '#f0f2f5', borderBottom: '1px solid #e9edef' }}
            >
              <div className="w-10 h-10 rounded-full bg-green-700 flex items-center justify-center text-white text-sm font-bold flex-shrink-0">
                {(selectedPatient?.paciente_nome ?? '?')[0].toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-gray-900 truncate">
                  {selectedPatient?.paciente_nome ?? '—'}
                </p>
                <div className="flex items-center gap-1.5 text-[10px] text-gray-500">
                  <span className="w-1.5 h-1.5 rounded-full bg-green-500 inline-block" />
                  Online
                  {selectedPatient?.cns && (
                    <span className="text-gray-400 ml-1">· CNS {mascaraCNS(selectedPatient.cns)}</span>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-3 text-gray-400">
                <Phone size={18} className="cursor-pointer hover:text-gray-600 transition-colors" title="Ligar" />
                <Video size={18} className="cursor-pointer hover:text-gray-600 transition-colors" title="Videochamada" />
                <MoreVertical size={18} className="cursor-pointer hover:text-gray-600 transition-colors" />
              </div>
            </div>
            <div
              className="flex-1 overflow-y-auto px-4 py-3"
              style={{
                backgroundImage: `url("data:image/svg+xml,%3Csvg width='80' height='80' viewBox='0 0 80 80' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23c8c8c8' fill-opacity='0.15'%3E%3Cpath d='M50 50c0-5.5-4.5-10-10-10s-10 4.5-10 10 4.5 10 10 10 10-4.5 10-10zM30 20c0-5.5-4.5-10-10-10S10 14.5 10 20s4.5 10 10 10 10-4.5 10-10zM70 20c0-5.5-4.5-10-10-10s-10 4.5-10 10 4.5 10 10 10 10-4.5 10-10z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
                backgroundColor: '#e5ddd5',
              }}
            >
              {loadingChat ? (
                <div className="flex justify-center items-center h-32">
                  <Loader size={18} className="animate-spin text-gray-600" />
                </div>
              ) : (
                <>
                  {chatNotifs.length === 0 ? (
                    <div className="flex justify-center py-8">
                      <p className="text-[11px] text-gray-600 bg-white/70 px-3 py-1.5 rounded-full shadow-sm">
                        Nenhuma mensagem ainda
                      </p>
                    </div>
                  ) : (
                    <>
                      <DateDivider label="Notificações" />
                      {chatNotifs.map((notif, idx) => {
                        const prev = chatNotifs[idx - 1]
                        const mudouDia = prev
                          ? new Date(prev.enviado_at).toDateString() !== new Date(notif.enviado_at).toDateString()
                          : false
                        return (
                          <div key={notif.id}>
                            {mudouDia && <DateDivider label={formatarDataRelativa(notif.enviado_at)} />}
                            <SysBubble text={gerarMensagemSistema(notif)} time={formatarHora(notif.enviado_at)} delivered={notif.entregue} />
                            {notif.resposta_paciente && (
                              <PatientBubble text={RESPOSTA_TEXT[notif.resposta_paciente] ?? notif.resposta_paciente} time={formatarHora(notif.respondido_at)} />
                            )}
                          </div>
                        )
                      })}
                    </>
                  )}
                  {resultadoOrquestracao?.tipo === 'cancelou' && (
                    <div className="flex justify-center my-3">
                      <div className={`border rounded-xl px-4 py-2 text-xs text-center max-w-sm shadow-sm leading-relaxed ${
                        resultadoOrquestracao.nomeConvocado
                          ? 'bg-emerald-50 border-emerald-200 text-emerald-800'
                          : 'bg-amber-50 border-amber-200 text-amber-700'
                      }`}>
                        {resultadoOrquestracao.nomeConvocado
                          ? `✅ Vaga reaproveitada — ${resultadoOrquestracao.nomeConvocado} convocado da fila`
                          : '⚠️ Vaga liberada — fila vazia para este procedimento/UBS'}
                      </div>
                    </div>
                  )}
                  <div ref={chatEndRef} />
                </>
              )}
            </div>
            <div
              className="flex-shrink-0 flex items-center justify-center px-4 py-3"
              style={{ backgroundColor: '#f0f2f5', borderTop: '1px solid #e9edef' }}
            >
              <p className="text-[10px] text-gray-400 select-none">
                Visão do Operador — mensagens enviadas automaticamente pelo sistema
              </p>
            </div>
          </div>
          <PainelPaciente
            notif={pendingNotif}
            pacienteNome={selectedPatient?.paciente_nome ?? ''}
            saving={!!savingId}
            resultado={resultadoOrquestracao}
            chatNotifs={chatNotifs}
            onConfirmar={handleConfirmar}
            onCancelar={handleCancelarConfirmado}
          />
          </>
        )
      ) : (
        !selectedProfId ? (
          // Estado vazio — Profissionais
          <div className="flex-1 flex flex-col items-center justify-center gap-4" style={{ backgroundColor: '#f0f2f5' }}>
            <div className="w-24 h-24 rounded-full bg-white shadow-md flex items-center justify-center">
              <Building2 size={40} className="text-violet-500" />
            </div>
            <div className="text-center">
              <p className="text-base font-medium text-gray-700">Profissionais e Clínicas</p>
              <p className="text-sm text-gray-400 mt-1 max-w-xs">
                Selecione um profissional ou clínica para ver o histórico de confirmações
              </p>
            </div>
            {profPendingTotal > 0 && (
              <div className="bg-violet-50 border border-violet-200 rounded-xl px-5 py-3 text-sm text-violet-800 text-center">
                ⏳ <strong>{profPendingTotal}</strong> confirmação{profPendingTotal > 1 ? 'ões' : ''} aguardando resposta
              </div>
            )}
          </div>
        ) : (
          <>
          {/* Centro: Chat do Operador — Profissional */}
          <div className="flex-1 flex flex-col overflow-hidden">
            <div
              className="flex items-center gap-3 px-4 py-2.5 flex-shrink-0"
              style={{ backgroundColor: '#f0f2f5', borderBottom: '1px solid #e9edef' }}
            >
              <div className="w-10 h-10 rounded-full bg-violet-700 flex items-center justify-center text-white text-sm font-bold flex-shrink-0">
                {(selectedProf?.nome ?? '?')[0].toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-gray-900 truncate">
                  {selectedProf?.nome ?? '—'}
                </p>
                <div className="flex items-center gap-1.5 text-[10px] text-gray-500">
                  <span className="w-1.5 h-1.5 rounded-full bg-violet-500 inline-block" />
                  {TIPO_CONFIG_PROF[selectedProf?.tipo]?.label ?? selectedProf?.tipo ?? '—'}
                  {selectedProf?.especialidade && (
                    <span className="text-gray-400 ml-1">· {selectedProf.especialidade}</span>
                  )}
                </div>
              </div>
              <div className="flex items-center gap-3 text-gray-400">
                <Phone size={18} className="cursor-pointer hover:text-gray-600 transition-colors" title="Ligar" />
                <MoreVertical size={18} className="cursor-pointer hover:text-gray-600 transition-colors" />
              </div>
            </div>
            <div
              className="flex-1 overflow-y-auto px-4 py-3"
              style={{
                backgroundImage: `url("data:image/svg+xml,%3Csvg width='80' height='80' viewBox='0 0 80 80' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23c8c8c8' fill-opacity='0.15'%3E%3Cpath d='M50 50c0-5.5-4.5-10-10-10s-10 4.5-10 10 4.5 10 10 10 10-4.5 10-10zM30 20c0-5.5-4.5-10-10-10S10 14.5 10 20s4.5 10 10 10 10-4.5 10-10zM70 20c0-5.5-4.5-10-10-10s-10 4.5-10 10 4.5 10 10 10 10-4.5 10-10z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
                backgroundColor: '#e5ddd5',
              }}
            >
              {loadingProfChat ? (
                <div className="flex justify-center items-center h-32">
                  <Loader size={18} className="animate-spin text-gray-600" />
                </div>
              ) : profChat.length === 0 ? (
                <div className="flex justify-center py-8">
                  <p className="text-[11px] text-gray-600 bg-white/70 px-3 py-1.5 rounded-full shadow-sm">
                    Nenhuma confirmação enviada ainda
                  </p>
                </div>
              ) : (
                <>
                  <DateDivider label="Confirmações" />
                  {profChat.map((conf, idx) => {
                    const prev = profChat[idx - 1]
                    const mudouDia = prev
                      ? new Date(prev.enviado_at).toDateString() !== new Date(conf.enviado_at).toDateString()
                      : false
                    const respText = conf.status_resposta
                      ? (STATUS_TEXT_PROF[conf.status_resposta] ?? conf.status_resposta) +
                        (conf.motivo_indisponibilidade ? `\nMotivo: ${conf.motivo_indisponibilidade}` : '')
                      : null
                    return (
                      <div key={conf.id}>
                        {mudouDia && <DateDivider label={formatarDataRelativa(conf.enviado_at)} />}
                        <SysBubble text={conf.mensagem ?? '(sem mensagem)'} time={formatarHora(conf.enviado_at)} delivered />
                        {respText && <ProfBubble text={respText} time={formatarHora(conf.respondido_at)} />}
                      </div>
                    )
                  })}
                </>
              )}
            </div>
            <div
              className="flex-shrink-0 flex items-center justify-center px-4 py-3"
              style={{ backgroundColor: '#f0f2f5', borderTop: '1px solid #e9edef' }}
            >
              <p className="text-[10px] text-gray-400 select-none">
                Visão do Operador — confirmações de disponibilidade
              </p>
            </div>
          </div>
          <PainelProfissional
            prof={selectedProf}
            pendingConf={pendingProfConf}
            saving={!!savingProfId}
            onConfirmar={handleConfirmarProf}
            onImpedimento={handleImpedimentoProf}
          />
          </>
        )
      )}
    </div>
  )
}
