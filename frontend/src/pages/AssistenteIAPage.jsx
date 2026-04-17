/**
 * AssistenteIAPage — Assistente de Regulação com IA Conversacional
 *
 * Arquitetura 3 camadas:
 *   Camada 1 — Interface React (chat com histórico, input livre, auto-scroll)
 *   Camada 2 — Classificador de intenção (Claude API, chamada 1, ~100 tokens)
 *   Camada 3 — Executor RPC + Narrador (Supabase + Claude API, chamada 2, ~500 tokens)
 *
 * SEGURANÇA: apenas dados agregados são enviados à API Anthropic.
 *            Nunca enviar: nome de paciente, CNS, telefone, dados individuais.
 *
 * DÍVIDA TÉCNICA (produção): mover chamadas à API Anthropic para Edge Function
 *            para não expor VITE_ANTHROPIC_API_KEY no bundle do cliente.
 */

import { useState, useRef, useEffect, useCallback } from 'react'
import { Bot, User, Send, Loader, Sparkles, AlertCircle } from 'lucide-react'
import { supabase } from '../lib/supabase'

// ── Constantes ─────────────────────────────────────────────────────────────────

// Usa proxy Vite em dev (/api/anthropic → https://api.anthropic.com).
// Em produção, substituir pela URL da Edge Function Supabase.
const ANTHROPIC_API_URL = '/api/anthropic/v1/messages'
const MODEL             = 'claude-sonnet-4-20250514'

const MENSAGEM_BOAS_VINDAS = `Olá! Sou o assistente de regulação do SUS Raio-X. Posso ajudar você a entender a situação atual da fila de exames e consultas em Montes Claros.

Você pode me perguntar sobre:
• Situação geral da fila e indicadores
• Equipamentos ociosos ou sobrecarregados
• Absenteísmo por clínica executante
• Tempo de espera por UBS de origem
• Demanda de pacientes de outros municípios
• Recomendações de ação para melhorar os indicadores

Pergunte com suas próprias palavras — por exemplo:
"Como está a fila hoje?", "Qual equipamento está mais parado?" ou "O que está mais urgente?"`

const RESPOSTA_FORA_ESCOPO = `Entendo sua pergunta, mas ela está fora do que consigo analisar com os dados disponíveis no momento. Posso ajudar com:

• Situação geral da fila e indicadores
• Equipamentos ociosos ou sobrecarregados
• Absenteísmo por clínica executante
• Tempo de espera por UBS de origem
• Distribuição de pacientes por município
• Recomendações de ação baseadas nos dados

Tente reformular sua pergunta focando em um desses temas.`

const RESPOSTA_ERRO = `Não consegui acessar os dados neste momento. Verifique sua conexão com a internet e tente novamente em alguns segundos.`

// ── System prompts ──────────────────────────────────────────────────────────────

const SYSTEM_CLASSIFICADOR = `Você é um classificador de intenções para um sistema de gestão de filas do SUS.
Sua função é analisar a pergunta do gestor e classificá-la em uma das categorias abaixo.

Categorias válidas:

- ajuda: perguntas sobre o que você pode fazer, suas capacidades, como funciona, como pode ajudar
  Ex: "o que você faz?", "como funciona?", "quais perguntas posso fazer?", "como pode me ajudar?"

- situacao_geral: visão geral, resumo, indicadores gerais, status da regulação hoje
  Ex: "como está a fila?", "me dá um resumo", "como estamos?", "tudo bem no sistema?", "situação hoje", "quais os indicadores?"

- equipamentos_ociosos: máquinas paradas, subutilizadas, baixa ocupação, folga de capacidade
  Ex: "tem máquina parada?", "aparelhos livres", "o que está subutilizado?", "equipamentos ociosos", "temos folga de capacidade?"

- equipamentos_sobrecarregados: gargalos, sobrecarga, equipamentos lotados, sem vaga
  Ex: "o que está mais cheio?", "onde está o gargalo?", "aparelho lotado", "qual está sobrecarregado?"

- absenteismo_executante: taxa de faltas por hospital, clínica ou equipamento executante
  Ex: "qual hospital tem mais falta?", "quem tem piores faltas?", "absenteísmo por executante", "qual clínica tem mais ausência?", "onde os pacientes mais faltam?"

- espera_ubs: tempo de espera ou situação da fila por UBS encaminhadora ou posto de saúde de origem
  Ex: "como está a espera nas UBSs?", "qual UBS deixa mais esperando?", "onde a fila é maior?", "como está o absenteísmo nas UBSs?", "tempo de espera por posto"
  ATENÇÃO: inclui perguntas sobre "absenteísmo por UBS" — o dado disponível é tempo de espera por UBS de origem.

- detalhe_executante: análise detalhada ou plano para uma unidade específica já mencionada na conversa
  Ex: "detalhe o Aroldo Tourinho", "mostre mais sobre o HU", "como está a ImageMed?", "foque no Hospital Universitário", "me mostre os dados da clínica X"
  Se mencionar nome de unidade, inclua em parametros: {"unidade": "nome mencionado"}

- demanda_municipal: pacientes de outros municípios, macrorregião, origem geográfica
  Ex: "de onde vêm os pacientes?", "pacientes de fora", "outros municípios", "macrorregião", "cidades da região"

- recomendacoes: o que fazer, sugestões prioritárias, ações imediatas, como melhorar os indicadores
  Ex: "o que eu faço?", "por onde começo?", "o que está mais urgente?", "quais as prioridades?", "como melhorar?", "ações recomendadas"

- fora_de_escopo: qualquer coisa que não se encaixe nas categorias acima

Responda APENAS com JSON válido, sem markdown, sem explicação:
{"intencao": "nome_da_categoria", "parametros": {}}

Regras para parametros:
- Período específico (ex: "última semana", "últimos 7 dias"): adicione {"dias": 7}
- Intent detalhe_executante com unidade mencionada: adicione {"unidade": "nome_da_unidade"}
- Combine quando necessário: {"dias": 30, "unidade": "Aroldo Tourinho"}
- Caso contrário: {}`

const SYSTEM_NARRADOR = `Você é um analista de regulação do SUS especializado em gestão de filas de exames de imagem e consultas especializadas. Trabalha na Secretaria Municipal de Saúde de Montes Claros/MG.

Sua função é analisar dados operacionais e explicá-los em linguagem clara para o gestor público, que pode não ser técnico. Use linguagem direta, sem jargão de TI.

--- CONTEXTO DO SISTEMA ---
Município sede: Montes Claros/MG — polo da macrorregião Norte de Minas.
Municípios atendidos via pactuação regional: Claro dos Poções, Janaúba, Bocaiúva, Pirapora, Salinas.
Unidades executantes atuais: Hospital Aroldo Tourinho, Hospital Universitário (HU), ImageMed (terceirizada), Ambulatório de Especialidades.
Siglas: US = Ultrassom | RX = Raio-X | TC = Tomografia Computadorizada | MRI = Ressonância Magnética.
Metas do edital CPSI 004/2026: absenteísmo ≤ 15% | espera ≤ 120 dias | capacidade ≥ 85% | satisfação > 8/10.
Dado "espera por UBS" = tempo médio de espera dos pacientes encaminhados por cada UBS de origem — NÃO é taxa de absenteísmo.

--- REGRAS DE RESPOSTA ---
- Sempre mencione os números relevantes (percentuais, contagens, dias)
- Compare com as metas acima e destaque o que está fora do padrão
- Quando possível, sugira uma ação concreta e viável para o gestor
- Use parágrafos curtos (máximo 3 linhas cada)
- NÃO invente dados — use APENAS os números presentes no JSON fornecido
- Se os dados estiverem vazios, null ou zerados: diga isso honestamente e sugira ampliar o período (ex: "últimos 90 dias")
- Nunca sugira diagnóstico clínico ou conduta médica
- Termine com uma pergunta de follow-up natural

--- REGRA ANTI-ALUCINAÇÃO (CRÍTICA) ---
Em respostas de acompanhamento SEM JSON de dados frescos (ex: pedidos de detalhamento, planos de ação):
- Cite números SOMENTE se eles já foram explicitamente mencionados nas mensagens anteriores desta conversa
- Se precisar de dados que não constam no histórico visível, diga: "Para detalhar isso com precisão precisaria consultar os dados novamente — quer que eu faça isso agora?"
- NUNCA invente percentuais, contagens ou nomes de equipamentos não mencionados`

// ── Mapa de intenções → execução de RPC ────────────────────────────────────────
// Nomes exatos das RPCs conforme existem no Supabase (verificado em useDashboardCharts.js e useDashboardMetrics.js)

async function executarQuery(intencao, parametros) {
  const dias = parametros?.dias || 30

  switch (intencao) {
    case 'situacao_geral': {
      const [absenteismo, espera, confirmacao, reaproveitamento, ocupacao] = await Promise.all([
        supabase.rpc('calcular_absenteismo',            { p_horizonte_dias: dias, p_tipo_atendimento: null }),
        supabase.rpc('calcular_tempo_medio_espera',     { p_horizonte_dias: dias, p_tipo_atendimento: null }),
        supabase.rpc('calcular_taxa_confirmacao_ativa', { p_horizonte_dias: dias, p_tipo_atendimento: null }),
        supabase.rpc('calcular_taxa_reaproveitamento',  { p_horizonte_dias: dias, p_tipo_atendimento: null, p_janela_horas: 48 }),
        supabase.rpc('fn_ocupacao_passada',             { p_dias_atras: dias,     p_tipo_atendimento: null }),
      ])
      const ocupRows = ocupacao.data || []
      const capTotal  = ocupRows.reduce((s, r) => s + Number(r.capacidade_total  ?? 0), 0)
      const realizados = ocupRows.reduce((s, r) => s + Number(r.exames_realizados ?? 0), 0)
      const taxaOcupacao = capTotal > 0 ? Math.round((realizados / capTotal) * 100) : null
      return {
        periodo_dias:         dias,
        absenteismo_pct:      absenteismo.data?.taxa_absenteismo     ?? null,
        espera_media_dias:    espera.data?.espera_atual_dias          ?? null,
        taxa_confirmacao_pct: confirmacao.data?.taxa_confirmacao      ?? null,
        taxa_reaproveitamento_pct: reaproveitamento.data?.taxa_reaproveitamento ?? null,
        taxa_ocupacao_pct:    taxaOcupacao,
        total_equipamentos:   ocupRows.length,
      }
    }

    case 'equipamentos_ociosos': {
      const { data } = await supabase.rpc('fn_ocupacao_passada', { p_dias_atras: dias, p_tipo_atendimento: null })
      return (data || [])
        .filter(e => Number(e.pct_ocupacao ?? e.taxa_ocupacao ?? 0) < 40)
        .map(e => ({
          equipamento: e.equipamento_nome,
          unidade:     e.unidade_nome,
          ocupacao_pct: Number(e.pct_ocupacao ?? e.taxa_ocupacao ?? 0),
          capacidade_total: e.capacidade_total,
          realizados: e.exames_realizados,
        }))
        .sort((a, b) => a.ocupacao_pct - b.ocupacao_pct)
    }

    case 'equipamentos_sobrecarregados': {
      const { data } = await supabase.rpc('fn_ocupacao_passada', { p_dias_atras: dias, p_tipo_atendimento: null })
      return (data || [])
        .filter(e => Number(e.pct_ocupacao ?? e.taxa_ocupacao ?? 0) > 80)
        .map(e => ({
          equipamento: e.equipamento_nome,
          unidade:     e.unidade_nome,
          ocupacao_pct: Number(e.pct_ocupacao ?? e.taxa_ocupacao ?? 0),
          capacidade_total: e.capacidade_total,
          realizados: e.exames_realizados,
        }))
        .sort((a, b) => b.ocupacao_pct - a.ocupacao_pct)
    }

    case 'absenteismo_executante': {
      const { data } = await supabase.rpc('get_absenteismo_por_executante', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de absenteísmo por executante para este período. Tente ampliar o período.', periodo_dias: dias }
      return rows
        .map(e => ({
          equipamento:     e.equipamento_nome,
          unidade:         e.unidade_nome,
          taxa_faltas_pct: e.taxa_absenteismo,
          total_agendado:  e.total_agendado,
          total_faltas:    e.total_faltas,
        }))
        .sort((a, b) => b.taxa_faltas_pct - a.taxa_faltas_pct)
        .slice(0, 10)
    }

    case 'detalhe_executante': {
      // Re-executa get_absenteismo_por_executante, filtrando pela unidade nomeada quando informada.
      // Permite follow-ups como "detalhe o Aroldo Tourinho" sem alucinar dados: a RPC é re-chamada
      // e o filtro é aplicado por correspondência parcial no nome da unidade ou equipamento.
      const { data } = await supabase.rpc('get_absenteismo_por_executante', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const todos = (data || []).map(e => ({
        equipamento:     e.equipamento_nome,
        unidade:         e.unidade_nome,
        taxa_faltas_pct: e.taxa_absenteismo,
        total_agendado:  e.total_agendado,
        total_faltas:    e.total_faltas,
      }))
      if (todos.length === 0) return { aviso: 'Sem dados de absenteísmo para este período.', periodo_dias: dias }
      const unidadeBusca = parametros?.unidade?.toLowerCase?.() ?? null
      if (unidadeBusca) {
        const filtrado = todos.filter(e =>
          e.unidade?.toLowerCase().includes(unidadeBusca) ||
          e.equipamento?.toLowerCase().includes(unidadeBusca)
        )
        return {
          unidade_filtrada: parametros.unidade,
          periodo_dias:     dias,
          aviso: filtrado.length === 0
            ? `Unidade "${parametros.unidade}" não encontrada nos dados — exibindo todos os executantes.`
            : null,
          equipamentos: filtrado.length > 0
            ? filtrado.sort((a, b) => b.taxa_faltas_pct - a.taxa_faltas_pct)
            : todos.sort((a, b) => b.taxa_faltas_pct - a.taxa_faltas_pct),
        }
      }
      return {
        periodo_dias: dias,
        equipamentos: todos.sort((a, b) => b.taxa_faltas_pct - a.taxa_faltas_pct),
      }
    }

    case 'espera_ubs': {
      // RENOMEADO de 'absenteismo_ubs' — o dado real é tempo de espera por UBS de origem, não falta.
      // get_ubs_menor_espera retorna espera média por UBS encaminhadora. Sem impacto nos dashboards.
      const { data } = await supabase.rpc('get_ubs_menor_espera', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de espera por UBS para este período. Tente ampliar o período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        tipo_dado:    'tempo_de_espera_por_ubs_encaminhadora',
        aviso:        'Dado disponível: tempo médio de espera dos pacientes encaminhados por cada UBS de origem — não é taxa de absenteísmo por UBS.',
        ubs: rows
          .map(e => ({
            ubs:               e.ubs_nome,
            municipio:         e.municipio,
            espera_media_dias: e.espera_media_dias,
            total_pacientes:   e.total_pacientes,
          }))
          .sort((a, b) => b.espera_media_dias - a.espera_media_dias)
          .slice(0, 10),
      }
    }

    case 'demanda_municipal': {
      const { data } = await supabase.rpc('get_demanda_por_municipio', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      return (data || [])
        .map(e => ({
          municipio:            e.municipio,
          uf:                   e.uf,
          total_encaminhamentos: e.total_encaminhamentos,
          pct_do_total:         e.pct_do_total,
        }))
        .sort((a, b) => b.total_encaminhamentos - a.total_encaminhamentos)
        .slice(0, 15)
    }

    case 'recomendacoes': {
      const [absenteismo, espera, ocupacao, absExec] = await Promise.all([
        supabase.rpc('calcular_absenteismo',            { p_horizonte_dias: dias, p_tipo_atendimento: null }),
        supabase.rpc('calcular_tempo_medio_espera',     { p_horizonte_dias: dias, p_tipo_atendimento: null }),
        supabase.rpc('fn_ocupacao_passada',             { p_dias_atras: dias,     p_tipo_atendimento: null }),
        supabase.rpc('get_absenteismo_por_executante',  { p_horizonte_dias: dias, p_tipo_atendimento: null }),
      ])
      const ocupRows = ocupacao.data || []
      const capTotal   = ocupRows.reduce((s, r) => s + Number(r.capacidade_total  ?? 0), 0)
      const realizados = ocupRows.reduce((s, r) => s + Number(r.exames_realizados ?? 0), 0)
      return {
        periodo_dias:              dias,
        absenteismo_geral_pct:     absenteismo.data?.taxa_absenteismo  ?? null,
        espera_media_dias:         espera.data?.espera_atual_dias       ?? null,
        taxa_ocupacao_media_pct:   capTotal > 0 ? Math.round((realizados / capTotal) * 100) : null,
        equipamentos_ociosos:      ocupRows.filter(e => Number(e.pct_ocupacao ?? 0) < 40).length,
        equipamentos_sobracarregados: ocupRows.filter(e => Number(e.pct_ocupacao ?? 0) > 80).length,
        top3_mais_faltas: (absExec.data || [])
          .sort((a, b) => b.taxa_absenteismo - a.taxa_absenteismo)
          .slice(0, 3)
          .map(e => ({ equipamento: e.equipamento_nome, taxa_pct: e.taxa_absenteismo })),
      }
    }

    default:
      return null
  }
}

// ── Chamada à API Anthropic ─────────────────────────────────────────────────────

// Aceita userMessage (turno único) OU messagesMultiTurn (conversa completa).
async function chamarAnthropic({ system, userMessage, messagesMultiTurn, maxTokens, temperature }) {
  const apiKey = import.meta.env.VITE_ANTHROPIC_API_KEY
  if (!apiKey) throw new Error('VITE_ANTHROPIC_API_KEY não configurada')

  const mensagens = messagesMultiTurn ?? [{ role: 'user', content: userMessage }]

  const resp = await fetch(ANTHROPIC_API_URL, {
    method: 'POST',
    headers: {
      'content-type':      'application/json',
      'x-api-key':         apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model:       MODEL,
      max_tokens:  maxTokens,
      temperature: temperature ?? 0,
      system,
      messages:    mensagens,
    }),
  })

  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}))
    const msg = err?.error?.message ?? `API error ${resp.status}`
    // Mapeia erros comuns para mensagens em português
    if (msg.includes('credit balance') || msg.includes('billing')) {
      throw new Error('Saldo de créditos Anthropic insuficiente. Acesse console.anthropic.com → Plans & Billing para adicionar créditos.')
    }
    if (msg.includes('invalid x-api-key') || msg.includes('authentication')) {
      throw new Error('Chave de API inválida. Verifique VITE_ANTHROPIC_API_KEY no arquivo .env.local.')
    }
    throw new Error(msg)
  }

  const data = await resp.json()
  return data.content?.[0]?.text ?? ''
}

// ── Componente principal ─────────────────────────────────────────────────────────

const WELCOME_MSG = {
  id:        'welcome',
  role:      'ia',
  text:      MENSAGEM_BOAS_VINDAS,
  timestamp: new Date(),
}

function formatTimestamp(date) {
  return new Intl.DateTimeFormat('pt-BR', { hour: '2-digit', minute: '2-digit' }).format(date)
}

export default function AssistenteIAPage() {
  const [messages, setMessages]  = useState([WELCOME_MSG])
  const [input, setInput]        = useState('')
  const [loading, setLoading]    = useState(false)
  const bottomRef                = useRef(null)
  const inputRef                 = useRef(null)

  // Auto-scroll para última mensagem
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, loading])

  const addMessage = useCallback((role, text) => {
    setMessages(prev => [...prev, { id: `${Date.now()}-${Math.random()}`, role, text, timestamp: new Date() }])
  }, [])

  async function handleSubmit(e) {
    e?.preventDefault()
    const pergunta = input.trim()
    if (!pergunta || loading) return

    setInput('')
    addMessage('gestor', pergunta)
    setLoading(true)

    try {
      // ── Chamada 1: classificar intenção ────────────────────────────────────
      const classificacaoRaw = await chamarAnthropic({
        system:      SYSTEM_CLASSIFICADOR,
        userMessage: pergunta,
        maxTokens:   100,
        temperature: 0,
      })

      let intencao   = 'fora_de_escopo'
      let parametros = {}
      try {
        const parsed = JSON.parse(classificacaoRaw.trim())
        intencao     = parsed.intencao   ?? 'fora_de_escopo'
        parametros   = parsed.parametros ?? {}
      } catch {
        // JSON inválido do classificador → trata como fora de escopo
        console.warn('[AssistenteIA] classificador retornou JSON inválido:', classificacaoRaw)
      }

      // ── Ajuda: descreve as capacidades do assistente ─────────────────────────
      if (intencao === 'ajuda') {
        addMessage('ia', MENSAGEM_BOAS_VINDAS)
        return
      }

      // ── Fora de escopo: se há histórico de conversa, responde em multi-turn ──
      // Isso cobre perguntas de acompanhamento como "detalhe esse ponto" ou
      // "elabore o plano para a UBS X" — o classificador não consegue mapear
      // essas perguntas sem contexto, mas Claude pode respondê-las da conversa.
      if (intencao === 'fora_de_escopo') {
        const historico = messages.filter(m => m.id !== 'welcome')
        if (historico.length > 0) {
          // Monta histórico multi-turn: últimas 6 mensagens + pergunta atual
          const turnosClaude = historico
            .slice(-6)
            .map(m => ({
              role:    m.role === 'ia' ? 'assistant' : 'user',
              content: m.text,
            }))
          turnosClaude.push({ role: 'user', content: pergunta })

          const respostaContinuacao = await chamarAnthropic({
            system:             SYSTEM_NARRADOR,
            messagesMultiTurn:  turnosClaude,
            maxTokens:          700,
            temperature:        0.3,
          })
          addMessage('ia', respostaContinuacao.trim())
          return
        }
        // Sem histórico → resposta padrão de fora de escopo
        addMessage('ia', RESPOSTA_FORA_ESCOPO)
        return
      }

      // ── Executa RPC correspondente à intenção ───────────────────────────────
      let dadosRPC = null
      try {
        dadosRPC = await executarQuery(intencao, parametros)
      } catch (rpcErr) {
        console.error('[AssistenteIA] RPC falhou:', rpcErr)
        addMessage('ia', RESPOSTA_ERRO)
        return
      }

      // ── Chamada 2: narrar os dados em linguagem natural ─────────────────────
      const userMessageNarrador = `O gestor perguntou: "${pergunta}"

Categoria identificada: ${intencao}

Dados retornados do sistema (JSON):
${JSON.stringify(dadosRPC, null, 2)}

Analise estes dados e responda a pergunta do gestor em linguagem natural.`

      const narrativa = await chamarAnthropic({
        system:      SYSTEM_NARRADOR,
        userMessage: userMessageNarrador,
        maxTokens:   600,
        temperature: 0.3,
      })

      addMessage('ia', narrativa.trim())

    } catch (err) {
      const msg = err?.message ?? String(err)
      console.error('[AssistenteIA] erro geral:', msg, err)
      addMessage('ia', `${RESPOSTA_ERRO}\n\n_(Detalhe técnico: ${msg})_`)
    } finally {
      setLoading(false)
      setTimeout(() => inputRef.current?.focus(), 100)
    }
  }

  function handleKeyDown(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSubmit()
    }
  }

  return (
    <div className="flex flex-col h-full max-w-3xl mx-auto">

      {/* Header */}
      <div className="flex items-center gap-3 mb-4 flex-shrink-0">
        <div className="flex items-center gap-2">
          <div className="p-2 bg-blue-50 rounded-lg">
            <Bot size={18} className="text-blue-700" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-base font-semibold text-gray-900">Assistente de Regulação</h1>
              <span className="text-[10px] font-bold bg-emerald-100 text-emerald-700 px-1.5 py-0.5 rounded-full uppercase tracking-wide">
                IA
              </span>
            </div>
            <p className="text-xs text-gray-400">Análise de dados em tempo real · Claude Sonnet</p>
          </div>
        </div>
      </div>

      {/* Área de mensagens */}
      <div className="flex-1 overflow-y-auto space-y-4 pr-1 mb-4">
        {messages.map((msg) => (
          <MensagemBubble key={msg.id} msg={msg} />
        ))}

        {/* Indicador de loading */}
        {loading && (
          <div className="flex items-start gap-3">
            <div className="w-7 h-7 rounded-full bg-blue-50 flex items-center justify-center flex-shrink-0 mt-0.5">
              <Bot size={13} className="text-blue-600" />
            </div>
            <div className="bg-white border border-gray-100 rounded-2xl rounded-tl-sm px-4 py-3 shadow-sm">
              <div className="flex items-center gap-2 text-xs text-gray-400">
                <Loader size={12} className="animate-spin" />
                Analisando dados da regulação…
              </div>
            </div>
          </div>
        )}

        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSubmit} className="flex-shrink-0">
        <div className="flex items-end gap-2 bg-white border border-gray-200 rounded-2xl px-4 py-3 shadow-sm focus-within:border-blue-400 focus-within:ring-1 focus-within:ring-blue-100 transition-all">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder='Pergunte sobre a fila, equipamentos, absenteísmo… Ex: "Como está a fila?"'
            rows={1}
            disabled={loading}
            className="flex-1 resize-none bg-transparent text-sm text-gray-900 placeholder-gray-400 focus:outline-none disabled:opacity-50"
            style={{ maxHeight: '120px' }}
            onInput={(e) => {
              // Auto-expand textarea
              e.target.style.height = 'auto'
              e.target.style.height = Math.min(e.target.scrollHeight, 120) + 'px'
            }}
          />
          <button
            type="submit"
            disabled={!input.trim() || loading}
            className="flex-shrink-0 p-1.5 rounded-xl bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          >
            <Send size={14} />
          </button>
        </div>
        <p className="text-center text-[10px] text-gray-300 mt-1.5">
          Enter para enviar · Shift+Enter para nova linha · Dados reais do Supabase
        </p>
      </form>
    </div>
  )
}

// ── Sub-componente: balão de mensagem ───────────────────────────────────────────

function MensagemBubble({ msg }) {
  const isIA = msg.role === 'ia'

  return (
    <div className={`flex items-start gap-3 ${isIA ? '' : 'flex-row-reverse'}`}>
      {/* Avatar */}
      <div className={`w-7 h-7 rounded-full flex items-center justify-center flex-shrink-0 mt-0.5 ${
        isIA ? 'bg-blue-50' : 'bg-gray-100'
      }`}>
        {isIA
          ? <Bot  size={13} className="text-blue-600" />
          : <User size={13} className="text-gray-500" />
        }
      </div>

      {/* Balão */}
      <div className={`max-w-[85%] ${isIA ? '' : 'items-end flex flex-col'}`}>
        <div className={`rounded-2xl px-4 py-3 text-sm leading-relaxed shadow-sm ${
          isIA
            ? 'bg-white border border-gray-100 rounded-tl-sm text-gray-800'
            : 'bg-blue-600 text-white rounded-tr-sm'
        }`}>
          {isIA
            ? <IAText text={msg.text} />
            : <span className="whitespace-pre-wrap">{msg.text}</span>
          }
        </div>
        <p className={`text-[10px] text-gray-300 mt-1 ${isIA ? 'ml-1' : 'mr-1'}`}>
          {formatTimestamp(msg.timestamp)}
        </p>
      </div>
    </div>
  )
}

// ── Sub-componente: formatação de texto da IA (quebras de linha, bullets) ───────

function IAText({ text }) {
  // Converte \n\n em parágrafos, • em lista, mantém whitespace
  const paragrafos = text.split('\n\n').filter(Boolean)

  return (
    <div className="space-y-2">
      {paragrafos.map((paragrafo, i) => {
        const linhas = paragrafo.split('\n').filter(Boolean)
        const ehLista = linhas.every(l => l.startsWith('•') || l.startsWith('-') || l.startsWith('*'))

        if (ehLista) {
          return (
            <ul key={i} className="space-y-1 pl-1">
              {linhas.map((linha, j) => (
                <li key={j} className="flex items-start gap-1.5">
                  <span className="text-blue-400 mt-0.5 flex-shrink-0">•</span>
                  <span>{linha.replace(/^[•\-\*]\s*/, '')}</span>
                </li>
              ))}
            </ul>
          )
        }

        return (
          <p key={i} className="whitespace-pre-wrap">
            {linhas.join('\n')}
          </p>
        )
      })}
    </div>
  )
}
