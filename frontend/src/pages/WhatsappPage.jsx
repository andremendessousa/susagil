import { useState, useEffect, useCallback, useRef } from 'react'
import {
  MessageSquare, Search, CheckCheck, Clock, X, Send,
  Bot, Phone, Video, MoreVertical, Loader, Check,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { executarReaproveitamento } from '../lib/orquestracao'

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

// Gera texto da mensagem do sistema a partir do notification_log
function gerarMensagemSistema(notif) {
  if (notif.mensagem) return notif.mensagem
  const nome     = notif.paciente_nome ?? 'paciente'
  const proc     = notif.equipamento_nome ?? 'procedimento'
  const dataStr  = notif.scheduled_at ? formatarDataHora(notif.scheduled_at) : 'data a confirmar'
  const prefixos = {
    '72h':           '⏰ Lembrete (72h)',
    '24h':           '⚡ Urgente (24h)',
    '2h':            '🚨 Confirmação final (2h)',
    lembrete_manual: '📋 Lembrete',
  }
  const prefixo = prefixos[notif.tipo] ?? '📢 Aviso'
  return `${prefixo}: Olá, ${nome}! Você tem ${proc} agendado para ${dataStr}.\n\nPor favor, confirme sua presença respondendo *SIM* ou *CANCELAR*.`
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

// ─── Badge de resposta ────────────────────────────────────────────────────────

function RespostaBadge({ resposta }) {
  if (resposta === 'confirmou')
    return <span className="badge bg-green-100 text-green-700 text-[10px]">confirmou</span>
  if (resposta === 'cancelou')
    return <span className="badge bg-red-100 text-red-700 text-[10px]">cancelou</span>
  return <span className="badge bg-yellow-100 text-yellow-700 text-[10px]">pendente</span>
}

// ─── ContactItem ──────────────────────────────────────────────────────────────

function ContactItem({ notif, active, onClick }) {
  const inicial = (notif.paciente_nome ?? '?')[0].toUpperCase()
  const preview = notif.resposta_paciente
    ? RESPOSTA_TEXT[notif.resposta_paciente]
    : TIPO_LABEL[notif.tipo] ?? notif.tipo

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
          <span className={`text-[10px] flex-shrink-0 ${!notif.resposta_paciente ? 'text-green-700 font-semibold' : 'text-gray-400'}`}>
            {formatarDataRelativa(notif.enviado_at)}
          </span>
        </div>
        <div className="flex items-center justify-between mt-0.5 gap-1">
          <p className="text-xs text-gray-500 truncate">{preview}</p>
          <RespostaBadge resposta={notif.resposta_paciente} />
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

// Balão de evento do sistema (amarelo, centralizado)
function EventBubble({ text }) {
  return (
    <div className="flex justify-center my-3">
      <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-2 text-xs text-amber-800 text-center max-w-sm shadow-sm leading-relaxed">
        {text}
      </div>
    </div>
  )
}

// Balão do bot (azul, esquerda, com ícone de robô)
function BotBubble({ text, time }) {
  return (
    <div className="flex justify-start mb-2 gap-2 items-end">
      <div className="flex-shrink-0 w-7 h-7 rounded-full bg-blue-600 flex items-center justify-center mb-0.5">
        <Bot size={13} className="text-white" />
      </div>
      <div className="max-w-[60%]">
        <div className="bg-white border border-blue-100 rounded-lg rounded-tl-none px-3 py-2 shadow-sm text-sm text-gray-900 whitespace-pre-wrap">
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

// ─── WhatsappPage ─────────────────────────────────────────────────────────────

export default function WhatsappPage() {
  // ── Contacts ────────────────────────────────────────────────────────────────
  const [allNotifs, setAllNotifs]           = useState([])
  const [loadingContacts, setLoadingContacts] = useState(true)
  const [search, setSearch]                 = useState('')
  const [selectedPatientId, setSelectedPatientId] = useState(null)

  // ── Chat ────────────────────────────────────────────────────────────────────
  const [chatNotifs, setChatNotifs]   = useState([])
  const [loadingChat, setLoadingChat] = useState(false)
  const [savingId, setSavingId]       = useState(null)

  // Mensagens de evento local (orquestração) — não persistidas no banco
  const [eventMsgs, setEventMsgs]     = useState({}) // { [notif.id]: string }

  // ── Bot / input livre ───────────────────────────────────────────────────────
  const [inputText, setInputText]     = useState('')
  const [botMessages, setBotMessages] = useState([]) // { text, time, isBotReply }
  const [botLoading, setBotLoading]   = useState(false)

  const chatEndRef  = useRef(null)
  const inputRef    = useRef(null)

  // ── Fetch contacts ─────────────────────────────────────────────────────────
  const fetchContacts = useCallback(async () => {
    setLoadingContacts(true)
    const { data, error } = await supabase
      .from('notification_log')
      .select(`
        id, patient_id, tipo, canal, enviado_at, respondido_at,
        resposta_paciente, entregue, appointment_id, mensagem,
        patients ( id, nome, cns, telefone ),
        appointments ( scheduled_at, equipment ( nome ) )
      `)
      .order('enviado_at', { ascending: false })
      .limit(300)

    if (!error) {
      const normalized = (data ?? []).map(n => ({
        ...n,
        paciente_nome:    n.patients?.nome ?? '—',
        cns:              n.patients?.cns  ?? null,
        telefone:         n.patients?.telefone ?? null,
        scheduled_at:     n.appointments?.scheduled_at ?? null,
        equipamento_nome: n.appointments?.equipment?.nome ?? null,
      }))
      setAllNotifs(normalized)
    }
    setLoadingContacts(false)
  }, [])

  useEffect(() => { fetchContacts() }, [fetchContacts])

  // Realtime: atualiza lista de contatos quando notification_log mudar
  useEffect(() => {
    const channel = supabase
      .channel('whatsapp-contacts-rt')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notification_log' }, fetchContacts)
      .subscribe()
    return () => supabase.removeChannel(channel)
  }, [fetchContacts])

  // ── Contacts derivados (dedup + filtro) ────────────────────────────────────
  const contacts = deduplicarPorPaciente(allNotifs).filter(n => {
    if (!search.trim()) return true
    const q = search.toLowerCase()
    return (
      n.paciente_nome.toLowerCase().includes(q) ||
      (n.cns && String(n.cns).replace(/\D/g, '').includes(q.replace(/\D/g, '')))
    )
  })

  const pendingTotal = allNotifs.filter(n => !n.resposta_paciente).length

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
    setBotMessages([])
    setEventMsgs({})
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
  }, [chatNotifs, botMessages, eventMsgs])

  // ── Selecionar contato ────────────────────────────────────────────────────
  function handleSelectContact(patientId) {
    setSelectedPatientId(patientId)
    setTimeout(() => inputRef.current?.focus(), 100)
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
    } finally {
      setSavingId(null)
      await Promise.all([fetchChat(), fetchContacts()])
    }
  }

  // ── Cancelar e acionar orquestração ───────────────────────────────────────
  async function handleCancelar(notif) {
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

        const { nomeConvocado, erro } = await executarReaproveitamento(notif.appointment_id)

        const msg = nomeConvocado
          ? `⚠️ Vaga liberada. Motor de orquestração convocou automaticamente ${nomeConvocado} do topo da fila.`
          : erro
            ? `⚠️ Vaga liberada. Orquestração não pôde convocar próximo: ${erro}`
            : '⚠️ Vaga liberada. Nenhum paciente aguardando na fila para este procedimento no momento.'

        setEventMsgs(prev => ({ ...prev, [notif.id]: msg }))
      }
    } finally {
      setSavingId(null)
      await Promise.all([fetchChat(), fetchContacts()])
    }
  }

  // ── Bot: consulta por CNS ou mensagem livre ────────────────────────────────
  async function handleSend() {
    const text = inputText.trim()
    if (!text || botLoading) return
    setInputText('')

    const hora = formatarHora(new Date().toISOString())
    const digits = text.replace(/\D/g, '')

    if (digits.length === 15) {
      // CNS detectado — modo bot
      setBotMessages(prev => [...prev, { text, time: hora, isBotReply: false }])
      setBotLoading(true)

      setTimeout(async () => {
        try {
          const { data: patient } = await supabase
            .from('patients')
            .select('id, nome')
            .eq('cns', digits)
            .maybeSingle()

          if (!patient) {
            setBotMessages(prev => [...prev, {
              text: `Não encontrei nenhum paciente com o CNS ${mascaraCNS(digits)} no sistema. Verifique o número e tente novamente.`,
              time: formatarHora(new Date().toISOString()),
              isBotReply: true,
            }])
            return
          }

          // Posição na fila — filtra por procedimento do paciente
          const { data: filaItems } = await supabase
            .from('v_dashboard_fila')
            .select('patient_id, nome_grupo_procedimento, prioridade_codigo, data_solicitacao_sisreg, dias_na_fila')
            .eq('status_local', 'aguardando')
            .eq('patient_id', patient.id)
            .order('prioridade_codigo', { ascending: true })
            .limit(1)

          const entrada = filaItems?.[0] ?? null

          if (!entrada) {
            setBotMessages(prev => [...prev, {
              text: `Olá, ${patient.nome}! 👋\n\nNão encontrei sua solicitação na fila de espera. Seu pedido pode estar já agendado ou realizado.\n\nConsulte o serviço de regulação para mais informações.`,
              time: formatarHora(new Date().toISOString()),
              isBotReply: true,
            }])
            return
          }

          // Calcular posição relativa dentro do procedimento
          const { data: todos } = await supabase
            .from('v_dashboard_fila')
            .select('patient_id')
            .eq('status_local', 'aguardando')
            .eq('nome_grupo_procedimento', entrada.nome_grupo_procedimento)
            .order('prioridade_codigo', { ascending: true })
            .order('data_solicitacao_sisreg', { ascending: true })

          const posicao = ((todos ?? []).findIndex(r => r.patient_id === patient.id) + 1) || '—'
          const diasNaFila = entrada.dias_na_fila ?? 0
          const previsao   = Math.max(1, Math.round(diasNaFila * 0.6))

          setBotMessages(prev => [...prev, {
            text: `Olá, ${patient.nome}! 👋\n\n📋 *Procedimento:* ${entrada.nome_grupo_procedimento ?? '—'}\n🏥 *Posição na fila:* ${posicao}º lugar\n⏳ *Dias aguardando:* ${diasNaFila} dias\n📅 *Previsão estimada:* ${previsao} dias\n\nAssim que uma vaga for liberada, você será notificado automaticamente pelo SUS Montes Claros.`,
            time: formatarHora(new Date().toISOString()),
            isBotReply: true,
          }])
        } catch (err) {
          setBotMessages(prev => [...prev, {
            text: 'Ocorreu um erro ao consultar o sistema. Tente novamente em instantes.',
            time: formatarHora(new Date().toISOString()),
            isBotReply: true,
          }])
          console.error('[BotCNS]', err)
        } finally {
          setBotLoading(false)
        }
      }, 1000)
    } else {
      // Mensagem livre — aparece como balão do sistema
      setBotMessages(prev => [...prev, { text, time: hora, isBotReply: false }])
    }
  }

  // Notificação pendente mais recente do paciente selecionado
  const pendingNotif = [...chatNotifs].reverse().find(n => !n.resposta_paciente) ?? null

  const isCNS = inputText.replace(/\D/g, '').length === 15

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
            {pendingTotal > 0 && (
              <span className="badge bg-green-600 text-white text-[10px] font-bold">
                {pendingTotal}
              </span>
            )}
          </div>
          <div className="relative">
            <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Buscar por nome ou CNS…"
              className="w-full pl-8 pr-3 py-2 text-xs rounded-lg border-0 focus:outline-none focus:ring-1 focus:ring-green-500"
              style={{ backgroundColor: '#ffffff' }}
            />
          </div>
        </div>

        {/* Lista */}
        <div className="flex-1 overflow-y-auto" style={{ backgroundColor: '#ffffff' }}>
          {loadingContacts ? (
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
          )}
        </div>
      </div>

      {/* ── COLUNA DIREITA: Chat ────────────────────────────────────────────── */}
      {!selectedPatientId ? (

        // Estado vazio
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
        <div className="flex-1 flex flex-col overflow-hidden">

          {/* Chat header */}
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

          {/* Área de mensagens */}
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
                {chatNotifs.length === 0 && botMessages.length === 0 ? (
                  <div className="flex justify-center py-8">
                    <p className="text-[11px] text-gray-600 bg-white/70 px-3 py-1.5 rounded-full shadow-sm">
                      Nenhuma mensagem ainda
                    </p>
                  </div>
                ) : (
                  <>
                    <DateDivider label="Notificações" />

                    {chatNotifs.map((notif, idx) => {
                      // Divider quando a data muda
                      const prev = chatNotifs[idx - 1]
                      const mudouDia = prev
                        ? new Date(prev.enviado_at).toDateString() !== new Date(notif.enviado_at).toDateString()
                        : false

                      return (
                        <div key={notif.id}>
                          {mudouDia && <DateDivider label={formatarDataRelativa(notif.enviado_at)} />}

                          {/* Mensagem do sistema */}
                          <SysBubble
                            text={gerarMensagemSistema(notif)}
                            time={formatarHora(notif.enviado_at)}
                            delivered={notif.entregue}
                          />

                          {/* Resposta do paciente */}
                          {notif.resposta_paciente && (
                            <PatientBubble
                              text={RESPOSTA_TEXT[notif.resposta_paciente] ?? notif.resposta_paciente}
                              time={formatarHora(notif.respondido_at)}
                            />
                          )}

                          {/* Evento de orquestração (só se cancelou) */}
                          {eventMsgs[notif.id] && (
                            <EventBubble text={eventMsgs[notif.id]} />
                          )}
                        </div>
                      )
                    })}

                    {/* Mensagens do bot / livres */}
                    {botMessages.length > 0 && (
                      <DateDivider label="Sessão atual" />
                    )}
                    {botMessages.map((m, i) =>
                      m.isBotReply
                        ? <BotBubble key={i} text={m.text} time={m.time} />
                        : <SysBubble key={i} text={m.text} time={m.time} />
                    )}

                    {botLoading && (
                      <div className="flex items-center gap-2 text-xs text-gray-500 pl-1 mb-2">
                        <div className="w-7 h-7 rounded-full bg-blue-600 flex items-center justify-center">
                          <Bot size={13} className="text-white" />
                        </div>
                        <div className="bg-white rounded-lg px-3 py-2 text-sm shadow-sm border border-gray-100 flex items-center gap-1.5">
                          <span className="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce" style={{ animationDelay: '0ms' }} />
                          <span className="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce" style={{ animationDelay: '150ms' }} />
                          <span className="w-1.5 h-1.5 rounded-full bg-gray-400 animate-bounce" style={{ animationDelay: '300ms' }} />
                        </div>
                      </div>
                    )}
                  </>
                )}
                <div ref={chatEndRef} />
              </>
            )}
          </div>

          {/* Botões de ação para notificação pendente */}
          {pendingNotif && (
            <div
              className="flex-shrink-0 px-4 py-2.5 flex flex-col gap-2"
              style={{ backgroundColor: '#f0f2f5', borderTop: '1px solid #e9edef' }}
            >
              <p className="text-[10px] text-gray-500 flex items-center gap-1.5">
                <Clock size={10} />
                Aguardando resposta do paciente — simule a interação:
              </p>
              <div className="flex gap-2">
                <button
                  onClick={() => handleConfirmar(pendingNotif)}
                  disabled={!!savingId}
                  className="flex items-center gap-1.5 px-4 py-2 rounded-full text-xs font-semibold bg-green-600 text-white hover:bg-green-700 transition-colors disabled:opacity-50 shadow-sm"
                >
                  {savingId === pendingNotif.id
                    ? <Loader size={12} className="animate-spin" />
                    : <Check size={12} />}
                  SIM, CONFIRMO
                </button>
                <button
                  onClick={() => handleCancelar(pendingNotif)}
                  disabled={!!savingId}
                  className="flex items-center gap-1.5 px-4 py-2 rounded-full text-xs font-semibold bg-white text-red-600 border border-red-200 hover:bg-red-50 transition-colors disabled:opacity-50 shadow-sm"
                >
                  {savingId === pendingNotif.id
                    ? <Loader size={12} className="animate-spin" />
                    : <X size={12} />}
                  NÃO, CANCELAR
                </button>
              </div>
            </div>
          )}

          {/* Input de mensagem */}
          <div
            className="flex-shrink-0 px-3 py-3 flex items-center gap-2"
            style={{ backgroundColor: '#f0f2f5', borderTop: '1px solid #e9edef' }}
          >
            <div className="flex-1 relative">
              <input
                ref={inputRef}
                value={inputText}
                onChange={e => setInputText(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend() } }}
                placeholder={
                  isCNS
                    ? '✓ CNS detectado — pressione Enter para consultar a fila'
                    : 'Digite um CNS (15 dígitos) para consulta ou envie uma mensagem…'
                }
                className="w-full px-4 py-2.5 text-sm bg-white rounded-full border-0 focus:outline-none focus:ring-1 focus:ring-green-500 pr-10"
              />
              {isCNS && (
                <Bot size={15} className="absolute right-4 top-1/2 -translate-y-1/2 text-blue-500" />
              )}
            </div>
            <button
              onClick={handleSend}
              disabled={!inputText.trim() || botLoading}
              className="w-10 h-10 rounded-full bg-green-600 hover:bg-green-700 flex items-center justify-center transition-colors disabled:opacity-40 shadow-sm flex-shrink-0"
            >
              <Send size={16} className="text-white" />
            </button>
          </div>

        </div>
      )}
    </div>
  )
}
