-- ============================================================
-- SUS RAIO-X — Migration 202604240008
-- Fix: get_tipos_exame_solicitados + get_espera_por_municipio
-- Lógica: Opção C
--   • Histórico  → filtrado por appointments.scheduled_at no período
--   • Fila ativa → filtrado por data_solicitacao_sisreg no período
--
-- ANTES (bug): WHERE data_solicitacao_sisreg >= now() - horizonte
--   → Excluía TODOS os aguardando com solicitação > horizonte dias
--   → Chart 30d ficava vazio pois seeds têm datas de 50-190d atrás
--
-- DEPOIS (Opção C): dois critérios OR independentes
--   → Histórico responde ao seletor via appointments.scheduled_at
--   → Fila ativa responde ao seletor via data_solicitacao_sisreg
--   → Seletor 7d/30d/90d filtra corretamente ambos os tipos de registro
--
-- ROLLBACK DESTA MIGRATION:
--   Re-executar a definição original de 202604180001_rpc_fila_desempenho.sql
--   (as RPCs sobreescrevem a si mesmas com CREATE OR REPLACE — sem perda de dados)
--
-- Data: 2026-04-20
-- ============================================================


-- ── 4. DEMANDA POR TIPO DE PROCEDIMENTO/EXAME (Reescrita — Opção C) ─────────
-- Opção C: histórico via appointments.scheduled_at; fila ativa via data_solicitacao_sisreg

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
        nullif(trim(qe.nome_grupo_procedimento), ''),
        qe.tipo_atendimento::text,
        'Não informado'
      )                                                                     as tipo_exame,
      count(*)                                                              as total_solicitacoes,
      avg(
        extract(epoch from (now() - qe.data_solicitacao_sisreg)) / 86400.0
      ) filter (
        where qe.data_solicitacao_sisreg is not null
      )                                                                     as espera_media_raw
    from queue_entries qe
    where (p_tipo_atendimento is null
           or qe.tipo_atendimento::text = p_tipo_atendimento)
      and (
        -- Opção C — histórico: appointment ACONTECEU dentro do período (passado)
        -- ATENÇÃO: <= now() é obrigatório — sem ele, appointments FUTUROS (status=agendado,
        -- scheduled_at > now()) satisfazem trivialmente ">= now()-30d" e inflam ambos os
        -- períodos com todos os tipos de procedimento, tornando 30d = 90d.
        exists (
          select 1 from appointments a
          where a.queue_entry_id = qe.id
            and a.scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
            and a.scheduled_at <= now()
        )
        -- Opção C — fila ativa: solicitação dentro do período (ou sem data → sempre inclui)
        or (
          qe.status_local in ('aguardando', 'agendado')
          and (
            qe.data_solicitacao_sisreg is null
            or qe.data_solicitacao_sisreg
               >= now() - (p_horizonte_dias || ' days')::interval
          )
        )
      )
    group by coalesce(
               nullif(trim(qe.nome_grupo_procedimento), ''),
               qe.tipo_atendimento::text,
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
  'Opção C: histórico filtrado por appointments.scheduled_at; fila ativa por data_solicitacao_sisreg. '
  'Fonte: nome_grupo_procedimento com fallback para tipo_atendimento. '
  'AssistenteIA: intent tipos_exame.';


-- ── 5. ESPERA MÉDIA E ABSENTEÍSMO POR MUNICÍPIO (Reescrita — Opção C) ───────
-- Opção C: histórico via appointments.scheduled_at; fila ativa via data_solicitacao_sisreg
-- A espera_media é calculada SOMENTE sobre os aguardando/agendado que estejam no período.

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
          and qe.data_solicitacao_sisreg
              >= now() - (p_horizonte_dias || ' days')::interval
      )                                                                           as espera_media
    from queue_entries qe
    join ubs u on u.id = qe.ubs_id
    where (
      -- Opção C — histórico: appointment no período
      exists (
        select 1 from appointments a
        where a.queue_entry_id = qe.id
          and a.scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
          and a.scheduled_at <= now()
      )
      -- Opção C — fila ativa: solicitação no período (ou sem data → sempre inclui)
      or (
        qe.status_local in ('aguardando', 'agendado')
        and (
          qe.data_solicitacao_sisreg is null
          or qe.data_solicitacao_sisreg
             >= now() - (p_horizonte_dias || ' days')::interval
        )
      )
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
  'Opção C: histórico filtrado por appointments.scheduled_at; fila ativa por data_solicitacao_sisreg. '
  'espera_media calculada apenas sobre aguardando/agendado dentro do período. '
  'AssistenteIA: intent espera_por_municipio.';


-- ── VALIDAÇÃO ────────────────────────────────────────────────────────────────
do $$
declare
  v_count int;
begin
  select count(*) into v_count
  from pg_proc
  where proname in (
    'get_tipos_exame_solicitados',
    'get_espera_por_municipio'
  );

  if v_count < 2 then
    raise exception
      'ERRO Migration 202604240008: % de 2 RPCs encontradas.', v_count;
  end if;

  raise notice '✅ Migration 202604240008 — % RPCs atualizadas (Opção C).', v_count;
  raise notice '   NOTA: Para popular o chart 30d, execute TAMBÉM a migration 202604240009';
  raise notice '         (seed fresh+old balanceado). Sem ela o chart 30d ainda ficará vazio.';
end $$;

-- ── VERIFICAÇÕES MANUAIS (após executar também migration 009) ────────────────
-- V1 — Procedimentos em 30d (esperado: retorna rows após seed 009)
-- SELECT tipo_exame, total_solicitacoes FROM get_tipos_exame_solicitados(30) LIMIT 5;

-- V2 — Espera por município em 30d (esperado: Montes Claros + Bocaiúva + Pirapora + Janaúba)
-- SELECT municipio, total_pacientes, espera_media_dias FROM get_espera_por_municipio(30) LIMIT 5;

-- V3 — Comparação 30d vs 90d (30d deve ter menos rows que 90d)
-- SELECT COUNT(*) as c_30d FROM get_tipos_exame_solicitados(30);
-- SELECT COUNT(*) as c_90d FROM get_tipos_exame_solicitados(90);
