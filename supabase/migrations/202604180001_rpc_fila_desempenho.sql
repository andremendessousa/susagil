-- ============================================================
-- SUS RAIO-X — Migration 0008
-- RPCs: Análise de Fila e Desempenho por UBS/Clínica
-- Data: 2026-04-18
-- Autor: GitHub Copilot / AssistenteIA Fase 2
--
-- Cinco funções novas para os gráficos da ZONA 6 do Dashboard
-- e para os intents do AssistenteIA.
--
-- Esquema confirmado:
--   queue_entries: id, patient_id, status_local, ubs_id, tipo_atendimento,
--                  nome_grupo_procedimento, data_solicitacao_sisreg,
--                  prioridade_codigo, tipo_vaga
--   appointments:  id, scheduled_at, equipment_id, queue_entry_id, status
--   equipment:     id, nome, ubs_id, capacidade_dia, status
--   ubs:           id, nome, municipio
--
-- Aplicar em: Supabase > SQL Editor
-- ============================================================


-- ── 1. FILA ATIVA POR UBS ENCAMINHADORA ──────────────────────────────────────
-- Pergunta: "Qual UBS tem maior fila?" / "Distribuição da fila por UBS"
-- Retorna: volume de pacientes aguardando por UBS + espera média
-- Diferente de get_ubs_menor_espera (que ranqueia por espera mínima):
--   este ranqueia por VOLUME de backlog e inclui pct do total.

create or replace function get_fila_por_ubs(
  p_horizonte_dias   int  default 30,
  p_tipo_atendimento text default null
)
returns table (
  ubs_nome          text,
  municipio         text,
  total_aguardando  bigint,
  pct_do_total      numeric,
  espera_media_dias numeric
)
language sql stable
as $$
  with base as (
    select
      u.nome                                                                     as ubs_nome,
      u.municipio,
      count(*) filter (
        where qe.status_local in ('aguardando', 'agendado')
      )                                                                          as total_aguardando,
      avg(
        extract(epoch from (now() - qe.data_solicitacao_sisreg)) / 86400.0
      ) filter (
        where qe.status_local in ('aguardando', 'agendado')
          and qe.data_solicitacao_sisreg is not null
      )                                                                          as espera_media_raw
    from queue_entries qe
    join ubs u on u.id = qe.ubs_id
    where (p_tipo_atendimento is null
           or qe.tipo_atendimento::text = p_tipo_atendimento)
    group by u.id, u.nome, u.municipio
  ),
  totais as (
    select coalesce(sum(total_aguardando), 0) as grand_total
    from base
  )
  select
    b.ubs_nome,
    b.municipio,
    b.total_aguardando,
    case when t.grand_total = 0 then 0::numeric
         else round((b.total_aguardando::numeric / t.grand_total) * 100, 1)
    end                                                                          as pct_do_total,
    round(coalesce(b.espera_media_raw, 0)::numeric, 1)                          as espera_media_dias
  from base b, totais t
  where b.total_aguardando > 0
  order by b.total_aguardando desc
  limit 15;
$$;

comment on function get_fila_por_ubs(int, text) is
  'Backlog da fila ativa (aguardando + agendado) por UBS encaminhadora. '
  'Inclui % do total e espera média. Ranqueado por volume, não por espera. '
  'Diferente de get_ubs_menor_espera. AssistenteIA: intent fila_por_ubs.';


-- ── 2. AGENDA COMPROMETIDA POR EQUIPAMENTO/CLÍNICA ───────────────────────────
-- Pergunta: "Qual clínica está mais sobrecarregada?" / "Agenda dos equipamentos"
-- Retorna: agendamentos futuros vs capacidade por equipment
-- Complementa fn_ocupacao_futura (que retorna % agregado sem separar clínicas).

create or replace function get_fila_por_clinica(
  p_horizonte_dias   int  default 30,
  p_tipo_atendimento text default null
)
returns table (
  equipamento_nome    text,
  unidade_nome        text,
  municipio           text,
  vagas_comprometidas bigint,
  capacidade_periodo  int,
  pct_carga_fila      numeric
)
language sql stable
as $$
  select
    eq.nome                                                                            as equipamento_nome,
    u.nome                                                                             as unidade_nome,
    u.municipio,
    count(a.id) filter (
      where a.status in ('agendado', 'confirmado')
    )                                                                                  as vagas_comprometidas,
    (eq.capacidade_dia * p_horizonte_dias)                                             as capacidade_periodo,
    case when eq.capacidade_dia * p_horizonte_dias = 0 then 0::numeric
         else round(
           (count(a.id) filter (
              where a.status in ('agendado', 'confirmado')
            )::numeric
            / (eq.capacidade_dia * p_horizonte_dias)::numeric) * 100, 1)
    end                                                                                as pct_carga_fila
  from equipment eq
  join ubs u on u.id = eq.ubs_id
  left join appointments a on a.equipment_id = eq.id
    and a.scheduled_at >= now()
    and a.scheduled_at <= now() + (p_horizonte_dias || ' days')::interval
    and (
      p_tipo_atendimento is null
      or exists (
        select 1 from queue_entries qe
        where qe.id = a.queue_entry_id
          and qe.tipo_atendimento::text = p_tipo_atendimento
      )
    )
  where eq.status = 'ativo'
  group by eq.id, eq.nome, u.nome, u.municipio, eq.capacidade_dia
  order by vagas_comprometidas desc
  limit 15;
$$;

comment on function get_fila_por_clinica(int, text) is
  'Agenda comprometida (agendado + confirmado) por equipamento no próximo período. '
  'pct_carga_fila = vagas_comprometidas / capacidade_total do período. '
  'AssistenteIA: intent fila_por_clinica.';


-- ── 3. SCORE COMPOSTO DE DESEMPENHO POR UBS ENCAMINHADORA ────────────────────
-- Pergunta: "Ranking das UBSs" / "Qual UBS tem melhor desempenho?"
-- Score (0–100): (100 – absenteismo%) × 0,5 + ((120 – min(espera,120)) / 120) × 50
-- Combina taxa de falta real (appointments) + espera atual (queue ativa).

create or replace function get_desempenho_por_ubs(
  p_horizonte_dias int default 30
)
returns table (
  ubs_nome          text,
  municipio         text,
  absenteismo_pct   numeric,
  espera_media_dias numeric,
  total_atendidos   bigint,
  score_composto    numeric
)
language sql stable
as $$
  with abs_data as (
    select
      u.id                                                                     as ubs_id,
      u.nome                                                                   as ubs_nome,
      u.municipio,
      count(*) filter (
        where a.status in ('realizado', 'faltou')
      )                                                                        as total_finalizados,
      count(*) filter (where a.status = 'faltou')                             as total_faltas,
      count(*) filter (where a.status = 'realizado')                          as total_atendidos
    from ubs u
    join queue_entries qe on qe.ubs_id = u.id
    join appointments  a  on a.queue_entry_id = qe.id
    where a.scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
      and a.scheduled_at <= now()
    group by u.id, u.nome, u.municipio
  ),
  espera_data as (
    select
      qe.ubs_id,
      avg(
        extract(epoch from (now() - qe.data_solicitacao_sisreg)) / 86400.0
      ) filter (
        where qe.status_local in ('aguardando', 'agendado')
          and qe.data_solicitacao_sisreg is not null
      )                                                                        as espera_media
    from queue_entries qe
    group by qe.ubs_id
  )
  select
    a.ubs_nome,
    a.municipio,
    case when a.total_finalizados = 0 then 0::numeric
         else round((a.total_faltas::numeric / a.total_finalizados) * 100, 1)
    end                                                                        as absenteismo_pct,
    round(coalesce(e.espera_media, 0)::numeric, 1)                            as espera_media_dias,
    a.total_atendidos,
    -- Score = (100 - abs%) × 0,5 + ((120 - min(espera, 120)) / 120) × 50
    round(
      (100 - case when a.total_finalizados = 0 then 0::numeric
                  else (a.total_faltas::numeric / a.total_finalizados) * 100
             end) * 0.5
      + ((120::numeric
           - least(coalesce(e.espera_media, 120)::numeric, 120)) / 120) * 50,
      1
    )                                                                          as score_composto
  from abs_data a
  left join espera_data e on e.ubs_id = a.ubs_id
  where a.total_finalizados > 0
  order by score_composto desc
  limit 15;
$$;

comment on function get_desempenho_por_ubs(int) is
  'Score composto 0-100 por UBS encaminhadora. '
  'Fórmula: (100 - abs%) × 0,5 + ((120 - min(espera,120)) / 120) × 50. '
  'Combina taxa de falta real (p_horizonte_dias) com espera da fila ativa. '
  'AssistenteIA: intent desempenho_ubs.';


-- ── 4. DEMANDA POR TIPO DE PROCEDIMENTO/EXAME ────────────────────────────────
-- Pergunta: "Quais exames mais solicitados?" / "Qual procedimento tem maior demanda?"
-- Fonte: queue_entries.nome_grupo_procedimento (fallback: tipo_atendimento)
-- Retorna top 20 por volume de solicitações.

create or replace function get_tipos_exame_solicitados(
  p_horizonte_dias   int  default 30,
  p_tipo_atendimento text default null
)
returns table (
  tipo_exame         text,
  total_solicitacoes bigint,
  pct_do_total       numeric,
  espera_media_dias  numeric
)
language sql stable
as $$
  with base as (
    select
      coalesce(
        nullif(trim(nome_grupo_procedimento), ''),
        tipo_atendimento::text,
        'Não informado'
      )                                                                     as tipo_exame,
      count(*)                                                              as total_solicitacoes,
      avg(
        extract(epoch from (now() - data_solicitacao_sisreg)) / 86400.0
      ) filter (
        where data_solicitacao_sisreg is not null
      )                                                                     as espera_media_raw
    from queue_entries
    where (p_tipo_atendimento is null
           or tipo_atendimento::text = p_tipo_atendimento)
      and (data_solicitacao_sisreg is null
           or data_solicitacao_sisreg
              >= now() - (p_horizonte_dias || ' days')::interval)
    group by coalesce(
               nullif(trim(nome_grupo_procedimento), ''),
               tipo_atendimento::text,
               'Não informado'
             )
  ),
  totais as (
    select coalesce(sum(total_solicitacoes), 0) as grand_total
    from base
  )
  select
    b.tipo_exame,
    b.total_solicitacoes,
    case when t.grand_total = 0 then 0::numeric
         else round((b.total_solicitacoes::numeric / t.grand_total) * 100, 1)
    end                                                                     as pct_do_total,
    round(coalesce(b.espera_media_raw, 0)::numeric, 1)                     as espera_media_dias
  from base b, totais t
  order by b.total_solicitacoes desc
  limit 20;
$$;

comment on function get_tipos_exame_solicitados(int, text) is
  'Volume de solicitações por tipo de procedimento/exame, com % do total e espera média. '
  'Fonte: nome_grupo_procedimento com fallback para tipo_atendimento. '
  'AssistenteIA: intent tipos_exame.';


-- ── 5. ESPERA MÉDIA E ABSENTEÍSMO POR MUNICÍPIO ───────────────────────────────
-- Pergunta: "Espera por município?" / "Qual cidade tem maior tempo de espera?"
-- Diferente de get_demanda_por_municipio (que conta encaminhamentos):
--   este calcula tempo de espera real + taxa de falta por município de origem.

create or replace function get_espera_por_municipio(
  p_horizonte_dias int default 30
)
returns table (
  municipio         text,
  total_pacientes   bigint,
  espera_media_dias numeric,
  pct_absenteismo   numeric
)
language sql stable
as $$
  with espera_data as (
    select
      u.municipio,
      count(distinct qe.id)                                                      as total_pacientes,
      avg(
        extract(epoch from (now() - qe.data_solicitacao_sisreg)) / 86400.0
      ) filter (
        where qe.status_local in ('aguardando', 'agendado')
          and qe.data_solicitacao_sisreg is not null
      )                                                                           as espera_media
    from queue_entries qe
    join ubs u on u.id = qe.ubs_id
    where qe.status_local in ('aguardando', 'agendado', 'realizado', 'faltou')
      and (
        qe.data_solicitacao_sisreg is null
        or qe.data_solicitacao_sisreg
           >= now() - (p_horizonte_dias || ' days')::interval
      )
    group by u.municipio
  ),
  abs_data as (
    select
      u.municipio,
      count(*) filter (
        where a.status in ('realizado', 'faltou')
      )                                                                           as total_finalizados,
      count(*) filter (where a.status = 'faltou')                                as total_faltas
    from ubs u
    join queue_entries qe on qe.ubs_id = u.id
    join appointments  a  on a.queue_entry_id = qe.id
    where a.scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
      and a.scheduled_at <= now()
    group by u.municipio
  )
  select
    e.municipio,
    e.total_pacientes,
    round(coalesce(e.espera_media, 0)::numeric, 1)                               as espera_media_dias,
    case when coalesce(a.total_finalizados, 0) = 0 then 0::numeric
         else round((a.total_faltas::numeric / a.total_finalizados) * 100, 1)
    end                                                                           as pct_absenteismo
  from espera_data e
  left join abs_data a on a.municipio = e.municipio
  where e.municipio is not null
  order by e.espera_media desc nulls last
  limit 20;
$$;

comment on function get_espera_por_municipio(int) is
  'Tempo de espera médio + taxa de absenteísmo por município de origem do paciente. '
  'Diferente de get_demanda_por_municipio (que conta encaminhamentos). '
  'AssistenteIA: intent espera_por_municipio.';


-- ── VALIDAÇÃO ─────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  select count(*) into v_count
  from pg_proc
  where proname in (
    'get_fila_por_ubs',
    'get_fila_por_clinica',
    'get_desempenho_por_ubs',
    'get_tipos_exame_solicitados',
    'get_espera_por_municipio'
  );

  if v_count < 5 then
    raise exception
      'ERRO Migration 0008: % de 5 funções criadas.', v_count;
  end if;

  raise notice '✅ Migration 0008 aplicada — % funções criadas.', v_count;
end $$;
