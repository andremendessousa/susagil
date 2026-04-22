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
• Absenteísmo e desempenho por clínica executante ou UBS
• Fila ativa e tempo de espera por UBS de origem
• Tipos de exame mais solicitados
• Espera e absenteísmo por município de origem
• Tendência temporal das faltas ao longo dos dias
• Recomendações de ação prioritárias

Notificações — Pacientes:
• "Quantos pacientes foram notificados hoje?"
• "Os pacientes estão respondendo às notificações?"
• "Como está o nível de cancelamento de consultas?"
• "Como está o nível de cancelamento de exames?"
• "Conseguimos recuperar vagas de pacientes que cancelaram?"

Agenda — Profissionais e Clínicas:
• "Os médicos confirmaram disponibilidade pra amanhã?"
• "Tem alguma agenda cancelada ou com impedimento?"
• "Qual clínica ainda não respondeu à notificação?"
• "Quem reportou impedimento esta semana?"

Pergunte com suas próprias palavras — por exemplo:
"Como está a fila hoje?", "Qual UBS tem maior represamento?" ou "Quais exames têm mais demanda?"`

const RESPOSTA_FORA_ESCOPO = `Entendo sua pergunta, mas ela está fora do que consigo analisar com os dados disponíveis no momento. Posso ajudar com:

• Situação geral da fila e indicadores
• Equipamentos ociosos ou sobrecarregados
• Absenteísmo e desempenho por clínica executante ou UBS
• Fila ativa e represamento por UBS ou equipamento
• Tipos de exame mais solicitados
• Espera e absenteísmo por município de origem
• Tendência temporal das faltas
• Recomendações de ação baseadas nos dados
• Notificações de pacientes — taxa de resposta e cancelamentos
• Agenda de profissionais — confirmações e impedimentos

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

- fila_por_ubs: volume de fila ativa (backlog) por UBS de origem, represamento de demanda por unidade de saúde
  Ex: "qual UBS tem maior fila?", "onde tem mais gente esperando?", "demanda represada por unidade", "qual posto tá mais cheio na fila?", "represamento por UBS", "mostre a fila por posto de saúde"

- fila_por_clinica: agenda comprometida ou fila nos equipamentos e clínicas executantes
  Ex: "qual clínica tá mais cheia?", "qual hospital tem mais gente na espera?", "agenda dos equipamentos", "qual executante tem mais compromisso?", "capacidade comprometida por clínica"

- desempenho_ubs: ranking ou score de desempenho das UBSs encaminhadoras, comparativo entre postos
  Ex: "qual UBS tá melhor?", "ranking das UBSs", "desempenho por unidade de saúde", "qual posto tá indo bem?", "quem se sai melhor?", "pontuação das UBSs", "compare as UBSs"

- tipos_exame: quais tipos de exame ou procedimentos são mais solicitados, distribuição por procedimento
  Ex: "quais exames são mais pedidos?", "procedimento mais solicitado", "quais exames têm mais demanda?", "o que é mais requisitado?", "distribuição por tipo de exame", "quais procedimentos lideram?"

- espera_por_municipio: tempo de espera real ou absenteísmo por município de origem do paciente
  Ex: "espera por município?", "quem vem de fora espera quanto?", "como está cada cidade?", "tempo de espera por cidade", "qual município tem mais espera?", "como estão os municípios da região?"
  ATENÇÃO: diferente de demanda_municipal (que conta encaminhamentos) — este calcula espera real por município.

- tendencia_absenteismo: evolução temporal das faltas, gráfico de tendência ao longo dos dias
  Ex: "como a falta evoluiu?", "tendência dos últimos dias", "gráfico de faltas", "absenteísmo tá subindo ou caindo?", "histórico de faltas por dia", "como foi nos últimos 30 dias?"

- exames_por_local: volume de exames efetivamente realizados por local ou equipamento executante
  Ex: "quais locais fizeram mais exames?", "volume por local", "onde realizaram mais?", "produção por equipamento", "qual local produziu mais?", "ranking de produção"

- notificacoes_pacientes: quantidade de notificações enviadas aos pacientes, taxa de resposta, engajamento com as mensagens enviadas via WhatsApp
  Ex: "quantos pacientes foram notificados hoje?", "os pacientes estão respondendo?", "como está a taxa de confirmação dos pacientes?", "quantos responderam às mensagens?", "qual a adesão às notificações?", "os avisos estão funcionando?"

- cancelamentos_vagas: nível de cancelamentos pelos pacientes (consultas ou exames) e recuperação de vagas pelo sistema de reaproveitamento
  Ex: "como está o cancelamento de consultas?", "como está o cancelamento de exames?", "conseguimos recuperar vagas?", "quão eficiente está o reaproveitamento?", "os pacientes estão cancelando muito?", "quantas vagas foram liberadas?"

- agenda_profissionais: confirmação de disponibilidade pelos médicos, técnicos e clínicas parceiras nas próximas 72h; quem confirmou e quem ainda não respondeu à solicitação
  Ex: "os médicos confirmaram pra amanhã?", "tem agenda confirmada?", "qual clínica não respondeu?", "quem ainda não confirmou disponibilidade?", "as clínicas estão confirmando?", "como está a agenda dos profissionais?", "os profissionais responderam a notificação?"

- agenda_indisponibilidades: profissionais ou clínicas que reportaram impedimento, motivos declarados de indisponibilidade
  Ex: "tem agenda cancelada?", "quem reportou impedimento?", "quais profissionais estão indisponíveis?", "qual o motivo dos impedimentos?", "tem algum médico que disse que não pode atender?", "quais são os impedimentos registrados?", "alguém cancelou a agenda?"

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

--- NOTIFICAÇÕES E AGENDA PROFISSIONAL ---
notification_log: comunicações com pacientes via WhatsApp. Campos relevantes: enviado_at, resposta_paciente ("confirmou" | "cancelou" | null = sem resposta), tipo ("72h" | "24h" | "2h" | "lembrete_manual").
professional_confirmations: comunicações com médicos, técnicos e clínicas parceiras. status_resposta: "confirmou_disponibilidade" | "reportou_indisponibilidade" | null (aguardando).
Pacientes protegidos = appointments ativos que coincidiam com slots onde o profissional reportou indisponibilidade — representa deslocamentos evitados pelo aviso prévio do sistema.
Tipos de profissional: medico | tecnico | clinica_parceira (contato institucional do setor/serviço).
Janela padrão de confirmação profissional: próximas 72 horas.

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
- NUNCA invente percentuais, contagens ou nomes de equipamentos não mencionados
- NUNCA invente nomes de pessoas (médicos, gestores, pacientes) — o JSON nunca contém esse dado; qualquer nome inventado é alucinação
- A primeira frase da resposta deve mencionar o período analisado (ex: "Nos últimos 30 dias..." ou "No período de DD/MM a DD/MM...")`

// ── Mapa de intenções → execução de RPC ────────────────────────────────────────
// Nomes exatos das RPCs conforme existem no Supabase (verificado em useDashboardCharts.js e useDashboardMetrics.js)

async function executarQuery(intencao, parametros, diasPadrao = 30) {
  const dias = parametros?.dias || diasPadrao

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

    case 'fila_por_ubs': {
      const { data } = await supabase.rpc('get_fila_por_ubs', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de fila por UBS para este período. Tente ampliar o período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        total_ubs: rows.length,
        ubs: rows.map(e => ({
          ubs_nome:          e.ubs_nome,
          municipio:         e.municipio,
          total_aguardando:  Number(e.total_aguardando),
          pct_do_total:      Number(e.pct_do_total),
          espera_media_dias: Number(e.espera_media_dias),
        })),
      }
    }

    case 'fila_por_clinica': {
      const { data } = await supabase.rpc('get_fila_por_clinica', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de agenda por clínica para este período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        clinicas: rows.map(e => ({
          equipamento:         e.equipamento_nome,
          unidade:             e.unidade_nome,
          municipio:           e.municipio,
          vagas_comprometidas: Number(e.vagas_comprometidas),
          capacidade_periodo:  Number(e.capacidade_periodo),
          pct_carga_fila:      Number(e.pct_carga_fila),
        })),
      }
    }

    case 'desempenho_ubs': {
      const { data } = await supabase.rpc('get_desempenho_por_ubs', {
        p_horizonte_dias: dias,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de desempenho por UBS para este período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        ubs: rows.map(e => ({
          ubs_nome:          e.ubs_nome,
          municipio:         e.municipio,
          absenteismo_pct:   Number(e.absenteismo_pct),
          espera_media_dias: Number(e.espera_media_dias),
          total_atendidos:   Number(e.total_atendidos),
          score_composto:    Number(e.score_composto),
        })),
      }
    }

    case 'tipos_exame': {
      const { data } = await supabase.rpc('get_tipos_exame_solicitados', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de tipos de exame para este período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        exames: rows.map(e => ({
          tipo_exame:         e.tipo_exame,
          total_solicitacoes: Number(e.total_solicitacoes),
          pct_do_total:       Number(e.pct_do_total),
          espera_media_dias:  Number(e.espera_media_dias),
        })),
      }
    }

    case 'espera_por_municipio': {
      const { data } = await supabase.rpc('get_espera_por_municipio', {
        p_horizonte_dias: dias,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de espera por município para este período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        tipo_dado:    'espera_e_absenteismo_por_municipio_de_origem',
        municipios: rows.map(e => ({
          municipio:         e.municipio,
          total_pacientes:   Number(e.total_pacientes),
          espera_media_dias: Number(e.espera_media_dias),
          pct_absenteismo:   Number(e.pct_absenteismo),
        })),
      }
    }

    case 'tendencia_absenteismo': {
      const { data } = await supabase.rpc('get_tendencia_absenteismo', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
        p_media_movel_dias: 7,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de tendência para este período. Tente ampliar o período.', periodo_dias: dias }
      const primeiro = rows[0]
      const ultimo   = rows[rows.length - 1]
      const variacao = (ultimo && primeiro)
        ? (Number(ultimo.taxa ?? 0) - Number(primeiro.taxa ?? 0)).toFixed(1)
        : null
      return {
        periodo_dias:      dias,
        total_pontos:      rows.length,
        taxa_inicial:      Number(primeiro?.taxa ?? 0),
        taxa_final:        Number(ultimo?.taxa   ?? 0),
        variacao_pct:      variacao ? Number(variacao) : null,
        media_movel_final: Number(ultimo?.taxa_media_movel ?? 0),
        serie: rows.map(e => ({
          dia:              e.dia,
          total:            Number(e.total),
          faltas:           Number(e.faltas),
          taxa:             Number(e.taxa),
          taxa_media_movel: Number(e.taxa_media_movel),
        })),
      }
    }

    case 'exames_por_local': {
      const { data } = await supabase.rpc('get_exames_por_local', {
        p_horizonte_dias:   dias,
        p_tipo_atendimento: null,
      })
      const rows = data || []
      if (rows.length === 0) return { aviso: 'Sem dados de exames por local para este período. Tente ampliar o período.', periodo_dias: dias }
      return {
        periodo_dias: dias,
        locais: rows
          .map(e => ({
            equipamento:      e.equipamento_nome,
            unidade:          e.unidade_nome,
            realizados:       Number(e.realizados),
            total_agendado:   Number(e.total_agendado),
            faltas:           Number(e.faltas),
            taxa_absenteismo: Number(e.taxa_absenteismo),
          }))
          .sort((a, b) => b.realizados - a.realizados),
      }
    }

    // ── DOMÍNIO: Notificações de Pacientes ──────────────────────────────────

    case 'notificacoes_pacientes': {
      const [confirmacaoRPC, logsRes] = await Promise.all([
        supabase.rpc('calcular_taxa_confirmacao_ativa', { p_horizonte_dias: dias, p_tipo_atendimento: null }),
        supabase
          .from('notification_log')
          .select('id, tipo, enviado_at, resposta_paciente, respondido_at')
          .gte('enviado_at', new Date(Date.now() - dias * 86_400_000).toISOString())
          .order('enviado_at', { ascending: false }),
      ])
      const logs = logsRes.data || []
      const hoje = new Date(); hoje.setHours(0, 0, 0, 0)
      const notificados_hoje  = logs.filter(n => n.enviado_at && new Date(n.enviado_at) >= hoje).length
      const com_resposta      = logs.filter(n => n.resposta_paciente).length
      const confirmaram       = logs.filter(n => n.resposta_paciente === 'confirmou').length
      const cancelaram        = logs.filter(n => n.resposta_paciente === 'cancelou').length
      const sem_resposta      = logs.filter(n => !n.resposta_paciente).length
      const taxa_resposta_pct = logs.length > 0 ? Math.round(com_resposta / logs.length * 100) : null
      const por_tipo = Object.fromEntries(
        ['72h', '24h', '2h', 'lembrete_manual'].map(t => [t, logs.filter(n => n.tipo === t).length])
      )
      return {
        periodo_dias:         dias,
        total_notificacoes:   logs.length,
        notificados_hoje,
        com_resposta,
        sem_resposta,
        confirmaram,
        cancelaram,
        taxa_resposta_pct,
        taxa_confirmacao_rpc: confirmacaoRPC.data?.taxa_confirmacao ?? null,
        por_tipo,
      }
    }

    case 'cancelamentos_vagas': {
      const [reaprovRes, cancelRes] = await Promise.all([
        supabase.rpc('calcular_taxa_reaproveitamento', {
          p_horizonte_dias:   dias,
          p_tipo_atendimento: null,
          p_janela_horas:     48,
        }),
        supabase
          .from('notification_log')
          .select('id, respondido_at, appointments ( tipo_vaga, equipment ( nome ) )')
          .eq('resposta_paciente', 'cancelou')
          .gte('respondido_at', new Date(Date.now() - dias * 86_400_000).toISOString()),
      ])
      const cancelados = cancelRes.data || []
      const por_tipo = {}
      for (const n of cancelados) {
        const tipo = n.appointments?.tipo_vaga ?? 'outros'
        por_tipo[tipo] = (por_tipo[tipo] || 0) + 1
      }
      return {
        periodo_dias:                 dias,
        total_cancelamentos_paciente: cancelados.length,
        taxa_reaproveitamento_pct:    reaprovRes.data?.taxa_reaproveitamento ?? null,
        cancelamentos_por_tipo:       Object.entries(por_tipo)
          .map(([tipo, count]) => ({ tipo, count }))
          .sort((a, b) => b.count - a.count),
      }
    }

    // ── DOMÍNIO: Agenda de Profissionais ────────────────────────────────────

    case 'agenda_profissionais': {
      const [kpisRes, confirmacoesRes] = await Promise.all([
        supabase.rpc('rpc_kpis_profissionais', { p_horizonte_horas: 72 }),
        supabase
          .from('professional_confirmations')
          .select(`
            id, status_resposta, enviado_at, respondido_at,
            profissionais ( nome, tipo, cargo ),
            appointments ( scheduled_at, equipment ( nome, ubs ( nome ) ) )
          `)
          .order('enviado_at', { ascending: false })
          .limit(60),
      ])
      const confs        = confirmacoesRes.data || []
      const aguardando   = confs.filter(c => !c.status_resposta).length
      const confirmaram_c = confs.filter(c => c.status_resposta === 'confirmou_disponibilidade').length
      const indisp_c     = confs.filter(c => c.status_resposta === 'reportou_indisponibilidade').length
      const sem_resposta_lista = confs
        .filter(c => !c.status_resposta)
        .slice(0, 10)
        .map(c => ({
          nome:          c.profissionais?.nome ?? '—',
          tipo:          c.profissionais?.tipo ?? null,
          equipamento:   c.appointments?.equipment?.nome ?? '—',
          ubs:           c.appointments?.equipment?.ubs?.nome ?? '—',
          agendado_para: c.appointments?.scheduled_at ?? null,
        }))
      return {
        janela_horas: 72,
        kpis: {
          agendas_confirmadas_pct:  kpisRes.data?.agendas_confirmadas_pct ?? null,
          equip_confirmaram:        Number(kpisRes.data?.equip_confirmaram ?? 0),
          equip_com_agenda:         Number(kpisRes.data?.equip_com_agenda  ?? 0),
          indisponibilidades_count: Number(kpisRes.data?.indisponibilidades_count ?? 0),
          pacientes_protegidos:     Number(kpisRes.data?.pacientes_protegidos ?? 0),
        },
        status_geral: {
          total_notificacoes_enviadas: confs.length,
          confirmaram:                confirmaram_c,
          aguardando_resposta:        aguardando,
          reportaram_impedimento:     indisp_c,
        },
        sem_resposta: sem_resposta_lista,
      }
    }

    case 'agenda_indisponibilidades': {
      const { data } = await supabase
        .from('professional_confirmations')
        .select(`
          id, status_resposta, motivo_indisponibilidade, respondido_at,
          profissionais ( nome, tipo, cargo ),
          appointments ( scheduled_at, equipment ( nome, ubs ( nome ) ) )
        `)
        .eq('status_resposta', 'reportou_indisponibilidade')
        .gte('respondido_at', new Date(Date.now() - dias * 86_400_000).toISOString())
        .order('respondido_at', { ascending: false })
      const rows = data || []
      if (rows.length === 0) {
        return { aviso: `Nenhuma indisponibilidade reportada nos últimos ${dias} dias.`, periodo_dias: dias }
      }
      const por_motivo = {}
      for (const r of rows) {
        const m = r.motivo_indisponibilidade ?? 'Não informado'
        por_motivo[m] = (por_motivo[m] || 0) + 1
      }
      return {
        periodo_dias:             dias,
        total_indisponibilidades: rows.length,
        por_motivo:               Object.entries(por_motivo)
          .map(([motivo, count]) => ({ motivo, count }))
          .sort((a, b) => b.count - a.count),
        casos: rows.map(r => ({
          profissional:  r.profissionais?.nome ?? '—',
          tipo:          r.profissionais?.tipo ?? null,
          equipamento:   r.appointments?.equipment?.nome ?? '—',
          ubs:           r.appointments?.equipment?.ubs?.nome ?? '—',
          agendado_para: r.appointments?.scheduled_at ?? null,
          motivo:        r.motivo_indisponibilidade ?? 'Não informado',
          reportado_em:  r.respondido_at,
        })),
      }
    }

    default:
      return null
  }
}

// ── Chamada à API Anthropic ─────────────────────────────────────────────────────

// Aceita userMessage (turno único) OU messagesMultiTurn (conversa completa).
// useCache=true: ativa Prompt Caching para o system prompt (apenas no narrador — ~600 tokens)
async function chamarAnthropic({ system, userMessage, messagesMultiTurn, maxTokens, temperature, useCache }) {
  const apiKey = import.meta.env.VITE_ANTHROPIC_API_KEY
  if (!apiKey) throw new Error('VITE_ANTHROPIC_API_KEY não configurada')

  const mensagens = messagesMultiTurn ?? [{ role: 'user', content: userMessage }]

  // Prompt Caching: serializa system como array quando useCache=true
  const systemArg = useCache
    ? [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }]
    : system

  const resp = await fetch(ANTHROPIC_API_URL, {
    method: 'POST',
    headers: {
      'content-type':      'application/json',
      'x-api-key':         apiKey,
      'anthropic-version': '2023-06-01',
      ...(useCache && { 'anthropic-beta': 'prompt-caching-2024-07-31' }),
    },
    body: JSON.stringify({
      model:       MODEL,
      max_tokens:  maxTokens,
      temperature: temperature ?? 0,
      system:      systemArg,
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

const CHAT_STORAGE_KEY = 'susraiox_chat'

export default function AssistenteIAPage() {
  const [messages, setMessages] = useState(() => {
    try {
      const saved = localStorage.getItem(CHAT_STORAGE_KEY)
      if (!saved) return [WELCOME_MSG]
      return JSON.parse(saved)
        .slice(-30)
        .map(m => ({ ...m, timestamp: new Date(m.timestamp) }))
    } catch { return [WELCOME_MSG] }
  })
  const [input, setInput]        = useState('')
  const [loading, setLoading]    = useState(false)
  const [diasPadrao, setDiasPadrao] = useState(30)
  const bottomRef                = useRef(null)
  const inputRef                 = useRef(null)

  // Persiste histórico no localStorage a cada mudança
  useEffect(() => {
    localStorage.setItem(CHAT_STORAGE_KEY, JSON.stringify(messages))
  }, [messages])

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
        dadosRPC = await executarQuery(intencao, parametros, diasPadrao)
      } catch (rpcErr) {
        console.error('[AssistenteIA] RPC falhou:', rpcErr)
        addMessage('ia', RESPOSTA_ERRO)
        return
      }

      // ── Chamada 2: narrar os dados em linguagem natural ─────────────────────
      const diasEfetivos = parametros?.dias || diasPadrao
      const periodoFim    = new Date().toLocaleDateString('pt-BR')
      const periodoInicio = new Date(Date.now() - diasEfetivos * 86_400_000).toLocaleDateString('pt-BR')

      const userMessageNarrador = `O gestor perguntou: "${pergunta}"

Categoria identificada: ${intencao}
Período de referência dos dados: ${periodoInicio} a ${periodoFim} (últimos ${diasEfetivos} dias)

Dados retornados do sistema (JSON):
${JSON.stringify(dadosRPC, null, 2)}

Analise estes dados e responda a pergunta do gestor em linguagem natural.`

      const narrativa = await chamarAnthropic({
        system:      SYSTEM_NARRADOR,
        userMessage: userMessageNarrador,
        maxTokens:   600,
        temperature: 0.3,
        useCache:    true,
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
        <div className="ml-auto flex items-center gap-2">
          <span className="text-xs text-gray-400">Período:</span>
          <select
            value={diasPadrao}
            onChange={e => setDiasPadrao(Number(e.target.value))}
            className="text-xs border border-gray-200 rounded-md px-2 py-1 text-gray-600 bg-white focus:outline-none focus:ring-1 focus:ring-blue-300"
          >
            <option value={7}>7 dias</option>
            <option value={30}>30 dias</option>
            <option value={60}>60 dias</option>
            <option value={90}>90 dias</option>
          </select>
          <button
            onClick={() => {
              localStorage.removeItem(CHAT_STORAGE_KEY)
              setMessages([WELCOME_MSG])
            }}
            title="Limpar histórico"
            className="text-xs text-gray-400 hover:text-red-500 px-1.5 py-1 rounded transition-colors"
          >
            ✕
          </button>
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
