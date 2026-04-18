-- ============================================================
-- SUS RAIO-X — Migration 0009
-- Fix: get_exames_por_local — contrato de colunas correto
-- Data: 2026-04-19
--
-- Problema identificado:
--   1. Overload v1 (1 param) usa a.nome_unidade_executante — coluna que não
--      existe no schema real de appointments. Função inutilizável.
--   2. Overload v2 (2 params) retorna {nome, total} — contrato divergente de
--      tudo que os callers esperam:
--        • useDashboardCharts → espera {equipamento_nome, unidade_nome, realizados, faltas, taxa_absenteismo}
--        • DashboardPage       → normaliza com r.nome ?? r.equipamento_nome (funciona por acidente)
--        • AssistenteIAPage    → lê e.equipamento_nome/e.realizados etc → undefined/NaN → narrador
--                                recebe zeros → responde "não consegui identificar dados" mesmo
--                                com 286 registros status='realizado' no banco!
--
-- Fix:
--   DROP overload v1 (obsoleto, coluna inexistente).
--   CREATE OR REPLACE v2 com contrato canônico:
--     {equipamento_nome, unidade_nome, realizados, total_agendado, faltas, taxa_absenteismo}
--   Padrão LEFT JOIN (mesmo que fn_ocupacao_passada): todos os equipamentos ativos
--   aparecem mesmo com 0 exames no período — graceful para o narrador dizer "sem movimento".
--   Cálculo de taxa_absenteismo alinhado com calcular_absenteismo:
--     denominador = realizados + faltou (total_finalizados), não total_agendado.
--
-- Dados reais no banco no momento desta migration:
--   status='realizado' → 286 registros (2026-03-16 a 2026-04-12)
--   status='faltou'    → 135 registros (mesma janela)
--
-- Aplicar em: Supabase > SQL Editor
-- ============================================================


-- ── STEP 1: Drop AMBOS os overloads ──────────────────────────────────────────
-- v1 (integer): usa a.nome_unidade_executante — coluna inexistente.
-- v2 (integer, text): retorna {nome, total} — contrato incorreto.
-- CREATE OR REPLACE não pode mudar a lista de colunas retornadas (PG ERROR 42P13).
-- É necessário DROP explícito antes de recriar com novo contrato.

DROP FUNCTION IF EXISTS public.get_exames_por_local(integer);
DROP FUNCTION IF EXISTS public.get_exames_por_local(integer, text);


-- ── STEP 2: Reescrever get_exames_por_local(int, text) ────────────────────────
-- Contrato canônico: {equipamento_nome, unidade_nome, realizados, total_agendado, faltas, taxa_absenteismo}
-- Padrão: LEFT JOIN equipment→ubs, filter por janela passada (<=now()), sort por realizados DESC.
-- Compatible backward: DashboardPage normaliza r.nome??r.equipamento_nome → cai em equipamento_nome. ✅

CREATE OR REPLACE FUNCTION public.get_exames_por_local(
  p_horizonte_dias   int  DEFAULT 30,
  p_tipo_atendimento text DEFAULT NULL
)
RETURNS TABLE (
  equipamento_nome  text,
  unidade_nome      text,
  realizados        bigint,
  total_agendado    bigint,
  faltas            bigint,
  taxa_absenteismo  numeric
)
LANGUAGE sql STABLE
AS $$
  SELECT
    eq.nome                                                                         AS equipamento_nome,
    u.nome                                                                          AS unidade_nome,

    -- Exames efetivamente realizados (paciente compareceu)
    count(a.id) FILTER (WHERE a.status = 'realizado')                              AS realizados,

    -- Total na janela excluindo cancelamentos (base para % de ocupação)
    count(a.id) FILTER (WHERE a.status != 'cancelado')                             AS total_agendado,

    -- Ausências registradas
    count(a.id) FILTER (WHERE a.status = 'faltou')                                 AS faltas,

    -- Taxa de absenteísmo: faltas / finalizados (realizado + faltou)
    -- Denominador = total_finalizados, alinhado com calcular_absenteismo().
    CASE
      WHEN count(a.id) FILTER (WHERE a.status IN ('realizado', 'faltou')) = 0
        THEN 0::numeric
      ELSE round(
        count(a.id) FILTER (WHERE a.status = 'faltou')::numeric
        / count(a.id) FILTER (WHERE a.status IN ('realizado', 'faltou'))::numeric
        * 100,
        1
      )
    END                                                                             AS taxa_absenteismo

  FROM equipment eq
  JOIN ubs u ON u.id = eq.ubs_id

  -- LEFT JOIN: equipamentos sem agendamentos no período aparecem com zeros.
  -- Isso permite ao narrador identificar "equipamentos sem movimento" sem omiti-los.
  LEFT JOIN appointments a ON a.equipment_id = eq.id
    AND a.scheduled_at >= now() - (p_horizonte_dias || ' days')::interval
    AND a.scheduled_at <= now()
    AND (
      p_tipo_atendimento IS NULL
      OR EXISTS (
        SELECT 1 FROM queue_entries qe
        WHERE qe.id = a.queue_entry_id
          AND qe.tipo_atendimento::text = p_tipo_atendimento
      )
    )

  WHERE eq.status = 'ativo'
  GROUP BY eq.id, eq.nome, u.id, u.nome
  ORDER BY realizados DESC;
$$;

COMMENT ON FUNCTION public.get_exames_por_local(int, text) IS
  'Volume de exames realizados por equipamento no período retroativo. '
  'Contrato: {equipamento_nome, unidade_nome, realizados, total_agendado, faltas, taxa_absenteismo}. '
  'LEFT JOIN: todos os equipamentos status=ativo retornados, mesmo com realizados=0. '
  'taxa_absenteismo = faltas / (realizados + faltou) × 100 — alinhado com calcular_absenteismo(). '
  'Usado por: useDashboardCharts (por_local), DashboardPage (gráfico), AssistenteIA (intent exames_por_local).';


-- ── VALIDAÇÃO ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_overloads int;
  v_rows      int;
  v_total     bigint;
BEGIN

  -- Confirma que existe exatamente 1 overload após o DROP
  SELECT count(*) INTO v_overloads
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE p.proname = 'get_exames_por_local'
    AND n.nspname = 'public';

  IF v_overloads != 1 THEN
    RAISE WARNING 'get_exames_por_local: % overload(s) — esperado exatamente 1', v_overloads;
  ELSE
    RAISE NOTICE '✅ get_exames_por_local: 1 overload (v1 obsoleto removido com sucesso)';
  END IF;

  -- Testa com janela de 90 dias — deve retornar ao menos 1 equipamento
  SELECT count(*), sum(realizados)
  INTO v_rows, v_total
  FROM get_exames_por_local(90, NULL);

  IF v_rows = 0 THEN
    RAISE WARNING 'get_exames_por_local(90) retornou 0 equipamentos — verifique equipment.status = ''ativo''';
  ELSE
    RAISE NOTICE '✅ get_exames_por_local(90) OK — % equipamentos, % realizados no período', v_rows, coalesce(v_total, 0);
  END IF;

END $$;
