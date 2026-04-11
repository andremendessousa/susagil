# PROMPTS — SUS Raio-X · GitHub Copilot (Claude Sonnet 4.6)

> Arquivo de referência de prompts do projeto.  
> **Sempre cole o PROMPT-0 no início de cada sessão nova do Copilot.**  
> Execute os prompts em ordem. Aguarde conclusão antes do próximo.

---

## PROMPT-0 · Contexto Mestre (obrigatório em toda sessão)

```
# CONTEXTO DO PROJETO — SUS RAIO-X

## O que é
Camada de inteligência operacional sobre o e-SUS Regulação de Montes Claros (MG).
NÃO somos um sistema de fila. Somos comunicação + monitoramento + analytics
sobre o que o e-SUS já autoriza e agenda.

Edital: CPSI Co.NE nº 004/2026 — Prefeitura de Montes Claros / ENAP / Sudene / BID
Valores: R$200k (CPSI) → R$1,6M (contrato subsequente)

## Fluxo principal (automático)
e-SUS autoriza exame → sync API → nossa fila → WhatsApp paciente →
confirmação → se faltou → vaga redistribuída → próximo da lista avisado

## Formulário manual (exceção, não regra)
Usado apenas para urgências presenciais ou quando API e-SUS indisponível.
Princípio: nunca duplicar trabalho do operador.

## Stack
React 18 + Vite + Tailwind CSS + Supabase (PostgreSQL + Auth + Realtime)
Supabase URL: https://duyabldyygckpxhnnemz.supabase.co

## Estrutura de arquivos
frontend/src/
  components/Layout.jsx          → sidebar azul (#1e3a8a), nav, header
  pages/DashboardPage.jsx        → KPIs do edital + alertas operacionais
  pages/FilaPage.jsx             → fila completa com busca e ações
  pages/MaquinasPage.jsx         → equipamentos com ocupação em tempo real
  pages/LoginPage.jsx            → auth com Supabase
  hooks/useKpis.js               → v_kpis (tempo espera, absenteísmo, capacidade)
  hooks/useQueue.js              → v_dashboard_fila com realtime
  hooks/useEquipment.js          → v_ocupacao_equipamentos com realtime
  hooks/useAuth.js               → autenticação e perfil do operador
  lib/supabase.js                → cliente configurado

## Banco — tabelas relevantes
ubs, equipment, patients, profiles, queue_entries, appointments,
notification_log, sisreg_sync_log
Views: v_dashboard_fila, v_kpis, v_ocupacao_equipamentos

## Indicadores obrigatórios do edital
- Absenteísmo: baseline 35% → meta ≤15%
- Tempo médio espera: meta ≤120 dias
- Aproveitamento capacidade: meta >85%
- Demanda reprimida: monitorada historicamente

## Convenções OBRIGATÓRIAS
- Tailwind apenas — zero CSS inline
- Classes globais: .card .btn-primary .btn-ghost .badge (definidas em index.css)
- Ícones: apenas lucide-react
- Dados: sempre via hooks em src/hooks/
- Labels: português | Variáveis/funções: inglês
- NUNCA reescrever arquivo inteiro para edições parciais
- NUNCA instalar pacotes sem perguntar
```

---

## PROMPT-1 · Login com Supabase Auth ✅ CONCLUÍDO

**Status:** implementado  
**Arquivos criados:** `src/pages/LoginPage.jsx`, `src/hooks/useAuth.js`  
**Arquivos editados:** `src/App.jsx`

**O que foi feito:**
- Tela de login com email + senha usando `supabase.auth.signInWithPassword()`
- Hook `useAuth` com `onAuthStateChange` e busca de perfil em `profiles`
- Guard no `App.jsx`: não autenticado → LoginPage | autenticado → Layout

---

## PROMPT-2 · Modal Novo Encaminhamento ✅ CONCLUÍDO

**Status:** implementado  
**Arquivos criados:** `src/components/NovoEncaminhamentoModal.jsx`  
**Arquivos editados:** `src/pages/FilaPage.jsx`

**O que foi feito:**
- Busca automática de paciente por CNS ao completar 15 dígitos
- Se CNS não existe → INSERT em `patients` antes de inserir na fila
- INSERT em `queue_entries` com status_local: 'aguardando'
- Toast de sucesso com auto-dismiss em 3.5s
- Reposicionamento conceitual: formulário é EXCEÇÃO, não fluxo principal

**Nota conceitual importante:**
Este formulário existe para resiliência operacional — urgências presenciais e
indisponibilidade da API e-SUS. O fluxo principal será o sync automático.
O campo "Classificação de Risco" neste formulário deve evoluir para
"Número de Autorização e-SUS" quando o sync estiver ativo.

---

## PROMPT-3 · Modal Agendar em Equipamento ✅ CONCLUÍDO

**Status:** implementado  
**Arquivos criados:** `src/components/AgendarModal.jsx`  
**Arquivos editados:** `src/pages/FilaPage.jsx`

**O que foi feito:**
- Select de equipamento com vagas disponíveis e % ocupação
- Date picker com mínimo = amanhã
- Turno filtrado pelo equipamento selecionado
- INSERT em `appointments` + UPDATE `queue_entries.status_local = 'agendado'`
- Rollback do INSERT se UPDATE falhar
- Botão "Agendar" → "Agendado" desabilitado após conclusão

---

## PROMPT-4A · Tabela kpi_configs no Supabase

**Status:** EXECUTAR PRIMEIRO — pré-requisito dos demais  
**Objetivo:** Criar a tabela de configuração de KPIs no banco

```
TAREFA: Rodar migration no Supabase SQL Editor

Cole e execute o bloco abaixo no SQL Editor do Supabase.
Este bloco está no final do arquivo supabase/schema.sql do repositório.
Ele cria a tabela kpi_configs com seed dos KPIs do edital CPSI.

Após executar, verificar com:
  SELECT chave, label, valor_meta, valor_critico FROM kpi_configs ORDER BY ordem_exibicao;

Deve retornar 6 linhas com as metas do edital.
```

---

## PROMPT-4B · Hook useKpiConfigs + useDashboardMetrics

**Status:** PRÓXIMO A EXECUTAR  
**Objetivo:** Hooks que leem metas do banco — nunca do código

```
TAREFA: Criar dois hooks para o sistema de KPIs configuráveis

Contexto arquitetural importante:
  As metas (15% absenteísmo, 120 dias espera, etc.) estão na tabela
  kpi_configs no Supabase — NÃO hardcoded no frontend.
  O gestor altera as metas via UI de configuração.
  O dashboard lê as metas do banco e compara com os dados reais.
  Padrão inspirado em ERPs (SAP) e plataformas como Monday.com.

## Hook 1: Criar src/hooks/useKpiConfigs.js

  Propósito: carregar configurações de metas do banco (muda raramente)
  
  Query: SELECT * FROM v_kpi_status ORDER BY ordem_exibicao
  
  Retorno: { configs, loading, error }
  onde configs é um objeto indexado por chave para acesso O(1):
  {
    absenteismo_taxa: { label, valor_meta, valor_critico, valor_atencao, direcao, unidade },
    espera_media_dias: { ... },
    capacidade_aproveitamento: { ... },
    demanda_reprimida_dias: { ... },
    vagas_risco_horas: { ... },
    satisfacao_meta: { ... }
  }
  
  Cache: os configs mudam raramente. Usar staleTime longo.
  Sem realtime — recarregar apenas na montagem.

## Hook 2: Criar src/hooks/useDashboardMetrics.js

  Propósito: calcular valores reais e comparar com metas do banco
  
  Queries paralelas (Promise.all para performance):
  
  Query A — absenteísmo real:
    SELECT
      COUNT(*) FILTER (WHERE st_falta_registrada = 1)::numeric as faltas,
      COUNT(*) FILTER (WHERE status in ('realizado','faltou')) as total_finalizados,
      ROUND(
        COUNT(*) FILTER (WHERE st_falta_registrada = 1)::numeric /
        NULLIF(COUNT(*) FILTER (WHERE status in ('realizado','faltou')), 0) * 100
      , 1) as taxa_absenteismo
    FROM appointments
    WHERE created_at >= now() - interval '30 days'
  
  Query B — tempo médio de espera (já existe em v_kpis):
    SELECT media_dias_espera, total_aguardando, total_agendado,
           total_confirmado, total_outros_municipios
    FROM v_kpis

  Query C — aproveitamento de capacidade:
    SELECT ROUND(AVG(pct_ocupacao), 1) as media_ocupacao,
           COUNT(*) FILTER (WHERE pct_ocupacao < 30) as equipamentos_ociosos,
           COUNT(*) as total_equipamentos
    FROM v_ocupacao_equipamentos
    WHERE status = 'ativo'

  Query D — demanda reprimida (usa config do banco):
    -- O limiar de dias vem de kpi_configs.chave='demanda_reprimida_dias'
    -- Passado como parâmetro, não hardcoded
    SELECT COUNT(*) as total_reprimida,
           MAX(extract(day from now() - data_solicitacao_sisreg)) as maior_espera
    FROM queue_entries
    WHERE status_local = 'aguardando'
      AND data_solicitacao_sisreg < now() - ($1 || ' days')::interval
    -- $1 = configs.demanda_reprimida_dias.valor_meta

  Query E — vagas em risco (usa config do banco):
    SELECT COUNT(*) as vagas_em_risco
    FROM appointments
    WHERE status = 'agendado'
      AND st_paciente_avisado = 0
      AND scheduled_at BETWEEN now() AND now() + ($1 || ' hours')::interval
    -- $1 = configs.vagas_risco_horas.valor_meta

  Função auxiliar (exportar junto):
    calcularStatus(valorReal, config):
      Recebe o valor real e o objeto config do kpi
      Retorna: 'ok' | 'atencao' | 'critico'
      Leva em conta config.direcao ('menor_melhor' | 'maior_melhor')
      Exemplo:
        direcao='menor_melhor', valorReal=18, valor_meta=15, valor_atencao=20
        → 'atencao' (acima da meta mas abaixo do crítico)

  Retorno do hook:
    { metrics, loading, error, refresh }
    metrics = {
      absenteismo: { valor: 18.3, status: 'atencao' },
      espera: { valor: 35, status: 'ok' },
      capacidade: { valor: 72, status: 'atencao' },
      demanda_reprimida: { valor: 4, status: 'ok' },
      vagas_em_risco: { valor: 2, status: 'critico' },
      equipamentos_ociosos: { valor: 1, status: 'atencao' },
      total_aguardando: 3,
      total_outros_municipios: 3
    }

Não modificar: useKpis.js (outros componentes dependem), useQueue.js, useEquipment.js
```

---

## PROMPT-4C · Dashboard com KPIs dinâmicos

**Status:** APÓS 4B  
**Objetivo:** Refatorar DashboardPage para consumir metas do banco

```
TAREFA: Refatorar src/pages/DashboardPage.jsx com KPIs configuráveis

Contexto:
  As metas vêm do banco via useKpiConfigs + useDashboardMetrics.
  O componente não conhece nenhum número hardcoded.
  Se o admin mudar a meta de 15% para 12%, o dashboard reflete
  automaticamente sem nenhuma alteração de código.

## Componente KpiCard (criar dentro do arquivo, não exportar)
Props:
  - config: objeto do kpi_configs { label, valor_meta, unidade, direcao }
  - valor: número real calculado
  - status: 'ok' | 'atencao' | 'critico'
  - icon: componente lucide

Comportamento visual por status:
  ok      → borda esquerda verde, ícone verde
  atencao → borda esquerda amarela, ícone âmbar
  critico → borda esquerda vermelha, ícone vermelho, leve pulse animation

Conteúdo do card:
  - Valor real grande (ex: "18.3%")
  - Label do KPI (ex: "Taxa de Absenteísmo")
  - Linha de meta: "Meta: ≤15%" ou "Meta: ≥85%" (direcao define o símbolo)
  - Barra de progresso colorida por status
  - Não mostrar número da meta hardcoded — ler de config.valor_meta

## Layout do Dashboard

Seção 1 — KPI Cards (grid 2x2 em mobile, 4 colunas em desktop)
  Card 1: absenteismo_taxa
  Card 2: espera_media_dias
  Card 3: capacidade_aproveitamento
  Card 4: demanda_reprimida_dias

Seção 2 — Alertas operacionais (só aparece se houver alertas)
Título: "Requer atenção agora"
  🔴 Vagas em risco: "X vagas sem confirmação nas próximas Yh"
     (Y vem de configs.vagas_risco_horas.valor_meta)
  🟡 Equipamentos ociosos: "X de Y equipamentos ativos abaixo de Z% ocupação"
  Se nenhum alerta: não renderizar a seção (não mostrar "tudo ok")

Seção 3 — Demanda por município
Título: "Polo macrorregional"
Tabela: municipio | aguardando | agendado | total
Máximo 8 linhas. Query via supabase diretamente no componente (exceção justificada):
  SELECT municipio_paciente,
    COUNT(*) FILTER (WHERE status_local='aguardando') as aguardando,
    COUNT(*) FILTER (WHERE status_local='agendado') as agendado,
    COUNT(*) as total
  FROM v_dashboard_fila
  GROUP BY municipio_paciente ORDER BY total DESC LIMIT 8
Destacar linha se municipio_paciente != 'Montes Claros' com texto azul

Importar e usar: useKpiConfigs, useDashboardMetrics
Não usar: useKpis (substituído pelo novo hook)
Não alterar: hooks existentes, outras páginas
```

---

## PROMPT-5 · Página de Configurações de KPI (Admin)

**Status:** PENDENTE  
**Objetivo:** Interface para o gestor configurar metas sem tocar em código

```
TAREFA: Criar página de configuração de KPIs para perfil admin

Contexto arquitetural:
  Inspirado em ERPs (SAP) e plataformas configuráveis (Monday.com).
  O gestor de saúde de Montes Claros define suas próprias metas.
  Quando o município alcança a meta de 15% de absenteísmo, pode
  aumentar a régua para 12%. Sem deploy. Sem developer.
  Toda alteração é auditada (atualizado_por, updated_at).

## Passo 1: Criar src/hooks/useKpiConfigsMutation.js

  Função: updateKpiConfig(chave, campos)
    UPDATE kpi_configs
    SET valor_meta = $1, valor_critico = $2, valor_atencao = $3,
        atualizado_por = auth.uid(), updated_at = now()
    WHERE chave = $4
  
  Retorno: { update, loading, error }

## Passo 2: Criar src/pages/ConfiguracoesPage.jsx

  Acesso: somente role='admin' (verificar via useAuth)
  Se não admin: mostrar mensagem "Acesso restrito" sem redirecionar

  Layout em duas colunas:
    Esquerda: lista de KPIs configuráveis (cards clicáveis)
    Direita: formulário de edição do KPI selecionado

  Card de KPI (esquerda):
    - Label do KPI
    - Meta atual (ex: "Meta: 15%")
    - Indicador visual de status atual vs meta
    - Clique seleciona para edição

  Formulário de edição (direita):
    Campos editáveis (inputs numéricos):
      - Meta (valor_meta): "Valor a atingir"
      - Atenção (valor_atencao): "Alertar quando passar deste valor"
      - Crítico (valor_critico): "Situação crítica — ação imediata"
    
    Campos informativos (somente leitura, não editáveis):
      - Chave técnica (chave)
      - Unidade de medida
      - Direção (menor_melhor / maior_melhor)
      - Descrição do KPI

    Validação antes de salvar:
      direcao='menor_melhor':
        valor_meta < valor_atencao < valor_critico
      direcao='maior_melhor':
        valor_meta > valor_atencao > valor_critico
      Se inválido: mostrar erro inline explicativo

    Ao salvar:
      - Chamar updateKpiConfig
      - Mostrar toast "Meta atualizada com sucesso"
      - Invalidar cache de useKpiConfigs (chamar refresh)

    Histórico simples abaixo do formulário:
      "Última atualização: [data] por [nome do operador]"
      (JOIN com profiles via atualizado_por)

## Passo 3: Editar App.jsx e Layout.jsx
  Nova rota: /configuracoes
  Nav item: ícone Settings (lucide-react), label "Configurações"
  Visível apenas para role='admin' (condicional no Layout)

Não instalar pacotes. Não alterar hooks existentes.
```

---

## PROMPT-6 · Notificações WhatsApp + Motor de Alertas

**Status:** PENDENTE  
**Objetivo:** Histórico de notificações e motor de redistribuição de vagas

```
TAREFA: Criar sistema de notificações com motor de redistribuição de vagas

Contexto:
  Esta é a proposta de valor central da solução.
  Nossa solução automatiza o campo st_paciente_avisado do e-SUS/SISREG.
  A janela de alerta (48h padrão) vem de kpi_configs.vagas_risco_horas —
  não hardcoded. O gestor pode mudar para 72h se quiser.

## Passo 1: Criar src/hooks/useNotifications.js
  Query:
    SELECT n.id, n.tipo, n.canal, n.enviado_at, n.respondido_at,
           n.resposta_paciente, n.entregue, n.erro,
           p.nome as paciente_nome, p.telefone,
           a.scheduled_at,
           eq.nome as equipamento_nome
    FROM notification_log n
    JOIN patients p ON p.id = n.patient_id
    LEFT JOIN appointments a ON a.id = n.appointment_id
    LEFT JOIN equipment eq ON eq.id = a.equipment_id
    ORDER BY n.enviado_at DESC
    LIMIT 50

  Realtime: subscrever notification_log para atualizações ao vivo
  Retorno: { notifications, stats, loading, error }
  
  stats calculado client-side:
    total_hoje: enviadas today
    taxa_confirmacao: confirmou / (confirmou + cancelou) * 100
    sem_resposta: enviado há >2h sem resposta_paciente

## Passo 2: Criar src/pages/NotificacoesPage.jsx

  Seção 1 — KPIs de comunicação (3 cards pequenos)
    - Total enviadas hoje
    - Taxa de confirmação (%)
    - Sem resposta / em risco

  Seção 2 — Alertas de vagas em risco
    Título: "Vagas sem confirmação"
    Buscar: appointments WHERE status='agendado'
      AND st_paciente_avisado=0
      AND scheduled_at BETWEEN now() AND now() + (config_horas || ' hours')
    config_horas: ler de useKpiConfigs().configs.vagas_risco_horas.valor_meta
    
    Para cada vaga em risco:
      Card com: paciente, equipamento, data do exame, horas restantes
      Botão "Notificar agora":
        INSERT notification_log (tipo='lembrete_manual', ...)
        UPDATE appointments SET st_paciente_avisado=1

  Seção 3 — Histórico de notificações
    Tabela: Paciente | Tipo | Equipamento | Enviado em | Resposta
    Badge por tipo: 72h=azul | 24h=amarelo | 2h=vermelho | manual=cinza
    Badge por resposta: confirmou=verde | cancelou=vermelho | sem_resposta=cinza

  Botão global "Notificar em massa":
    Modal com preview: "X pacientes serão notificados"
    Seletor de tipo (72h / 24h / 2h / lembrete_manual)
    Ao confirmar:
      INSERT em notification_log para todos agendados sem aviso
      UPDATE appointments SET st_paciente_avisado=1 em batch
      Toast com resultado: "Y notificações registradas"

## Passo 3: Adicionar rota e nav
  Rota: /notificacoes
  Ícone: Bell (lucide-react)
  Label: "Notificações"
  Badge vermelho no ícone se houver vagas_em_risco > 0

Não instalar pacotes. Não alterar hooks existentes.
```

---

## PROMPT-7 · Sync com e-SUS (esqueleto auditável)

**Status:** FUTURO — fase de aceleração  
**Objetivo:** Estrutura de integração com API e-SUS/SISREG

```
TAREFA: Criar módulo de sync com e-SUS Regulação

Contexto:
  O coração do sistema. Quando tivermos credencial da Prefeitura,
  este módulo popula o banco automaticamente.
  Hoje: esqueleto com mock para demonstração.
  Na aceleração: substituir mock pela API real.

API alvo (Elasticsearch — GET only):
  https://sisreg-es.saude.gov.br/marcacao-ambulatorial-mg-{municipio}
  Autenticação: Bearer token fornecido pela Prefeitura

## Criar src/services/esusSync.js

  Constantes no topo (únicas strings configuráveis do arquivo):
    ESUS_BASE_URL = 'https://sisreg-es.saude.gov.br'
    CODIGO_CENTRAL_MG = process.env.VITE_ESUS_CODIGO_CENTRAL (do .env.local)

  Função principal: syncFromESus()
    1. GET /marcacao-ambulatorial-mg-{municipio}
       com query Elasticsearch para agendados nos últimos 7 dias
    2. Para cada hit._source:
       a. Upsert em patients por cns_usuario
       b. Upsert em queue_entries por sisreg_codigo_solicitacao
       c. Upsert em appointments por codigo_marcacao_sisreg
    3. INSERT em sisreg_sync_log com resultado
    4. Retornar { novos, atualizados, erros, duracao_ms }

  Mapeamento de campos (API → banco):
    codigo_solicitacao           → queue_entries.sisreg_codigo_solicitacao
    cns_usuario                  → patients.cns
    no_usuario                   → patients.nome
    municipio_paciente_residencia → queue_entries.municipio_paciente
    codigo_classificacao_risco   → queue_entries.prioridade_codigo
    status_solicitacao           → queue_entries.status_sisreg
    chave_confirmacao            → appointments.sisreg_chave_confirmacao
    data_marcacao                → appointments.scheduled_at
    data_aprovacao               → appointments.authorized_at
    st_paciente_avisado          → appointments.st_paciente_avisado
    st_falta_registrada          → appointments.st_falta_registrada
    nome_unidade_executante      → appointments.nome_unidade_executante
    codigo_unidade_executante    → equipment (lookup por cnes)

## Criar src/pages/SyncPage.jsx (admin only)
  - Status do último sync (timestamp, registros, duração)
  - Botão "Sincronizar agora" → chama syncFromESus()
  - Progress indicator durante sync
  - Histórico dos últimos 20 syncs de sisreg_sync_log
    Colunas: data | registros novos | atualizados | erros | duração | status
  - Indicador de "próximo sync automático" (futuro: cron job)

Adicionar rota /sync e nav item com ícone RefreshCw
Visível apenas para role='admin'
```

---

## PROMPT-8 · Portal do Cidadão (consulta pública)

**Status:** FUTURO  
**Objetivo:** Transparência — item 5.1.3 do edital

```
TAREFA: Criar página pública de consulta de posição na fila

Contexto:
  Item 5.1.3 do edital CPSI: "Fornecer ao cidadão informações claras
  sobre sua posição na fila e previsão estimada de atendimento."
  Esta página é pública — não requer login.
  Design: mobile-first, fonte grande, linguagem acessível.

## Criar src/pages/CidadaoPage.jsx (rota pública /minha-vez)

  Header simples: logo + "Sistema de Regulação de Imagem — Montes Claros"
  Sem sidebar.

  Formulário de consulta:
    Campo único: CNS (15 dígitos, máscara automática)
    Botão "Consultar minha situação"

  Resultados (se encontrado):
    Card 1 — Status atual:
      "Seu pedido está: AGUARDANDO / AGENDADO / CONFIRMADO"
      Ícone colorido por status

    Card 2 — Posição na fila (se aguardando):
      "Você é o Nº X na fila"
      "Tempo estimado: Y dias" (media_dias_espera da v_kpis)

    Card 3 — Agendamento (se agendado/confirmado):
      "Seu exame está marcado para:"
      Data e hora em destaque
      Local: nome do equipamento / unidade
      "Confirme sua presença respondendo ao WhatsApp que enviamos"

    Card 4 — Orientações:
      "Em caso de dúvidas, procure sua UBS de origem"

  Se CNS não encontrado:
    "CNS não localizado na fila de Montes Claros"
    "Procure a UBS mais próxima para verificar seu encaminhamento"

## Criar policy RLS para consulta pública
  CREATE POLICY "Cidadao consulta por CNS"
  ON queue_entries FOR SELECT TO anon
  USING (true)
  -- Segurança: o CNS é dado que só o paciente conhece
  -- Query filtra por CNS exato — não expõe lista

Adicionar rota /minha-vez no App.jsx como rota pública (fora do guard de auth)
Link no Login: "Consulte sua posição na fila →"
```

---

## Histórico de Decisões Arquiteturais

| Data | Decisão | Motivo |
|------|---------|--------|
| 10/04 | Supabase como BaaS | Auditabilidade, PostgreSQL, RLS nativo |
| 10/04 | Schema alinhado com API SISREG | Integração real futura sem refatoração |
| 10/04 | Reposicionamento: camada de gestão sobre e-SUS | Edital pede complementaridade, não substituição |
| 10/04 | FastAPI postergado para fase de aceleração | Foco no MVP demonstrável para o edital |
| 10/04 | Formulário manual = exceção, não fluxo principal | Evitar duplicidade de trabalho do operador |
| 10/04 | kpi_configs: metas no banco, não no código | Escalabilidade, autonomia do gestor, sem deploys |

---

## PROMPT-7 · Dashboard Sala de Situação (BI + Gráficos)

**Status:** PRÓXIMO — requer `npm install recharts` aprovado pelo usuário  
**Objetivo:** Transformar o dashboard em sala de situação para o Secretário de Saúde

**Pré-requisito:** Instalar recharts
```bash
cd frontend && npm install recharts
```

**Decisão de design:** Usuário é gestor público (não técnico), mas com nível alto.
O dashboard deve ser autoexplicativo, com filtros simples e impacto visual imediato.
Inspiração: NOC (Network Operations Center) + Sala de Situação governamental.
NÃO replicar complexidade de Monday.com — filtros devem ser botões, não formulários.

```
TAREFA: Refatorar DashboardPage.jsx como Sala de Situação do Secretário de Saúde

Contexto estratégico:
  Este dashboard fica exposto em tela grande na sala da Secretaria de Saúde.
  O secretário precisa tomar decisão de onde focar esforços em 30 segundos.
  Cada gráfico responde uma pergunta específica de gestão.
  Filtros são simples: botões de período (7d / 30d / 90d) no topo.

## Instalar recharts (confirmar que npm install recharts foi executado)

## Criar src/hooks/useDashboardCharts.js

  Propósito: queries específicas para os gráficos
  
  Todas as queries aceitam parametro p_dias (7, 30 ou 90)
  default: 30 dias

  Query A — Exames por hospital/clínica (pizza):
    SELECT nome_unidade_executante as nome,
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE st_falta_registrada = 1) as faltas,
      COUNT(*) FILTER (WHERE status = 'realizado') as realizados
    FROM appointments
    WHERE created_at >= now() - (p_dias || ' days')::interval
      AND nome_unidade_executante IS NOT NULL
    GROUP BY nome_unidade_executante
    ORDER BY total DESC

  Query B — Demanda por município (barras horizontais):
    SELECT municipio_paciente as municipio,
      COUNT(*) as total,
      COUNT(*) FILTER (WHERE prioridade_codigo <= 2) as urgentes,
      COUNT(*) FILTER (WHERE status_local = 'aguardando') as aguardando
    FROM queue_entries
    WHERE created_at >= now() - (p_dias || ' days')::interval
    GROUP BY municipio_paciente
    ORDER BY total DESC
    LIMIT 10

  Query C — Ranking de UBS por volume (barras horizontais):
    SELECT u.nome as ubs,
      COUNT(q.id) as total,
      COUNT(q.id) FILTER (WHERE q.prioridade_codigo <= 2) as urgentes,
      COUNT(q.id) FILTER (WHERE q.status_local = 'aguardando') as aguardando
    FROM ubs u
    LEFT JOIN queue_entries q ON q.ubs_id = u.id
      AND q.created_at >= now() - (p_dias || ' days')::interval
    WHERE u.tipo IN ('S', 'A')
    GROUP BY u.nome
    ORDER BY total DESC

  Query D — Tendência de absenteísmo (linha do tempo, semanal):
    SELECT
      date_trunc('week', a.scheduled_at) as semana,
      COUNT(*) as total_agendados,
      COUNT(*) FILTER (WHERE a.st_falta_registrada = 1) as faltas,
      ROUND(COUNT(*) FILTER (WHERE a.st_falta_registrada = 1)::numeric /
        NULLIF(COUNT(*), 0) * 100, 1) as taxa
    FROM appointments a
    WHERE a.scheduled_at >= now() - (p_dias || ' days')::interval
    GROUP BY date_trunc('week', a.scheduled_at)
    ORDER BY semana ASC

  Retorno: { charts, loading, error, refresh, periodo, setPeriodo }

## Layout do Dashboard — estrutura em zonas

### ZONA 0 — Header do dashboard
  Título: "Sala de Situação — Regulação de Imagem"
  Subtítulo: data e hora atual atualizando a cada minuto
  Direita: seletor de período — botões simples:
    [7 dias] [30 dias] [90 dias]  ← estado ativo destacado
  Botão "Atualizar" (já existe, manter)

### ZONA 1 — KPIs (existente, melhorar cores)
  Manter os 4 cards existentes
  
  CORREÇÃO DE CORES — regra clara por status:
    status='ok'      → borda esquerda 4px verde (#16a34a), ícone verde
    status='atencao' → borda esquerda 4px âmbar (#d97706), ícone âmbar
    status='critico' → borda esquerda 4px vermelho (#dc2626), ícone vermelho + pulse
  
  Barra de progresso:
    Calcular preenchimento relativo entre 0 e valor_critico
    Cor da barra = cor do status
    Nunca mostrar barra vazia (mínimo 2% para ser visível)

### ZONA 2 — Gráficos (novo)
  Grid: 2 colunas em desktop, 1 coluna em mobile

  Card A — "Exames por local" (Donut/Pizza)
    Componente recharts: PieChart + Pie + Cell + Tooltip + Legend
    Dados: Query A do useDashboardCharts
    Cores: paleta acessível ['#1d4ed8','#059669','#d97706','#7c3aed','#db2777']
    Centro do donut: total de exames em número grande
    Legenda embaixo: nome + quantidade
    Pergunta respondida: "Onde estão sendo realizados os exames?"

  Card B — "Demanda por município" (Barras horizontais)
    Componente recharts: BarChart layout='vertical' + Bar + Tooltip
    Dados: Query B (top 10 municípios)
    Barras empilhadas: urgentes (vermelho) + rotina (azul)
    Eixo Y: nome do município (fonte pequena, truncar em 15 chars)
    Destacar Montes Claros com cor diferente
    Pergunta respondida: "De onde vêm os pacientes?"

  Card C — "UBS com mais encaminhamentos" (Barras horizontais)
    Componente recharts: BarChart layout='vertical'
    Dados: Query C
    Barra total (azul claro) com barra de urgentes sobreposta (vermelho)
    Máximo 8 UBS no gráfico
    Pergunta respondida: "Quais UBS geram mais demanda?"

  Card D — "Tendência de absenteísmo" (Linha)
    Componente recharts: LineChart + Line + Area + ReferenceLine
    Dados: Query D
    Linha de taxa (%) com área preenchida
    ReferenceLine horizontal na meta (vem de configs.absenteismo_taxa.valor_meta)
    Label na linha de referência: "Meta 15%"
    Eixo X: semanas em formato "DD/MM"
    Pergunta respondida: "O absenteísmo está melhorando?"

### ZONA 3 — Alertas operacionais (existente, refinar)
  Manter lógica atual
  Adicionar: botão "Ver notificações" que navega para /notificacoes

### ZONA 4 — Polo macrorregional (existente, refinar)
  Manter tabela atual
  Adicionar coluna "% do total" calculado client-side

## Regras de implementação

- Cada card de gráfico tem header: ícone + título + pergunta respondida (texto pequeno cinza)
- Loading state: Skeleton retangular na área do gráfico (não spinner)
- Empty state: mensagem específica "Nenhum dado no período selecionado"
- Todos os gráficos respondem ao filtro de período (7d/30d/90d)
- Tooltip em português com formatação brasileira de números
- NÃO adicionar filtros complexos nos gráficos — o período global é suficiente
- Responsivo: em mobile os gráficos ficam abaixo dos KPIs, 1 coluna

## Não alterar
  useKpis.js, useKpiConfigs.js, useDashboardMetrics.js,
  hooks de fila e equipamentos, outras páginas

## Fixes incluídos neste prompt
  1. Cores dos KPIs: regra clara ok/atencao/critico conforme acima
  2. Badge "ativo/inativo" nos equipamentos: já é dinâmico —
     verificar se a classe CSS está condicional e não estática
```

---

## PROMPT-7B · Fix do filtro na FilaPage

**Status:** EXECUTAR JUNTO COM PROMPT-7 ou antes**

```
TAREFA: Corrigir bug de duplicatas no filtro da FilaPage

Problema identificado:
  A view v_dashboard_fila já foi corrigida com DISTINCT ON no banco.
  Mas o hook useQueue pode estar fazendo múltiplas requisições
  ou o componente renderizando múltiplas linhas com o mesmo id.
  
Correção no hook src/hooks/useQueue.js:
  Após receber os dados do Supabase, garantir unicidade por id:
  
  const uniqueEntries = (data || []).filter(
    (entry, index, self) => index === self.findIndex(e => e.id === entry.id)
  )
  setEntries(uniqueEntries)

Correção no FilaPage.jsx — filtro de busca:
  O filtro atual usa .includes() que é case-sensitive e filtra
  mas mantém duplicatas se houver.
  Substituir por:

  const filtrados = entries.filter(e => {
    if (!busca) return true
    const termo = busca.toLowerCase().trim()
    return (
      e.paciente_nome?.toLowerCase().includes(termo) ||
      e.ubs_origem?.toLowerCase().includes(termo) ||
      e.paciente_cns?.includes(termo) ||
      e.municipio_paciente?.toLowerCase().includes(termo)
    )
  })

  Nenhuma outra alteração. Não tocar em outros arquivos.
```
