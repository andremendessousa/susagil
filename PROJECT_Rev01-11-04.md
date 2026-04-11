# SUS Raio-X — Documento Mestre do Projeto
> Última atualização: 11/04/2026 — snapshot para nova sessão de desenvolvimento

---

## 1. Contexto Estratégico

### O que é
Sistema de **gestão operacional e comunicação** sobre o e-SUS Regulação de Montes Claros (MG).  
**Não somos um sistema de fila paralelo.** Somos a camada de inteligência que o e-SUS não tem.

### Posicionamento exato
```
e-SUS Regulação (autoriza, agenda, regula — fluxo oficial intacto)
         ↓  sync automático via API Elasticsearch
    SUS RAIO-X
    → comunica com paciente (WhatsApp)
    → monitora ocupação de equipamentos em tempo real
    → redistribui vagas de quem faltou
    → analytics de absenteísmo para o gestor
         ↓
  Beneficiários:
  Secretário de Saúde → sala de situação com BI
  Operador/UBS        → alertas de vaga em risco
  Cidadão             → posição na fila via CNS
```

### Edital
- **CPSI Co.NE nº 004/2026** — Prefeitura de Montes Claros / ENAP / Sudene / BID
- Submissão: **28/04/2026**
- Aceleração MVP: 18/mai → 10/jul/2026
- Demoday: 03–07/ago/2026
- Valores: R$200k (CPSI) → R$1,6M (contrato subsequente)

### Indicadores obrigatórios do edital
| KPI | Baseline | Meta | Como medimos |
|-----|---------|------|-------------|
| Absenteísmo | ~35% | ≤15% | `st_falta_registrada` / total agendado |
| Tempo médio espera | >120 dias | ≤120 dias | `media_dias_espera` em v_kpis |
| Aproveitamento capacidade | ~65% | >85% | agendados hoje / capacidade_dia |
| Satisfação usuário | ? | >8/10 | pesquisa pós-atendimento |

### Concorrentes de alto risco
- **Beyond Co./Absens** — IA preditiva 96% acurácia, CPSI com Recife
- **DHF** — assistente WhatsApp "Celina", -18% absenteísmo

### Diferencial único
Foco em **exames de imagem** + gestão por **equipamento** + **polo macrorregional** (80 municípios).

---

## 2. Stack Tecnológico

```
Frontend:  React 18 + Vite + Tailwind CSS + Recharts + lucide-react
BaaS:      Supabase (PostgreSQL + Auth + Realtime + RLS)
           URL: https://duyabldyygckpxhnnemz.supabase.co
Futuro:    FastAPI (fase de aceleração) + Evolution API (WhatsApp)
Repo:      andremendessousa/susagil (público, GitHub)
```

---

## 3. Banco de Dados — Estado Atual

### Tabelas (todas com RLS habilitado)
| Tabela | Propósito | Status |
|--------|-----------|--------|
| `ubs` | Unidades de saúde (chave: cnes_code) | ✅ Populada |
| `equipment` | Aparelhos de raio-x com capacidade_dia | ✅ 4 equipamentos |
| `patients` | CNS como PK — integra CADWEB/e-SUS | ✅ ~24 pacientes |
| `profiles` | Operadores — espelha perfis e-SUS | ✅ Com RLS |
| `queue_entries` | Fila — espelho do e-SUS com campos API | ✅ ~24 entradas |
| `appointments` | Agendamentos (authorized_at ≠ scheduled_at) | ✅ ~30 registros |
| `notification_log` | Histórico WhatsApp com resposta paciente | ✅ Estrutura pronta |
| `kpi_configs` | Metas configuráveis pelo gestor — nunca hardcoded | ✅ 6 KPIs seedados |
| `sisreg_sync_log` | Controle de syncs com API e-SUS | ✅ Estrutura pronta |

### Views
| View | Propósito | Observação |
|------|-----------|------------|
| `v_dashboard_fila` | Fila com joins — DISTINCT ON para evitar duplicatas | ✅ Corrigida |
| `v_kpis` | KPIs agregados em tempo real | ✅ Ativa |
| `v_ocupacao_equipamentos` | Ocupação por equipamento no dia atual | ✅ Ativa |
| `v_kpi_status` | Configs de KPI ordenadas para o dashboard | ✅ Ativa |

### RPCs (funções PostgreSQL)
| Função | Parâmetro | Propósito |
|--------|-----------|-----------|
| `calcular_absenteismo_30d()` | nenhum | Taxa de faltas últimos 30 dias |
| `calcular_demanda_reprimida(p_limiar_dias)` | int do kpi_configs | Pacientes acima do limiar |
| `calcular_vagas_em_risco(p_horas)` | int do kpi_configs | Agendados sem confirmação |

### kpi_configs — valores atuais
| chave | valor_meta | valor_atencao | valor_critico | direcao |
|-------|-----------|---------------|---------------|---------|
| absenteismo_taxa | 15% | 20% | 35% | menor_melhor |
| espera_media_dias | 120 dias | 140 | 180 | menor_melhor |
| capacidade_aproveitamento | 85% | 70% | 50% | maior_melhor |
| demanda_reprimida_dias | 30 dias | 45 | 60 | menor_melhor |
| vagas_risco_horas | 48h | 24 | 72 | menor_melhor |
| satisfacao_meta | 8.0 | 7.0 | 6.0 | maior_melhor |

---

## 4. Frontend — Estado Atual

### Arquivos existentes
```
frontend/src/
  components/
    Layout.jsx              ✅ Sidebar azul, nav, header com sino
    NovoEncaminhamentoModal.jsx  ✅ CNS lookup + INSERT queue_entries
    AgendarModal.jsx        ✅ Equipamento + data + INSERT appointments
  hooks/
    useAuth.js              ✅ Supabase Auth + perfil
    useKpis.js              ✅ v_kpis (legado — manter para compatibilidade)
    useQueue.js             ✅ v_dashboard_fila com Realtime
    useEquipment.js         ✅ v_ocupacao_equipamentos com Realtime
    useKpiConfigs.js        ✅ kpi_configs indexado por chave O(1)
    useDashboardMetrics.js  ✅ 5 queries paralelas + calcularStatus()
    useDashboardCharts.js   ⚠️ CRIADO MAS GRÁFICOS VAZIOS (ver bug #1)
    useNotifications.js     ✅ notification_log com Realtime
    useKpiConfigsMutation.js ✅ UPDATE kpi_configs com auditoria
  pages/
    LoginPage.jsx           ✅ Auth funcional
    DashboardPage.jsx       ⚠️ KPI cards ok, gráficos recharts VAZIOS (ver bug #1)
    FilaPage.jsx            ⚠️ Filtro com bug de duplicatas (ver bug #2)
    MaquinasPage.jsx        ✅ Cards com ocupação e badges dinâmicos
    NotificacoesPage.jsx    ✅ Estrutura visual pronta, dados simulados
    ConfiguracoesPage.jsx   ✅ CRUD de metas — admin only
  lib/
    supabase.js             ✅ Cliente configurado
  App.jsx                   ✅ Rotas + guard de auth
  index.css                 ✅ .card .btn-primary .btn-ghost .badge
```

### Rotas existentes
```
/               → DashboardPage (autenticado)
/fila           → FilaPage
/maquinas       → MaquinasPage
/notificacoes   → NotificacoesPage
/configuracoes  → ConfiguracoesPage (admin only)
```

---

## 5. Bugs Conhecidos — Prioridade de Resolução

### Bug #1 — CRÍTICO: Gráficos recharts vazios no Dashboard
**Sintoma:** Espaço em branco onde deveriam estar PieChart, BarChart, LineChart  
**Causa provável:** `useDashboardCharts.js` faz queries filtrando por `created_at >= now() - interval '30 days'` mas os `appointments` têm `scheduled_at` no futuro ou passado distante, fora da janela. Ou o hook retorna dados mas o componente não mapeia corretamente os campos (nome das chaves do objeto).  
**Como resolver:**
1. No Supabase SQL Editor, rodar: `SELECT * FROM appointments LIMIT 5;` — ver o formato real dos campos
2. Comparar com o que o `useDashboardCharts` espera
3. Ajustar o mapeamento no hook ou no componente

### Bug #2 — MÉDIO: Filtro da FilaPage com duplicatas
**Sintoma:** Buscar "Carlos" mostra Carlos + outras linhas duplicadas  
**Causa:** JOIN na view retornava múltiplos appointments por queue_entry  
**Status:** View corrigida com DISTINCT ON no banco. Frontend precisa de dedup adicional no hook:
```js
// Em useQueue.js, após receber dados:
const unique = (data || []).filter(
  (e, i, self) => i === self.findIndex(x => x.id === e.id)
)
setEntries(unique)
```

### Bug #3 — MÉDIO: Aproveitamento de capacidade em 1.3%
**Causa:** `v_ocupacao_equipamentos` conta appointments onde `date(scheduled_at) = current_date`. Os appointments seedados têm `scheduled_at = now() + interval 'X days'` — nenhum cai em hoje.  
**Fix SQL (rodar no Supabase):**
```sql
-- Atualizar alguns appointments para hoje
UPDATE appointments 
SET scheduled_at = current_date + '09:00:00'::interval
WHERE id IN (
  SELECT id FROM appointments 
  WHERE status = 'agendado'
  ORDER BY created_at DESC
  LIMIT 15
);
-- Verificar
SELECT * FROM v_ocupacao_equipamentos;
```

---

## 6. Integração e-SUS / SISREG

### API real (Elasticsearch — GET only)
```
https://sisreg-es.saude.gov.br/marcacao-ambulatorial-mg-{municipio}
https://sisreg-es.saude.gov.br/solicitacao-ambulatorial-mg-{municipio}
```

### Campos críticos que nossa solução gerencia
- `st_paciente_avisado` (0/1) — **automatizamos este campo**
- `st_falta_registrada` (0/1) — detectamos e redistribuímos vaga
- `chave_confirmacao` (5 dígitos) — ID único do agendamento
- `status_solicitacao` — 19 estados da máquina de estados

### Mapeamento API → banco
```
codigo_solicitacao           → queue_entries.sisreg_codigo_solicitacao
cns_usuario                  → patients.cns
municipio_paciente_residencia → queue_entries.municipio_paciente
codigo_classificacao_risco   → queue_entries.prioridade_codigo
status_solicitacao           → queue_entries.status_sisreg
chave_confirmacao            → appointments.sisreg_chave_confirmacao
data_marcacao                → appointments.scheduled_at
data_aprovacao               → appointments.authorized_at
st_paciente_avisado          → appointments.st_paciente_avisado
st_falta_registrada          → appointments.st_falta_registrada
```

---

## 7. Módulo de Notificações — Estado Real

### O que está pronto
- Tabela `notification_log` com todos os campos (tipo, resposta, entregue, erro)
- `useNotifications.js` com Realtime
- `NotificacoesPage.jsx` com histórico e disparo manual
- Lógica de vagas em risco (usa `kpi_configs.vagas_risco_horas`)
- Campo `st_paciente_avisado` gerenciado pelo sistema

### O que falta para WhatsApp real
```
[ ] Evolution API rodando (Docker ou cloud)
[ ] Edge Function ou FastAPI endpoint de envio
[ ] Template de mensagem configurável no banco
[ ] Webhook para receber resposta do paciente (1=confirma, 2=cancela)
[ ] Lógica de reagendamento automático quando paciente cancela
```

### Estratégia para o vídeo do edital
Demonstrar fluxo simulado no banco — suficiente para a banca técnica.  
WhatsApp real entra na fase de aceleração (maio/julho 2026).

---

## 8. Convenções Obrigatórias de Desenvolvimento

```
- Tailwind apenas — zero CSS inline
- Classes globais: .card .btn-primary .btn-ghost .badge (em index.css)
- Ícones: apenas lucide-react
- Dados: sempre via hooks em src/hooks/
- Labels: português | Variáveis/funções: inglês
- NUNCA reescrever arquivo inteiro para edições parciais
- NUNCA instalar pacotes sem decisão explícita
- Pacotes instalados: recharts (já ok)
- Metas: NUNCA hardcoded — sempre de kpi_configs via useKpiConfigs
```

---

## 9. Sistema de Cores — Regra Única para Toda a UI

```
Status OK       → verde  (#16a34a) — dentro da meta
Status Atenção  → âmbar  (#d97706) — entre meta e crítico
Status Crítico  → vermelho (#dc2626) — além do crítico + pulse animation

Aplicar em:
  KPI cards         → borda esquerda 4px + ícone
  Barra de progresso → cor da barra
  Badges de fila    → cor_risco do paciente
  Badges equipamento → status ativo/inativo/manutencao
  Sino do header    → badge vermelho se vagas_em_risco > 0
```

---

## 10. Próximos Passos — Ordem de Prioridade

```
URGENTE (antes do vídeo):
  1. Fix Bug #3 — rodar SQL de update do scheduled_at
  2. Fix Bug #1 — debugar useDashboardCharts (console.log dos dados)
  3. Fix Bug #2 — dedup no useQueue.js
  4. Validar cores dinâmicas com queries de teste no Supabase

IMPORTANTE (para submissão):
  5. Portal do cidadão /minha-vez (Prompt 8)
  6. Fluxo WhatsApp simulado visualmente perfeito para o vídeo
  7. Sync e-SUS esqueleto (Prompt 7 de sync)

PÓS-EDITAL (fase de aceleração):
  8. FastAPI backend (segurança produção)
  9. Evolution API WhatsApp real
  10. Ambiente de produção separado
  11. LGPD compliance para dados de saúde
```

---

## 11. Queries de Teste — Validação em Tempo Real

Rodar no Supabase e observar o dashboard mudar:

```sql
-- TESTE A: Forçar absenteísmo para ver card mudar de cor
UPDATE appointments SET st_falta_registrada = 1, status = 'faltou'
WHERE id IN (SELECT id FROM appointments WHERE status = 'agendado' LIMIT 4);

-- TESTE B: Criar vaga em risco (exame em 20h sem aviso)
INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, 
  authorized_at, tipo_vaga, status, st_paciente_avisado, nome_unidade_executante)
SELECT
  (SELECT id FROM queue_entries WHERE status_local='aguardando' LIMIT 1),
  (SELECT id FROM equipment WHERE nome LIKE '%Aroldo%'),
  now() + interval '20 hours', now() - interval '2 days',
  'primeira_vez'::tipo_vaga, 'agendado'::status_local, 0,
  'Hospital Aroldo Tourinho';

-- TESTE C: Simular notificação enviada e confirmada pelo paciente
INSERT INTO notification_log (appointment_id, patient_id, tipo, canal,
  mensagem, telefone_destino, resposta_paciente, enviado_at, respondido_at, entregue)
SELECT a.id, q.patient_id, '24h'::notif_tipo, 'whatsapp',
  'Seu exame está marcado para amanhã. Confirme com 1.',
  p.telefone, 'confirmou'::notif_resposta,
  now() - interval '2 hours', now() - interval '1 hour', true
FROM appointments a
JOIN queue_entries q ON q.id = a.queue_entry_id
JOIN patients p ON p.id = q.patient_id
WHERE a.nome_unidade_executante IS NOT NULL LIMIT 1;

-- TESTE D: Fix aproveitamento capacidade (scheduled_at para hoje)
UPDATE appointments SET scheduled_at = current_date + '09:00:00'::interval
WHERE id IN (SELECT id FROM appointments WHERE status='agendado' LIMIT 15);
```

---

## 12. Arquivos de Migration (em supabase/)

```
schema.sql                    → Schema completo (rodar do zero)
migration_kpi_configs.sql     → Tabela kpi_configs + seed
migration_rpcs.sql            → 3 funções RPC
migration_fix_e_seed_rico.sql → Fix views + seed diverso
```

---

## 13. Decisões Arquiteturais Registradas

| Data | Decisão | Motivo |
|------|---------|--------|
| 10/04 | Supabase como BaaS | Auditabilidade PostgreSQL, RLS nativo |
| 10/04 | Schema alinhado API SISREG/e-SUS | Integração futura sem refatoração |
| 10/04 | Posicionamento: camada sobre e-SUS, não paralelo | Edital pede complementaridade |
| 10/04 | FastAPI postergado | MVP focado no edital |
| 10/04 | Formulário manual = exceção | Evitar duplicidade do operador |
| 10/04 | kpi_configs no banco | Metas configuráveis sem deploy |
| 11/04 | Recharts para gráficos | Maturidade, zero deps extras |
| 11/04 | WhatsApp simulado no MVP | Risco de prazo vs impacto visual |
