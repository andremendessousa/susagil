-- =============================================================================
-- QUERY-7 — RPCs de Análise Gerencial + fix get_tendencia_absenteismo
-- Supabase project: susagil
-- Gerado em: 2026-04-13
--
-- ESCOPO:
--   1. get_absenteismo_por_executante(p_horizonte_dias, p_tipo_atendimento)
--   2. get_ubs_menor_espera(p_horizonte_dias, p_tipo_atendimento)
--   3. get_tendencia_absenteismo/3 — nova assinatura com p_media_movel_dias
--      (preserva as duas versões existentes intactas)
--
-- SCHEMA VALIDADO PREVIAMENTE:
--   appointments : scheduled_at(timestamptz), status(status_local),
--                  equipment_id(uuid), queue_entry_id(uuid),
--                  st_falta_registrada(int2), realized_at(timestamptz)
--   equipment    : id, ubs_id, nome, tipo_recurso, tipo_atendimento,
--                  status(equipment_status), capacidade_dia
--   ubs          : id, cnes_code, nome, municipio, uf, tipo
--   queue_entries: id, patient_id, ubs_id, data_solicitacao_sisreg(date),
--                  status_local, tipo_atendimento, cor_risco, prioridade_codigo
--   patients     : id, nome, municipio_residencia, uf_residencia
--
-- ENUMS VALIDADOS:
--   status_local     : realizado / faltou / agendado / aguardando / ...
--   tipo_atendimento : exame / consulta
--   equipment_status : ativo / inativo / manutencao
--
-- PRINCÍPIOS:
--   - Parâmetros sempre com DEFAULT (nunca obrigatório no frontend)
--   - p_tipo_atendimento = NULL → ambos os tipos
--   - Nenhum valor hardcoded (metas vêm de kpi_configs, horizontes do frontend)
--   - LANGUAGE sql STABLE (sem PL/pgSQL desnecessário)
--   - COMMENT em cada função para rastreabilidade
-- =============================================================================

-- =============================================================================
-- SEÇÃO 1 — get_absenteismo_por_executante
-- Pergunta respondida: "Quais unidades executantes têm maior absenteísmo?"
-- Usado por: AnaliseGerencialPage — gráfico de barras horizontais
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_absenteismo_por_executante(
    p_horizonte_dias     integer DEFAULT 30,
    p_tipo_atendimento   text    DEFAULT NULL
)
RETURNS TABLE(
    equipment_id         uuid,
    equipamento_nome     text,
    unidade_nome         text,
    municipio            text,
    tipo_recurso         text,
    tipo_atendimento     text,
    total_realizados     bigint,
    total_faltas         bigint,
    total_finalizados    bigint,
    taxa_absenteismo     numeric,
    meta_absenteismo     numeric   -- vem de kpi_configs via subquery
)
LANGUAGE sql STABLE AS $function$
    WITH periodo AS (
        SELECT
            a.equipment_id,
            COUNT(*) FILTER (WHERE a.status = 'realizado'::status_local) AS realizados,
            COUNT(*) FILTER (WHERE a.status = 'faltou'::status_local)    AS faltas,
            COUNT(*) FILTER (WHERE a.status IN (
                'realizado'::status_local, 'faltou'::status_local))      AS finalizados
        FROM appointments a
        JOIN queue_entries q ON q.id = a.queue_entry_id
        WHERE a.scheduled_at >= NOW() - (p_horizonte_dias || ' days')::interval
          AND a.scheduled_at <  NOW()
          AND a.status IN ('realizado'::status_local, 'faltou'::status_local)
          AND (p_tipo_atendimento IS NULL
               OR q.tipo_atendimento::text = p_tipo_atendimento)
        GROUP BY a.equipment_id
    ),
    meta AS (
        SELECT valor_meta
        FROM kpi_configs
        WHERE chave = 'absenteismo_taxa'
        LIMIT 1
    )
    SELECT
        e.id                                AS equipment_id,
        e.nome                              AS equipamento_nome,
        u.nome                              AS unidade_nome,
        u.municipio,
        e.tipo_recurso::text,
        e.tipo_atendimento::text,
        COALESCE(p.realizados,  0)          AS total_realizados,
        COALESCE(p.faltas,      0)          AS total_faltas,
        COALESCE(p.finalizados, 0)          AS total_finalizados,
        CASE
            WHEN COALESCE(p.finalizados, 0) = 0 THEN 0::numeric
            ELSE ROUND(
                COALESCE(p.faltas, 0)::numeric
                / COALESCE(p.finalizados, 1)::numeric * 100,
            1)
        END                                 AS taxa_absenteismo,
        COALESCE((SELECT valor_meta FROM meta), 15) AS meta_absenteismo
    FROM equipment e
    JOIN ubs u ON u.id = e.ubs_id
    LEFT JOIN periodo p ON p.equipment_id = e.id
    WHERE e.status = 'ativo'::equipment_status
      AND (p_tipo_atendimento IS NULL
           OR e.tipo_atendimento::text = p_tipo_atendimento)
    ORDER BY taxa_absenteismo DESC, total_finalizados DESC;
$function$;

COMMENT ON FUNCTION public.get_absenteismo_por_executante IS
'Ranking de absenteísmo por unidade executante no horizonte configurável.
 Usado por AnaliseGerencialPage. Meta vem de kpi_configs.absenteismo_taxa.
 ATENÇÃO PÓS-DEMO: com dados reais da API e-SUS, validar se scheduled_at
 reflete corretamente a data de realização ou apenas o agendamento.';

-- =============================================================================
-- SEÇÃO 2 — get_ubs_menor_espera
-- Pergunta respondida: "Quais UBS reguladoras têm menor tempo de espera?"
-- Usado por: AnaliseGerencialPage — tabela de ranking acionável
-- Tempo de espera = dias entre data_solicitacao_sisreg e scheduled_at
--                   (para realizados) ou hoje (para aguardando)
-- =============================================================================
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
    meta_espera_dias     numeric   -- vem de kpi_configs
)
LANGUAGE sql STABLE AS $function$
    WITH esperas AS (
        -- Calcula espera individual: data_solicitacao_sisreg → scheduled_at (realizados)
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
              )) >= 0   -- sanidade: espera não pode ser negativa
    ),
    encaminhamentos AS (
        -- Total encaminhado pela UBS no horizonte
        SELECT
            q.ubs_id,
            COUNT(*) AS total_enc,
            COUNT(*) FILTER (WHERE q.status_local = 'realizado'::status_local) AS total_real
        FROM queue_entries q
        WHERE (p_tipo_atendimento IS NULL
               OR q.tipo_atendimento::text = p_tipo_atendimento)
          AND q.data_solicitacao_sisreg >= (NOW() - (p_horizonte_dias || ' days')::interval)::date
        GROUP BY q.ubs_id
    ),
    meta AS (
        SELECT valor_meta FROM kpi_configs WHERE chave = 'espera_media_dias' LIMIT 1
    )
    SELECT
        u.id                                        AS ubs_id,
        u.nome                                      AS ubs_nome,
        u.municipio,
        u.uf,
        COALESCE(enc.total_enc,  0)                 AS total_encaminhamentos,
        COALESCE(enc.total_real, 0)                 AS total_realizados,
        COALESCE(ROUND(AVG(e.dias_espera), 1), 0)   AS espera_media_dias,
        COALESCE(ROUND(PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY e.dias_espera)::numeric, 1), 0) AS espera_mediana_dias,
        COALESCE(MIN(e.dias_espera), 0)             AS espera_min_dias,
        COALESCE(MAX(e.dias_espera), 0)             AS espera_max_dias,
        COALESCE((SELECT valor_meta FROM meta), 120) AS meta_espera_dias
    FROM ubs u
    LEFT JOIN esperas e      ON e.ubs_id = u.id
    LEFT JOIN encaminhamentos enc ON enc.ubs_id = u.id
    WHERE u.tipo = 'R'   -- apenas UBS reguladoras/encaminhadoras
      AND COALESCE(enc.total_enc, 0) > 0  -- exclui UBS sem encaminhamentos no período
    GROUP BY u.id, u.nome, u.municipio, u.uf,
             enc.total_enc, enc.total_real
    ORDER BY espera_media_dias ASC NULLS LAST;
$function$;

COMMENT ON FUNCTION public.get_ubs_menor_espera IS
'Ranking de UBS reguladoras por tempo médio de espera (data_solicitacao_sisreg → scheduled_at).
 Usado por AnaliseGerencialPage. Meta vem de kpi_configs.espera_media_dias.
 ATENÇÃO PÓS-DEMO: data_solicitacao_sisreg vem da API e-SUS como data_marcacao.
 Validar mapeamento no adaptador de ingestão antes de ir a produção.';

-- =============================================================================
-- SEÇÃO 3 — get_tendencia_absenteismo/3 (nova assinatura com média móvel)
-- Preserva intactas as duas versões existentes (1 e 2 parâmetros).
-- Adiciona 3ª versão com p_media_movel_dias para suavizar a curva.
-- Pergunta respondida: "O absenteísmo está melhorando ao longo do tempo?"
-- =============================================================================
CREATE OR REPLACE FUNCTION public.get_tendencia_absenteismo(
    p_horizonte_dias     integer DEFAULT 30,
    p_tipo_atendimento   text    DEFAULT NULL,
    p_media_movel_dias   integer DEFAULT 7
)
RETURNS TABLE(
    dia                  date,
    total                bigint,
    faltas               bigint,
    taxa                 numeric,
    taxa_media_movel     numeric   -- média móvel suavizadora
)
LANGUAGE sql STABLE AS $function$
    WITH dias AS (
        SELECT generate_series(
            (NOW() - (p_horizonte_dias || ' days')::interval)::date,
            NOW()::date,
            '1 day'::interval
        )::date AS dia
    ),
    aggregado AS (
        SELECT
            DATE(a.scheduled_at)  AS dia,
            COUNT(*)              AS total,
            COUNT(*) FILTER (WHERE a.st_falta_registrada = 1) AS faltas
        FROM appointments a
        JOIN queue_entries q ON q.id = a.queue_entry_id
        WHERE a.status IN ('realizado'::status_local, 'faltou'::status_local)
          AND a.scheduled_at >= NOW() - (p_horizonte_dias || ' days')::interval
          AND a.scheduled_at <  NOW()
          AND (p_tipo_atendimento IS NULL
               OR q.tipo_atendimento::text = p_tipo_atendimento)
        GROUP BY DATE(a.scheduled_at)
    ),
    serie AS (
        SELECT
            d.dia,
            COALESCE(a.total,  0)::bigint AS total,
            COALESCE(a.faltas, 0)::bigint AS faltas,
            CASE
                WHEN COALESCE(a.total, 0) = 0 THEN 0::numeric
                ELSE ROUND(
                    COALESCE(a.faltas, 0)::numeric
                    / COALESCE(a.total, 1)::numeric * 100,
                1)
            END AS taxa
        FROM dias d
        LEFT JOIN aggregado a ON a.dia = d.dia
    )
    SELECT
        dia,
        total,
        faltas,
        taxa,
        -- Média móvel centrada no passado (não usa dados futuros)
        ROUND(
            AVG(CASE WHEN total > 0 THEN taxa ELSE NULL END)
            OVER (
                ORDER BY dia
                ROWS BETWEEN (p_media_movel_dias - 1) PRECEDING AND CURRENT ROW
            ),
        1) AS taxa_media_movel
    FROM serie
    ORDER BY dia;
$function$;

COMMENT ON FUNCTION public.get_tendencia_absenteismo(integer, text, integer) IS
'Série temporal de absenteísmo diário com média móvel configurável.
 p_media_movel_dias: janela da média móvel (default 7 dias).
 Dias sem appointments contribuem taxa NULL para a média móvel (não distorcem).
 Versões com 1 e 2 parâmetros preservadas intactas para compatibilidade.
 ATENÇÃO PÓS-DEMO: média móvel sobre dias sem dados (total=0) retorna NULL
 — o frontend deve tratar connectNulls=false no gráfico Recharts.';

-- =============================================================================
-- SEÇÃO 4 — VALIDAÇÃO
-- =============================================================================
DO $$
DECLARE
    v_abs_count int;
    v_ubs_count int;
    v_tend_count int;
BEGIN
    -- Testa get_absenteismo_por_executante
    SELECT COUNT(*) INTO v_abs_count
    FROM get_absenteismo_por_executante(30, NULL);

    -- Testa get_ubs_menor_espera
    SELECT COUNT(*) INTO v_ubs_count
    FROM get_ubs_menor_espera(30, NULL);

    -- Testa get_tendencia_absenteismo/3
    SELECT COUNT(*) INTO v_tend_count
    FROM get_tendencia_absenteismo(30, NULL, 7);

    RAISE NOTICE '=== QUERY-7 — VALIDAÇÃO ===';
    RAISE NOTICE 'get_absenteismo_por_executante(30, NULL): % linhas', v_abs_count;
    RAISE NOTICE 'get_ubs_menor_espera(30, NULL):           % linhas', v_ubs_count;
    RAISE NOTICE 'get_tendencia_absenteismo(30, NULL, 7):   % linhas', v_tend_count;
    RAISE NOTICE '===========================';
END $$;

-- =============================================================================
-- SEÇÃO 5 — QUERIES DE VALIDAÇÃO MANUAL
-- =============================================================================

/*
-- V1: Ranking de absenteísmo por executante (exames, 30 dias)
SELECT equipamento_nome, unidade_nome, municipio,
       total_finalizados, total_faltas, taxa_absenteismo, meta_absenteismo
FROM get_absenteismo_por_executante(30, 'exame')
ORDER BY taxa_absenteismo DESC;
-- Esperado: Aroldo ~40%, HU Manha ~25%, ImageMed ~15%
*/

/*
-- V2: Ranking de UBS por menor espera (todos os tipos, 30 dias)
SELECT ubs_nome, municipio, total_encaminhamentos,
       espera_media_dias, espera_mediana_dias, meta_espera_dias
FROM get_ubs_menor_espera(30, NULL)
ORDER BY espera_media_dias ASC;
*/

/*
-- V3: Tendência com média móvel de 7 dias
SELECT dia, total, faltas, taxa, taxa_media_movel
FROM get_tendencia_absenteismo(30, NULL, 7)
WHERE total > 0
ORDER BY dia;
-- Verificar: taxa_media_movel deve ser mais suave que taxa diária
*/

/*
-- V4: Comparativo exame vs consulta no absenteísmo
SELECT tipo_atendimento, unidade_nome,
       taxa_absenteismo, total_finalizados
FROM get_absenteismo_por_executante(30, NULL)
ORDER BY tipo_atendimento, taxa_absenteismo DESC;
*/

/*
-- V5: Confirmar que as 3 assinaturas de get_tendencia_absenteismo coexistem
SELECT pg_get_function_arguments(oid) AS assinatura
FROM pg_proc
WHERE proname = 'get_tendencia_absenteismo'
ORDER BY assinatura;
-- Esperado: 3 linhas com 1, 2 e 3 parâmetros
*/

-- =============================================================================
-- FIM DA QUERY-7
-- Salvar como: supabase/migrations/202604130001_query7_rpcs_analise_gerencial.sql
-- =============================================================================
