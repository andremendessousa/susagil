-- ============================================================
-- QUERY-1 v2 — SUS RAIO-X
-- Migration: fundação multifonte + KPIs do edital
-- Data: 2026-04-12
-- Versão: 2 (corrige incompatibilidades com estrutura real do banco)
-- Aplicar em: Supabase SQL Editor (projeto susagil)
-- Salvar depois em: supabase/migrations/202604120001_multifonte_kpis.sql
-- ============================================================
-- MUDANÇAS DA v1 → v2:
--   - Insert em kpi_configs preenche todos os NOT NULL reais (categoria,
--     unidade, descricao, ordem_exibicao, visivel_dashboard, visivel_relatorio)
--   - Não usa ON CONFLICT (chave) por não ter certeza da unique constraint;
--     usa WHERE NOT EXISTS, idempotente independente de constraints
--   - RPCs novas retornam JSON no padrão {numerador, denominador, taxa}
--     compatível com calcular_absenteismo_30d() existente
--   - Mantém RPCs antigas vivas (sem substituir) — deprecação no Prompt 3
--   - Mantém v_ocupacao_equipamentos viva — funções novas em paralelo
--   - Trigger nomeado com prefixo único (trg_susagil_*) para evitar conflito
--   - Categorias dos novos KPIs alinhadas às existentes (absenteismo,
--     capacidade, configuracao) baseadas em inspeção do banco real
-- ============================================================

-- ── 1. ENUM DATA_SOURCE ─────────────────────────────────────
do $$ begin
  create type data_source as enum (
    'sisreg_api',
    'esus_regulacao_api',
    'csv_import',
    'txt_import',
    'manual',
    'seed_demo'
  );
exception when duplicate_object then null; end $$;

comment on type data_source is
  'Origem do registro. Crítico para auditoria, rollback de importações e relatórios de qualidade de dados.';

-- ── 2. TABELA IMPORT_BATCHES ────────────────────────────────
create table if not exists import_batches (
  id                    uuid primary key default uuid_generate_v4(),
  source                data_source not null,
  arquivo_nome          text,
  arquivo_hash          text,
  registros_total       int default 0,
  registros_ok          int default 0,
  registros_erro        int default 0,
  registros_duplicados  int default 0,
  iniciado_at           timestamptz not null default now(),
  concluido_at          timestamptz,
  usuario_id            uuid references auth.users(id) on delete set null,
  status                sync_status not null default 'ok',
  detalhes              jsonb,
  created_at            timestamptz not null default now()
);

comment on table import_batches is
  'Lotes de importação. Permite rollback completo e auditoria de origem dos dados.';

create index if not exists idx_import_batches_source on import_batches(source);
create index if not exists idx_import_batches_iniciado on import_batches(iniciado_at desc);

alter table import_batches enable row level security;

drop policy if exists "Autenticados leem lotes de importação" on import_batches;
create policy "Autenticados leem lotes de importação"
  on import_batches for select to authenticated using (true);

-- ── 3. COLUNAS DATA_SOURCE + IMPORT_BATCH_ID ────────────────
alter table queue_entries
  add column if not exists data_source data_source not null default 'manual',
  add column if not exists import_batch_id uuid references import_batches(id) on delete set null;

alter table appointments
  add column if not exists data_source data_source not null default 'manual',
  add column if not exists import_batch_id uuid references import_batches(id) on delete set null;

alter table patients
  add column if not exists data_source data_source not null default 'manual',
  add column if not exists import_batch_id uuid references import_batches(id) on delete set null;

alter table notification_log
  add column if not exists data_source data_source not null default 'manual',
  add column if not exists import_batch_id uuid references import_batches(id) on delete set null;

create index if not exists idx_queue_entries_batch on queue_entries(import_batch_id);
create index if not exists idx_appointments_batch on appointments(import_batch_id);
create index if not exists idx_patients_batch on patients(import_batch_id);

-- ── 4. RASTREABILIDADE DE REAPROVEITAMENTO DE VAGAS ─────────
alter table appointments
  add column if not exists reaproveitado_de_id uuid references appointments(id) on delete set null;

comment on column appointments.reaproveitado_de_id is
  'Quando este agendamento ocupou um slot liberado por outro cancelamento, referencia o appointment original. Base do KPI de reaproveitamento de vagas.';

create index if not exists idx_appt_reaproveitado on appointments(reaproveitado_de_id)
  where reaproveitado_de_id is not null;

-- ── 5. TABELA SATISFACTION_SURVEYS (KPI #6) ─────────────────
create table if not exists satisfaction_surveys (
  id              uuid primary key default uuid_generate_v4(),
  appointment_id  uuid not null references appointments(id) on delete cascade,
  patient_id      uuid not null references patients(id) on delete restrict,
  nota_geral      smallint not null check (nota_geral between 1 and 10),
  comentario      text,
  canal           text not null default 'whatsapp',
  respondido_at   timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  unique (appointment_id)
);

comment on table satisfaction_surveys is
  'Pesquisas de satisfação pós-atendimento. KPI #6 do edital. MVP com nota única; expansível na fase de aceleração.';

create index if not exists idx_satisfaction_appointment on satisfaction_surveys(appointment_id);
create index if not exists idx_satisfaction_respondido on satisfaction_surveys(respondido_at desc);

alter table satisfaction_surveys enable row level security;
drop policy if exists "Autenticados leem pesquisas de satisfação" on satisfaction_surveys;
create policy "Autenticados leem pesquisas de satisfação"
  on satisfaction_surveys for select to authenticated using (true);

-- ── 6. FUNÇÃO DERIVE_COR_RISCO + TRIGGER ────────────────────
-- Garante coerência entre prioridade_codigo (1-4) e cor_risco (enum).
-- Trigger nomeado com prefixo trg_susagil_ para evitar colisão.

create or replace function derive_cor_risco(p_codigo smallint)
returns prioridade_cor language sql immutable as $$
  select case p_codigo
    when 1 then 'vermelho'::prioridade_cor
    when 2 then 'amarelo'::prioridade_cor
    when 3 then 'verde'::prioridade_cor
    when 4 then 'azul'::prioridade_cor
    else 'azul'::prioridade_cor
  end;
$$;

create or replace function fn_susagil_sync_cor_risco()
returns trigger language plpgsql as $$
begin
  new.cor_risco := derive_cor_risco(new.prioridade_codigo);
  return new;
end $$;

drop trigger if exists trg_susagil_sync_cor_risco on queue_entries;
create trigger trg_susagil_sync_cor_risco
  before insert or update of prioridade_codigo on queue_entries
  for each row execute function fn_susagil_sync_cor_risco();

-- ── 7. MAPEAMENTO STATUS_SISREG → STATUS_LOCAL ──────────────
create or replace function map_sisreg_status_to_local(p_status_sisreg text)
returns status_local language plpgsql immutable as $$
declare
  v_norm text;
begin
  v_norm := upper(trim(coalesce(p_status_sisreg, '')));

  return case
    when v_norm in ('SOLICITACAO/PENDENTE', 'SOLICITAÇÃO/PENDENTE',
                    'SOLICITACAO/PENDENTE/REGULADOR', 'SOLICITAÇÃO/PENDENTE/REGULADOR',
                    'PENDENTE', 'AGUARDANDO REGULACAO', 'AGUARDANDO REGULAÇÃO',
                    'EM FILA', 'FILA DE ESPERA')
      then 'aguardando'::status_local

    when v_norm in ('AUTORIZADA', 'AUTORIZADO', 'AGENDADA', 'AGENDADO',
                    'MARCADA', 'MARCADO', 'EM AGENDAMENTO')
      then 'agendado'::status_local

    when v_norm in ('CONFIRMADA', 'CONFIRMADO', 'CIENTE',
                    'PACIENTE AVISADO', 'CONFIRMADA PELO PACIENTE')
      then 'confirmado'::status_local

    when v_norm in ('EXECUTADA', 'EXECUTADO', 'REALIZADA', 'REALIZADO',
                    'CONCLUIDA', 'CONCLUÍDA', 'ATENDIDO')
      then 'realizado'::status_local

    when v_norm in ('FALTA', 'FALTOU', 'AUSENTE', 'NAO COMPARECEU',
                    'NÃO COMPARECEU', 'AUSENCIA', 'AUSÊNCIA')
      then 'faltou'::status_local

    when v_norm in ('CANCELADA', 'CANCELADO', 'NEGADA', 'NEGADO',
                    'DEVOLVIDA', 'DEVOLVIDO', 'EXCLUIDA', 'EXCLUÍDA')
      then 'cancelado'::status_local

    else 'aguardando'::status_local
  end;
end $$;

comment on function map_sisreg_status_to_local is
  'Mapeia os ~19 estados textuais da API SISREG para nosso enum de 6 estados. Estados desconhecidos caem em aguardando como fallback seguro.';

-- ── 8. RPC: CALCULAR_ABSENTEISMO (KPI #1, parametrizada) ────
-- Retorna JSON no mesmo padrão de calcular_absenteismo_30d() existente.

create or replace function calcular_absenteismo(p_horizonte_dias int default 30)
returns json language sql stable as $$
  select json_build_object(
    'horizonte_dias', p_horizonte_dias,
    'faltas', count(*) filter (where st_falta_registrada = 1),
    'total_finalizados', count(*),
    'taxa_absenteismo', case
      when count(*) = 0 then 0
      else round(
        (count(*) filter (where st_falta_registrada = 1)::numeric
         / count(*)::numeric) * 100,
        1
      )
    end
  )
  from appointments
  where status in ('realizado', 'faltou')
    and scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
    and scheduled_at <= now();
$$;

comment on function calcular_absenteismo is
  'KPI #1 do edital. Versão parametrizada por horizonte. Substituirá calcular_absenteismo_30d() na fase de refatoração de hooks (Prompt 3).';

-- ── 9. RPC: CALCULAR_TAXA_CONFIRMACAO_ATIVA (KPI #5) ────────
create or replace function calcular_taxa_confirmacao_ativa(p_horizonte_dias int default 30)
returns json language sql stable as $$
  select json_build_object(
    'horizonte_dias', p_horizonte_dias,
    'confirmacoes', count(*) filter (where resposta_paciente = 'confirmou'),
    'total_enviadas', count(*),
    'taxa_confirmacao', case
      when count(*) = 0 then 0
      else round(
        (count(*) filter (where resposta_paciente = 'confirmou')::numeric
         / count(*)::numeric) * 100,
        1
      )
    end
  )
  from notification_log
  where tipo in ('72h', '24h', '2h', 'confirmacao_agendamento')
    and enviado_at >= now() - (p_horizonte_dias || ' days')::interval
    and entregue = true;
$$;

comment on function calcular_taxa_confirmacao_ativa is
  'KPI #5 do edital. Proporção de pacientes que confirmaram após receber notificação ativa.';

-- ── 10. RPC: CALCULAR_TAXA_REAPROVEITAMENTO (KPI #4) ────────
create or replace function calcular_taxa_reaproveitamento(
  p_horizonte_dias int default 30,
  p_janela_horas int default 48
)
returns json language sql stable as $$
  with vagas_canceladas as (
    select id, scheduled_at, updated_at
    from appointments
    where status = 'cancelado'
      and updated_at >= now() - (p_horizonte_dias || ' days')::interval
  ),
  vagas_reaproveitadas as (
    select vc.id
    from vagas_canceladas vc
    join appointments novo on novo.reaproveitado_de_id = vc.id
    where novo.created_at <= vc.scheduled_at
      and extract(epoch from (novo.created_at - vc.updated_at)) / 3600 <= p_janela_horas
  )
  select json_build_object(
    'horizonte_dias', p_horizonte_dias,
    'janela_horas', p_janela_horas,
    'vagas_reaproveitadas', (select count(*) from vagas_reaproveitadas),
    'vagas_canceladas_total', (select count(*) from vagas_canceladas),
    'taxa_reaproveitamento', case
      when (select count(*) from vagas_canceladas) = 0 then 0
      else round(
        ((select count(*) from vagas_reaproveitadas)::numeric
         / (select count(*) from vagas_canceladas)::numeric) * 100,
        1
      )
    end
  );
$$;

comment on function calcular_taxa_reaproveitamento is
  'KPI #4 do edital. Vagas canceladas reocupadas dentro da janela hábil (default 48h).';

-- ── 11. RPC: CALCULAR_INDICE_SATISFACAO (KPI #6) ────────────
create or replace function calcular_indice_satisfacao(p_horizonte_dias int default 30)
returns json language sql stable as $$
  select json_build_object(
    'horizonte_dias', p_horizonte_dias,
    'total_respostas', count(*),
    'nota_media', case
      when count(*) = 0 then 0
      else round(avg(nota_geral)::numeric, 1)
    end,
    'pct_satisfeitos', case
      when count(*) = 0 then 0
      else round(
        (count(*) filter (where nota_geral >= 8)::numeric
         / count(*)::numeric) * 100,
        1
      )
    end
  )
  from satisfaction_surveys
  where respondido_at >= now() - (p_horizonte_dias || ' days')::interval;
$$;

comment on function calcular_indice_satisfacao is
  'KPI #6 do edital. Nota média e percentual de satisfeitos (nota >= 8) na janela.';

-- ── 12. FUNÇÕES DE OCUPAÇÃO POR HORIZONTE (KPI #3) ──────────
-- Não dropa v_ocupacao_equipamentos — mantém viva para compatibilidade.
-- Frontend migra para estas funções no Prompt 3.

create or replace function fn_ocupacao_passada(p_dias_atras int default 30)
returns table (
  equipment_id uuid,
  equipamento_nome text,
  unidade_nome text,
  capacidade_total int,
  exames_realizados bigint,
  pct_ocupacao numeric
) language sql stable as $$
  select
    eq.id,
    eq.nome,
    u.nome,
    eq.capacidade_dia * p_dias_atras as capacidade_total,
    count(a.id) filter (where a.status = 'realizado') as exames_realizados,
    case when eq.capacidade_dia * p_dias_atras = 0 then 0
         else round(
           (count(a.id) filter (where a.status = 'realizado')::numeric
            / (eq.capacidade_dia * p_dias_atras)::numeric) * 100,
           1)
    end as pct_ocupacao
  from equipment eq
  join ubs u on u.id = eq.ubs_id
  left join appointments a on a.equipment_id = eq.id
    and a.scheduled_at >= now() - (p_dias_atras || ' days')::interval
    and a.scheduled_at <= now()
  where eq.status = 'ativo'
  group by eq.id, eq.nome, u.nome, eq.capacidade_dia
  order by pct_ocupacao desc;
$$;

create or replace function fn_ocupacao_futura(p_dias_a_frente int default 30)
returns table (
  equipment_id uuid,
  equipamento_nome text,
  unidade_nome text,
  capacidade_total int,
  vagas_comprometidas bigint,
  vagas_disponiveis bigint,
  pct_ocupacao numeric
) language sql stable as $$
  select
    eq.id,
    eq.nome,
    u.nome,
    eq.capacidade_dia * p_dias_a_frente as capacidade_total,
    count(a.id) filter (where a.status in ('agendado', 'confirmado')) as vagas_comprometidas,
    (eq.capacidade_dia * p_dias_a_frente)
      - count(a.id) filter (where a.status in ('agendado', 'confirmado')) as vagas_disponiveis,
    case when eq.capacidade_dia * p_dias_a_frente = 0 then 0
         else round(
           (count(a.id) filter (where a.status in ('agendado', 'confirmado'))::numeric
            / (eq.capacidade_dia * p_dias_a_frente)::numeric) * 100,
           1)
    end as pct_ocupacao
  from equipment eq
  join ubs u on u.id = eq.ubs_id
  left join appointments a on a.equipment_id = eq.id
    and a.scheduled_at >= now()
    and a.scheduled_at <= now() + (p_dias_a_frente || ' days')::interval
  where eq.status = 'ativo'
  group by eq.id, eq.nome, u.nome, eq.capacidade_dia
  order by pct_ocupacao desc;
$$;

comment on function fn_ocupacao_passada is
  'Capacidade entregue: % da capacidade dos últimos N dias que virou exame realizado.';
comment on function fn_ocupacao_futura is
  'Capacidade comprometida: % da capacidade dos próximos N dias já reservada.';

-- ── 13. NOVAS CHAVES EM KPI_CONFIGS ─────────────────────────
-- Idempotente via WHERE NOT EXISTS (não depende de unique constraint em chave).
-- Categorias alinhadas às existentes: absenteismo, capacidade, configuracao.

insert into kpi_configs (
  chave, categoria, label, descricao, unidade,
  valor_meta, valor_atencao, valor_critico, direcao,
  visivel_dashboard, visivel_relatorio, ordem_exibicao
)
select 'reaproveitamento_taxa', 'capacidade', 
       'Taxa de Reaproveitamento de Vagas',
       'Percentual de vagas canceladas reocupadas em tempo hábil',
       '%', 70, 50, 30, 'maior_melhor', true, true, 10
where not exists (select 1 from kpi_configs where chave = 'reaproveitamento_taxa');

insert into kpi_configs (
  chave, categoria, label, descricao, unidade,
  valor_meta, valor_atencao, valor_critico, direcao,
  visivel_dashboard, visivel_relatorio, ordem_exibicao
)
select 'confirmacao_ativa_taxa', 'absenteismo',
       'Taxa de Confirmação Ativa',
       'Pacientes que respondem confirmando após notificação WhatsApp',
       '%', 75, 60, 40, 'maior_melhor', true, true, 11
where not exists (select 1 from kpi_configs where chave = 'confirmacao_ativa_taxa');

insert into kpi_configs (
  chave, categoria, label, descricao, unidade,
  valor_meta, valor_atencao, valor_critico, direcao,
  visivel_dashboard, visivel_relatorio, ordem_exibicao
)
select 'reaproveitamento_janela_horas', 'capacidade',
       'Janela Hábil de Reaproveitamento',
       'Tempo máximo para considerar uma vaga como reaproveitada',
       'h', 48, 72, 96, 'menor_melhor', false, true, 20
where not exists (select 1 from kpi_configs where chave = 'reaproveitamento_janela_horas');

insert into kpi_configs (
  chave, categoria, label, descricao, unidade,
  valor_meta, valor_atencao, valor_critico, direcao,
  visivel_dashboard, visivel_relatorio, ordem_exibicao
)
select 'horizonte_padrao_dias', 'configuracao',
       'Horizonte Padrão do Dashboard',
       'Janela temporal default exibida nos KPIs e gráficos',
       'd', 30, 60, 90, 'menor_melhor', false, false, 99
where not exists (select 1 from kpi_configs where chave = 'horizonte_padrao_dias');

-- ── 14. VALIDAÇÃO FINAL ─────────────────────────────────────
do $$
declare
  v_count int;
begin
  select count(*) into v_count from information_schema.tables
    where table_name in ('import_batches', 'satisfaction_surveys');
  if v_count <> 2 then
    raise exception 'ERRO: tabelas novas não criadas (esperado 2, encontrado %)', v_count;
  end if;

  select count(*) into v_count from information_schema.columns
    where column_name = 'data_source'
    and table_name in ('queue_entries', 'appointments', 'patients', 'notification_log');
  if v_count <> 4 then
    raise exception 'ERRO: data_source faltando em alguma tabela (esperado 4, encontrado %)', v_count;
  end if;

  select count(*) into v_count from information_schema.columns
    where column_name = 'reaproveitado_de_id' and table_name = 'appointments';
  if v_count <> 1 then
    raise exception 'ERRO: appointments.reaproveitado_de_id faltando';
  end if;

  select count(*) into v_count from pg_proc
    where proname in ('calcular_absenteismo', 'calcular_taxa_confirmacao_ativa',
                      'calcular_taxa_reaproveitamento', 'calcular_indice_satisfacao',
                      'fn_ocupacao_passada', 'fn_ocupacao_futura',
                      'map_sisreg_status_to_local', 'derive_cor_risco');
  if v_count < 8 then
    raise exception 'ERRO: funções faltando (esperado 8, encontrado %)', v_count;
  end if;

  select count(*) into v_count from kpi_configs
    where chave in ('reaproveitamento_taxa', 'confirmacao_ativa_taxa',
                    'reaproveitamento_janela_horas', 'horizonte_padrao_dias');
  if v_count <> 4 then
    raise exception 'ERRO: kpi_configs novas chaves (esperado 4, encontrado %)', v_count;
  end if;

  raise notice '✅ QUERY-1 v2 aplicada com sucesso. Migration 0001 completa.';
end $$;

-- ============================================================
-- VALIDAÇÃO MANUAL — rode estas queries depois e me reporte:
-- ============================================================
-- 1) Confirma os 4 novos KPIs (vão retornar zerados, é esperado)
-- select calcular_absenteismo(30)              as kpi1_absenteismo,
--        calcular_taxa_confirmacao_ativa(30)   as kpi5_confirmacao,
--        calcular_taxa_reaproveitamento(30,48) as kpi4_reaproveitamento,
--        calcular_indice_satisfacao(30)        as kpi6_satisfacao;
--
-- 2) Confirma as funções de ocupação
-- select * from fn_ocupacao_passada(30);
-- select * from fn_ocupacao_futura(30);
--
-- 3) Confirma as 4 novas chaves de configuração
-- select chave, categoria, label, valor_meta, unidade
--   from kpi_configs
--   where chave in ('reaproveitamento_taxa','confirmacao_ativa_taxa',
--                   'reaproveitamento_janela_horas','horizonte_padrao_dias')
--   order by ordem_exibicao;
--
-- 4) Confirma colunas data_source criadas
-- select table_name, count(*) filter (where column_name = 'data_source') as tem
--   from information_schema.columns
--   where table_name in ('queue_entries','appointments','patients','notification_log')
--   group by table_name;
-- ============================================================