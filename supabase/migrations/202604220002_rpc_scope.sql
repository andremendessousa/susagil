-- ============================================================
-- SUS RAIO-X — Migration 202604220002
-- Unificação de RPCs com overloads ambíguos + filtros de escopo geográfico
-- Referência: Edital CPSI 004/2026
-- Data: 2026-04-20
--
-- PROBLEMA:
--   PostgreSQL lança "ambiguous function call" quando dois overloads de uma
--   função com DEFAULT NULL são ambos candidatos para a mesma chamada nomeada.
--   Ex: calcular_absenteismo(int,text) e calcular_absenteismo(int,text,text[])
--   ambos casam com rpc('calcular_absenteismo', {p_horizonte_dias, p_tipo_atendimento}).
--
-- SOLUÇÃO:
--   DROP de todos os overloads → CREATE de uma função ÚNICA por RPC.
--   Novos parâmetros com DEFAULT NULL: 100% backward compatible.
--   Chamadas existentes do frontend (sem p_municipios) continuam funcionando.
--
-- FUNÇÕES AFETADAS:
--   A. get_tendencia_absenteismo   — DROP 3 → CREATE v4(int, text, int, text[])
--   B. calcular_absenteismo        — DROP 3 → CREATE v4(int, text, text[], text[])
--   C. calcular_tempo_medio_espera — DROP 3 → CREATE v4(int, text, text[], text[])
--   D. calcular_demanda_reprimida  — DROP 3 → CREATE v4(int, int, text, text[], text[])
--   E. fn_ocupacao_passada         — DROP 3 → CREATE v4(int, text, text[], text[])
--
-- ESCOPO GEOGRÁFICO (mapeamento front → banco):
--   MUNICIPAL              → p_municipios = ARRAY['Montes Claros']
--   MACRORREGIAO           → p_municipios = NULL  (sem filtro)
--   REGIONAL_INDEPENDENCIA → p_executante_nomes = ARRAY['HU Clemente de Faria — Ortopedia']  (oferta)
--                            p_ubs_reguladora_nomes = ARRAY['Independência II']              (demanda)
-- ============================================================


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE A — get_tendencia_absenteismo
--
--  Overloads atuais no banco:
--    v1: (integer DEFAULT 30)
--    v2: (integer DEFAULT 30, text DEFAULT NULL)
--    v3: (integer DEFAULT 30, text DEFAULT NULL, integer DEFAULT 7)  ← Query-7
--
--  Nova assinatura v4: (int, text, int, text[])
--    Mantém p_media_movel_dias = 7 (suavização de curva do Query-7)
--    Adiciona p_executante_nomes: filtra por ubs.nome do executante
--    Usado pelo 2º useDashboardCharts (chartsExtra) no escopo Regional Independência
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.get_tendencia_absenteismo(integer);
DROP FUNCTION IF EXISTS public.get_tendencia_absenteismo(integer, text);
DROP FUNCTION IF EXISTS public.get_tendencia_absenteismo(integer, text, integer);

CREATE OR REPLACE FUNCTION public.get_tendencia_absenteismo(
    p_horizonte_dias   integer DEFAULT 30,
    p_tipo_atendimento text    DEFAULT NULL,
    p_media_movel_dias integer DEFAULT 7,
    p_executante_nomes text[]  DEFAULT NULL
)
RETURNS TABLE(
    dia              date,
    total            bigint,
    faltas           bigint,
    taxa             numeric,
    taxa_media_movel numeric
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
            DATE(a.scheduled_at)                                AS dia,
            COUNT(*)                                            AS total,
            COUNT(*) FILTER (WHERE a.st_falta_registrada = 1)  AS faltas
        FROM appointments a
        JOIN queue_entries q  ON q.id  = a.queue_entry_id
        JOIN equipment     eq ON eq.id = a.equipment_id
        JOIN ubs           u  ON u.id  = eq.ubs_id
        WHERE a.status IN ('realizado'::status_local, 'faltou'::status_local)
          AND a.scheduled_at >= NOW() - (p_horizonte_dias || ' days')::interval
          AND a.scheduled_at <  NOW()
          AND (p_tipo_atendimento IS NULL OR q.tipo_atendimento::text = p_tipo_atendimento)
          AND (p_executante_nomes IS NULL OR u.nome = ANY(p_executante_nomes))
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
        -- Dias sem appointments (total=0) contribuem NULL — não distorcem a média
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

COMMENT ON FUNCTION public.get_tendencia_absenteismo(integer, text, integer, text[]) IS
'Série temporal de absenteísmo diário com média móvel configurável e filtro de executante.
 p_executante_nomes: filtra por ubs.nome (ex: ARRAY[''HU Clemente de Faria — Ortopedia'']).
 p_media_movel_dias: tamanho da janela da média móvel (default 7).
 Frontend deve usar connectNulls=false no gráfico Recharts para dias sem dados.
 Unificado de 3 overloads em 2026-04-20 (migration 202604220002).';


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE B — calcular_absenteismo
--
--  Overloads atuais:
--    v1: (integer DEFAULT 30)
--    v2: (integer DEFAULT 30, text DEFAULT NULL)  ← JOIN queue_entries existente
--
--  Nova assinatura v4: (int, text, text[], text[])
--    Adiciona p_municipios: filtra por queue_entries.municipio_paciente
--    Adiciona p_executante_nomes: filtra por ubs.nome via equipment (métrica de oferta)
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.calcular_absenteismo(integer);
DROP FUNCTION IF EXISTS public.calcular_absenteismo(integer, text);
DROP FUNCTION IF EXISTS public.calcular_absenteismo(integer, text, text[]);

CREATE OR REPLACE FUNCTION public.calcular_absenteismo(
    p_horizonte_dias   integer DEFAULT 30,
    p_tipo_atendimento text    DEFAULT NULL,
    p_municipios       text[]  DEFAULT NULL,
    p_executante_nomes text[]  DEFAULT NULL
)
RETURNS json LANGUAGE sql STABLE AS $function$
    SELECT json_build_object(
        'horizonte_dias',    p_horizonte_dias,
        'tipo_atendimento',  coalesce(p_tipo_atendimento, 'todos'),
        'faltas',            count(*) FILTER (WHERE a.st_falta_registrada = 1),
        'total_finalizados', count(*),
        'taxa_absenteismo',
            CASE
                WHEN count(*) = 0 THEN 0
                ELSE round(
                    (count(*) FILTER (WHERE a.st_falta_registrada = 1)::numeric
                     / count(*)::numeric) * 100,
                1)
            END
    )
    FROM appointments a
    JOIN queue_entries q  ON q.id  = a.queue_entry_id
    JOIN equipment     eq ON eq.id = a.equipment_id
    JOIN ubs           u  ON u.id  = eq.ubs_id
    WHERE a.status IN ('realizado', 'faltou')
      AND a.scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
      AND a.scheduled_at <= now()
      AND (p_tipo_atendimento IS NULL OR q.tipo_atendimento::text = p_tipo_atendimento)
      AND (p_municipios       IS NULL OR q.municipio_paciente     = ANY(p_municipios))
      AND (p_executante_nomes IS NULL OR u.nome                   = ANY(p_executante_nomes));
$function$;

COMMENT ON FUNCTION public.calcular_absenteismo(integer, text, text[], text[]) IS
'KPI #1 do edital. Absenteísmo no horizonte configurável, filtrável por tipo, município e executante.
 p_municipios NULL = agregação global (macrorregião).
 p_executante_nomes: filtra por ubs.nome do executante (ex: ARRAY[''HU Clemente de Faria — Ortopedia'']).
 Unificado de 2 overloads em 2026-04-20 (migration 202604220002).';


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE C — calcular_tempo_medio_espera
--
--  Overloads atuais:
--    v1: (integer DEFAULT 30)
--    v2: (integer DEFAULT 30, text DEFAULT NULL)  ← 2 CTEs: aguardando + realizados
--
--  Nova assinatura v4: (int, text, text[], text[])
--    Adiciona p_municipios: filtra por municipio_paciente (ambas as CTEs)
--    Adiciona p_ubs_reguladora_nomes: filtra por ubs.nome via queue_entries.ubs_id (métrica de demanda)
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.calcular_tempo_medio_espera(integer);
DROP FUNCTION IF EXISTS public.calcular_tempo_medio_espera(integer, text);
DROP FUNCTION IF EXISTS public.calcular_tempo_medio_espera(integer, text, text[]);

CREATE OR REPLACE FUNCTION public.calcular_tempo_medio_espera(
    p_horizonte_dias        integer DEFAULT 30,
    p_tipo_atendimento      text    DEFAULT NULL,
    p_municipios            text[]  DEFAULT NULL,
    p_ubs_reguladora_nomes  text[]  DEFAULT NULL
)
RETURNS json LANGUAGE sql STABLE AS $function$
    WITH aguardando AS (
        SELECT
            avg(extract(day FROM (now() - coalesce(qe.data_solicitacao_sisreg, qe.created_at))))::numeric AS dias_avg,
            count(*) AS total
        FROM queue_entries qe
        LEFT JOIN ubs u_reg ON u_reg.id = qe.ubs_id
        WHERE qe.status_local = 'aguardando'
          AND (p_tipo_atendimento      IS NULL OR qe.tipo_atendimento::text = p_tipo_atendimento)
          AND (p_municipios            IS NULL OR qe.municipio_paciente     = ANY(p_municipios))
          AND (p_ubs_reguladora_nomes  IS NULL OR u_reg.nome               = ANY(p_ubs_reguladora_nomes))
    ),
    realizados AS (
        SELECT
            avg(extract(day FROM (a.realized_at - coalesce(q.data_solicitacao_sisreg, q.created_at))))::numeric AS dias_avg,
            count(*) AS total
        FROM appointments a
        JOIN queue_entries q ON q.id = a.queue_entry_id
        LEFT JOIN ubs u_reg ON u_reg.id = q.ubs_id
        WHERE a.status = 'realizado'
          AND a.realized_at IS NOT NULL
          AND a.realized_at >= now() - (p_horizonte_dias || ' days')::interval
          AND (p_tipo_atendimento      IS NULL OR q.tipo_atendimento::text = p_tipo_atendimento)
          AND (p_municipios            IS NULL OR q.municipio_paciente     = ANY(p_municipios))
          AND (p_ubs_reguladora_nomes  IS NULL OR u_reg.nome              = ANY(p_ubs_reguladora_nomes))
    )
    SELECT json_build_object(
        'horizonte_dias',       p_horizonte_dias,
        'tipo_atendimento',     coalesce(p_tipo_atendimento, 'todos'),
        'espera_atual_dias',    coalesce(round((SELECT dias_avg FROM aguardando), 1), 0),
        'total_aguardando',     (SELECT total FROM aguardando),
        'espera_historica_dias', coalesce(round((SELECT dias_avg FROM realizados), 1), 0),
        'total_realizados',     (SELECT total FROM realizados)
    );
$function$;

COMMENT ON FUNCTION public.calcular_tempo_medio_espera(integer, text, text[], text[]) IS
'KPI #2 do edital. Tempo médio de espera atual (aguardando) e histórico (realizados).
 p_municipios NULL = agregação global.
 p_ubs_reguladora_nomes: filtra pela UBS reguladora que encaminhou (queue_entries.ubs_id).
 Unificado de 2 overloads em 2026-04-20 (migration 202604220002).';


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE D — calcular_demanda_reprimida
--
--  Overloads atuais:
--    v1: (integer DEFAULT 30, integer DEFAULT 30)
--    v2: (integer DEFAULT 30, integer DEFAULT 30, text DEFAULT NULL)
--
--  Nova assinatura v4: (int, int, text, text[], text[])
--    Adiciona p_municipios ao main query E à subquery de por_prioridade
--    Adiciona p_ubs_reguladora_nomes: filtra por ubs.nome via queue_entries.ubs_id (métrica de demanda)
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.calcular_demanda_reprimida(integer, integer);
DROP FUNCTION IF EXISTS public.calcular_demanda_reprimida(integer, integer, text);
DROP FUNCTION IF EXISTS public.calcular_demanda_reprimida(integer, integer, text, text[]);

CREATE OR REPLACE FUNCTION public.calcular_demanda_reprimida(
    p_horizonte_dias        integer DEFAULT 30,
    p_dias_limite           integer DEFAULT 30,
    p_tipo_atendimento      text    DEFAULT NULL,
    p_municipios            text[]  DEFAULT NULL,
    p_ubs_reguladora_nomes  text[]  DEFAULT NULL
)
RETURNS json LANGUAGE sql STABLE AS $function$
    SELECT json_build_object(
        'horizonte_dias',    p_horizonte_dias,
        'dias_limite',       p_dias_limite,
        'tipo_atendimento',  coalesce(p_tipo_atendimento, 'todos'),
        'total_reprimida',   count(*),
        'por_prioridade',    (
            SELECT json_object_agg(prioridade_codigo, qtd)
            FROM (
                SELECT qe2.prioridade_codigo, count(*) AS qtd
                FROM queue_entries qe2
                LEFT JOIN ubs u_reg2 ON u_reg2.id = qe2.ubs_id
                WHERE qe2.status_local = 'aguardando'
                  AND extract(day FROM (now() - coalesce(qe2.data_solicitacao_sisreg, qe2.created_at))) > p_dias_limite
                  AND (p_tipo_atendimento      IS NULL OR qe2.tipo_atendimento::text = p_tipo_atendimento)
                  AND (p_municipios            IS NULL OR qe2.municipio_paciente     = ANY(p_municipios))
                  AND (p_ubs_reguladora_nomes  IS NULL OR u_reg2.nome               = ANY(p_ubs_reguladora_nomes))
                GROUP BY qe2.prioridade_codigo
            ) x
        )
    )
    FROM queue_entries qe
    LEFT JOIN ubs u_reg ON u_reg.id = qe.ubs_id
    WHERE qe.status_local = 'aguardando'
      AND extract(day FROM (now() - coalesce(qe.data_solicitacao_sisreg, qe.created_at))) > p_dias_limite
      AND (p_tipo_atendimento      IS NULL OR qe.tipo_atendimento::text = p_tipo_atendimento)
      AND (p_municipios            IS NULL OR qe.municipio_paciente     = ANY(p_municipios))
      AND (p_ubs_reguladora_nomes  IS NULL OR u_reg.nome                = ANY(p_ubs_reguladora_nomes));
$function$;

COMMENT ON FUNCTION public.calcular_demanda_reprimida(integer, integer, text, text[], text[]) IS
'KPI do edital. Pacientes aguardando além do limite configurável (default 30d).
 p_municipios NULL = agregação global.
 p_ubs_reguladora_nomes: filtra pela UBS reguladora que encaminhou (queue_entries.ubs_id).
 Unificado de 2 overloads em 2026-04-20 (migration 202604220002).';


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE E — fn_ocupacao_passada
--
--  Overloads atuais:
--    v1: (integer DEFAULT 30)
--    v2: (integer DEFAULT 30, text DEFAULT NULL)  ← filtra por eq.tipo_atendimento
--
--  Nova assinatura v4: (int, text, text[], text[])
--    Mantém filtro de tipo NO WHERE (sobre equipment, como em v2).
--    Adiciona p_municipios via subquery no LEFT JOIN de appointments.
--    Adiciona p_executante_nomes: filtra por u.nome (ubs do equipment, already JOINed).
--      - equipment sem appointments aparece com exames_realizados=0 (comportamento inalterado)
-- ══════════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.fn_ocupacao_passada(integer);
DROP FUNCTION IF EXISTS public.fn_ocupacao_passada(integer, text);
DROP FUNCTION IF EXISTS public.fn_ocupacao_passada(integer, text, text[]);

CREATE OR REPLACE FUNCTION public.fn_ocupacao_passada(
    p_dias_atras       integer DEFAULT 30,
    p_tipo_atendimento text    DEFAULT NULL,
    p_municipios       text[]  DEFAULT NULL,
    p_executante_nomes text[]  DEFAULT NULL
)
RETURNS TABLE(
    equipment_id      uuid,
    equipamento_nome  text,
    unidade_nome      text,
    tipo_recurso      text,
    tipo_atendimento  text,
    capacidade_total  integer,
    exames_realizados bigint,
    pct_ocupacao      numeric
)
LANGUAGE sql STABLE AS $function$
    SELECT
        eq.id,
        eq.nome,
        u.nome,
        eq.tipo_recurso::text,
        eq.tipo_atendimento::text,
        eq.capacidade_dia * p_dias_atras                                            AS capacidade_total,
        COUNT(a_fil.id) FILTER (WHERE a_fil.status = 'realizado')                  AS exames_realizados,
        CASE
            WHEN eq.capacidade_dia * p_dias_atras = 0 THEN 0
            ELSE ROUND(
                (COUNT(a_fil.id) FILTER (WHERE a_fil.status = 'realizado')::numeric
                 / (eq.capacidade_dia * p_dias_atras)::numeric) * 100,
            1)
        END                                                                         AS pct_ocupacao
    FROM equipment eq
    JOIN ubs u ON u.id = eq.ubs_id
    -- Subquery isola o filtro de municipio: appointments sem queue_entry_id
    -- nunca casam com p_municipios <> NULL → contados apenas quando p_municipios IS NULL
    LEFT JOIN (
        SELECT a.equipment_id, a.id, a.status
        FROM appointments a
        LEFT JOIN queue_entries q ON q.id = a.queue_entry_id
        WHERE a.scheduled_at >= NOW() - (p_dias_atras || ' days')::interval
          AND a.scheduled_at <= NOW()
          AND (p_municipios IS NULL OR q.municipio_paciente = ANY(p_municipios))
    ) a_fil ON a_fil.equipment_id = eq.id
    WHERE eq.status = 'ativo'
      AND (p_tipo_atendimento IS NULL OR eq.tipo_atendimento::text = p_tipo_atendimento)
      AND (p_executante_nomes IS NULL OR u.nome                   = ANY(p_executante_nomes))
    GROUP BY eq.id, eq.nome, u.nome, eq.tipo_recurso, eq.tipo_atendimento, eq.capacidade_dia
    ORDER BY pct_ocupacao DESC;
$function$;

COMMENT ON FUNCTION public.fn_ocupacao_passada(integer, text, text[], text[]) IS
'KPI #3 do edital. Capacidade entregue: % da capacidade dos últimos N dias realizada.
 p_municipios filtra os appointments contabilizados (não remove o equipment do resultado).
 p_municipios NULL = conta todos os appointments (agregação global).
 p_executante_nomes: filtra por u.nome do executante (remove equipment de outras UBSs).
 Unificado de 2 overloads em 2026-04-20 (migration 202604220002).';


-- ══════════════════════════════════════════════════════════════════════════════
--  VERIFICAÇÃO
-- ══════════════════════════════════════════════════════════════════════════════

-- V1: cada função deve ter exatamente 1 overload (pronargs únicos por proname)
-- SELECT proname, pronargs, pg_get_function_arguments(oid) AS assinatura
-- FROM pg_proc
-- WHERE proname IN (
--   'get_tendencia_absenteismo', 'calcular_absenteismo',
--   'calcular_tempo_medio_espera', 'calcular_demanda_reprimida', 'fn_ocupacao_passada'
-- )
-- ORDER BY proname;
-- Esperado: 1 linha por function (5 linhas total)

-- V2: testar scope MUNICIPAL (absenteísmo por município)
-- SELECT calcular_absenteismo(30, null, ARRAY['Montes Claros'], null)::jsonb;
-- SELECT calcular_absenteismo(30, null, null, null)::jsonb;
-- Esperado: global >= municipal

-- V3: testar scope REGIONAL INDEPENDÊNCIA — oferta (absenteísmo por executante)
-- SELECT calcular_absenteismo(30, null, null, ARRAY['HU Clemente de Faria — Ortopedia'])::jsonb;

-- V4: testar scope REGIONAL INDEPENDÊNCIA — demanda (espera por UBS reguladora)
-- SELECT calcular_tempo_medio_espera(30, null, null, ARRAY['Independência II'])::jsonb;

-- V5: testar demanda reprimida por UBS reguladora
-- SELECT calcular_demanda_reprimida(30, 30, null, null, ARRAY['Independência II'])::jsonb;

-- V6: tendência com executante Regional Independência
-- SELECT * FROM get_tendencia_absenteismo(30, null, 7, ARRAY['HU Clemente de Faria — Ortopedia'])
-- WHERE total > 0;

-- V7: fn_ocupacao_passada com e sem executante
-- SELECT equipamento_nome, exames_realizados, pct_ocupacao
-- FROM fn_ocupacao_passada(30, null, null, null) ORDER BY pct_ocupacao DESC;
-- SELECT equipamento_nome, exames_realizados, pct_ocupacao
-- FROM fn_ocupacao_passada(30, null, null, ARRAY['HU Clemente de Faria — Ortopedia']) ORDER BY pct_ocupacao DESC;
