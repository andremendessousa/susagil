-- ============================================================
-- SUS RAIO-X — Migration 202604230001
-- Fix: get_ubs_menor_espera — incluir UBSs com aguardando sem realizados
-- Referência: Edital CPSI 004/2026
-- Data: 2026-04-23
--
-- PROBLEMA:
--   A função excluía UBSs onde COALESCE(enc.total_enc, 0) = 0.
--   A CTE "encaminhamentos" só contava queue_entries com
--   data_solicitacao_sisreg >= now() - p_horizonte_dias.
--   UBSs com pacientes "aguardando" sem appointments realizados no período
--   (ex: Independência II com 20 aguardando) eram excluídas do painel
--   "Tempo de espera por UBS encaminhadora".
--
-- SOLUÇÃO:
--   Adicionar CTE "aguardando" que conta queue_entries.status_local = 'aguardando'.
--   Incluir UBSs que têm aguardando mesmo sem realizados no horizonte.
--   espera_media_dias calculada somente dos realizados (semanticamente correto);
--   total_encaminhamentos = realizados + aguardando (visão completa da demanda).
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_ubs_menor_espera(
    p_horizonte_dias     integer DEFAULT 30,
    p_tipo_atendimento   text    DEFAULT NULL
)
RETURNS TABLE(
    ubs_id               uuid,
    ubs_nome             text,
    municipio            text,
    uf                   text,
    total_encaminhamentos bigint,
    total_realizados     bigint,
    espera_media_dias    numeric,
    espera_mediana_dias  numeric,
    espera_min_dias      integer,
    espera_max_dias      integer,
    meta_espera_dias     numeric
)
LANGUAGE sql STABLE AS $function$
    WITH esperas AS (
        -- Espera individual: data_solicitacao_sisreg → scheduled_at (realizados)
        SELECT
            q.ubs_id,
            EXTRACT(DAY FROM (
                a.scheduled_at - q.data_solicitacao_sisreg::timestamptz
            ))::integer AS dias_espera
        FROM queue_entries q
        JOIN appointments a ON a.queue_entry_id = q.id
        WHERE a.status = 'realizado'::status_local
          AND a.scheduled_at >= NOW() - (p_horizonte_dias || ' days')::interval
          AND a.scheduled_at <  NOW()
          AND q.data_solicitacao_sisreg IS NOT NULL
          AND (p_tipo_atendimento IS NULL
               OR q.tipo_atendimento::text = p_tipo_atendimento)
          AND EXTRACT(DAY FROM (
                a.scheduled_at - q.data_solicitacao_sisreg::timestamptz
              )) >= 0
    ),
    realizados AS (
        -- Contagem de realizados por UBS no horizonte
        SELECT
            q.ubs_id,
            COUNT(*) AS total_real
        FROM appointments a
        JOIN queue_entries q ON q.id = a.queue_entry_id
        WHERE a.status = 'realizado'::status_local
          AND a.scheduled_at >= NOW() - (p_horizonte_dias || ' days')::interval
          AND a.scheduled_at <  NOW()
          AND (p_tipo_atendimento IS NULL
               OR q.tipo_atendimento::text = p_tipo_atendimento)
        GROUP BY q.ubs_id
    ),
    aguardando AS (
        -- Pacientes na fila aguardando — presença deles justifica a UBS aparecer no painel
        -- mesmo que nenhum tenha sido realizado no período
        SELECT
            ubs_id,
            COUNT(*) AS total_aguard
        FROM queue_entries
        WHERE status_local = 'aguardando'
          AND (p_tipo_atendimento IS NULL
               OR tipo_atendimento::text = p_tipo_atendimento)
        GROUP BY ubs_id
    ),
    meta AS (
        SELECT valor_meta FROM kpi_configs WHERE chave = 'espera_media_dias' LIMIT 1
    )
    SELECT
        u.id                                        AS ubs_id,
        u.nome                                      AS ubs_nome,
        u.municipio,
        u.uf,
        -- Total = realizados no horizonte + aguardando na fila (visão completa da demanda)
        COALESCE(r.total_real, 0) + COALESCE(aw.total_aguard, 0) AS total_encaminhamentos,
        COALESCE(r.total_real, 0)                   AS total_realizados,
        -- Espera média calculada apenas dos realizados (evita misturar apples e oranges)
        COALESCE(ROUND(AVG(e.dias_espera), 1), 0)   AS espera_media_dias,
        COALESCE(ROUND(PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY e.dias_espera)::numeric, 1), 0) AS espera_mediana_dias,
        COALESCE(MIN(e.dias_espera), 0)             AS espera_min_dias,
        COALESCE(MAX(e.dias_espera), 0)             AS espera_max_dias,
        COALESCE((SELECT valor_meta FROM meta), 120) AS meta_espera_dias
    FROM ubs u
    LEFT JOIN esperas    e  ON e.ubs_id  = u.id
    LEFT JOIN realizados r  ON r.ubs_id  = u.id
    LEFT JOIN aguardando aw ON aw.ubs_id = u.id
    WHERE u.tipo = 'R'   -- apenas UBS reguladoras/encaminhadoras
      -- Inclui UBSs que têm realizados OU aguardando — não exclui piloto sem histórico
      AND (COALESCE(r.total_real, 0) > 0 OR COALESCE(aw.total_aguard, 0) > 0)
    GROUP BY u.id, u.nome, u.municipio, u.uf,
             r.total_real, aw.total_aguard
    ORDER BY espera_media_dias DESC NULLS LAST;
$function$;

COMMENT ON FUNCTION public.get_ubs_menor_espera(integer, text) IS
'Ranking de UBS reguladoras por tempo médio de espera (data_solicitacao_sisreg → scheduled_at).
 Inclui UBSs com aguardando mesmo sem realizados no período (ex: piloto Independência II).
 total_encaminhamentos = realizados + aguardando (visão completa da demanda por UBS).
 espera_media_dias calculada apenas dos realizados com data_solicitacao_sisreg preenchida.
 Meta vem de kpi_configs.espera_media_dias.
 Corrigido em 2026-04-23 (migration 202604230001).';

-- ══════════════════════════════════════════════════════════════════════════════
--  VERIFICAÇÃO
-- ══════════════════════════════════════════════════════════════════════════════

-- V1: Independência II deve aparecer mesmo sem realizados
-- SELECT ubs_nome, municipio, total_encaminhamentos, total_realizados, espera_media_dias
-- FROM get_ubs_menor_espera(30, NULL)
-- WHERE ubs_nome ILIKE '%Independ%';
-- Esperado: 1 linha com total_encaminhamentos > 0, espera_media_dias = 0 (sem realizados)

-- V2: Listagem completa — ordenada por espera DESC
-- SELECT ubs_nome, total_encaminhamentos, total_realizados, espera_media_dias, meta_espera_dias
-- FROM get_ubs_menor_espera(30, NULL)
-- ORDER BY espera_media_dias DESC;

-- V3: Filtro por tipo (consultas de ortopedia)
-- SELECT ubs_nome, total_encaminhamentos, espera_media_dias
-- FROM get_ubs_menor_espera(30, 'consulta')
-- ORDER BY espera_media_dias DESC;
