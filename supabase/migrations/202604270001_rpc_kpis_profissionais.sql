-- ============================================================
-- SUS RAIO-X — Migration 202604270001
-- RPC: rpc_kpis_profissionais
-- KPIs de BI para GestaoFilaProfissionaisPage
-- Data: 2026-04-22
-- ============================================================
--
-- OBJETIVO:
--   Prover 3 indicadores de alto valor para o dashboard de
--   Gestão de Agenda de Profissionais, calculados no banco para
--   garantir consistência e evitar duplicação de lógica no frontend.
--
-- KPI 1 — Agendas confirmadas (%)
--   Percentual de equipamentos/setores que já confirmaram
--   disponibilidade nas próximas p_horizonte_horas (default 72h).
--   Denominador: equipamentos distintos com agendamentos 'agendado'
--                na janela prospectiva.
--   Numerador:   desses, quantos têm ao menos 1 confirmação
--                confirmou_disponibilidade vinculada ao appointment.
--   Retorna: agendas_confirmadas_pct, equip_confirmaram, equip_com_agenda
--
-- KPI 2 — Indisponibilidades reportadas (contagem)
--   Total de professional_confirmations com
--   status_resposta = 'reportou_indisponibilidade'
--   nos últimos 30 dias.
--   Retorna: indisponibilidades_count
--
-- KPI 3 — Pacientes protegidos (contagem)
--   Número de appointments em status 'aguardando'/'agendado'/'confirmado'
--   cujo equipment+dia coincide com algum slot onde houve
--   indisponibilidade reportada.
--   Lógica: cada appointment = 1 deslocamento potencialmente evitado.
--   Retorna: pacientes_protegidos
--
-- SEGURANÇA:
--   SECURITY DEFINER + SET search_path = public → protege contra
--   search_path injection (OWASP A01).
--   STABLE → permite cache pelo query planner.
--   Sem escrita em tabelas → zero risco de efeitos colaterais.
--
-- ROLLBACK:
--   DROP FUNCTION IF EXISTS public.rpc_kpis_profissionais(integer);
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_kpis_profissionais(
  p_horizonte_horas integer DEFAULT 72
)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
WITH
  -- ── Janela prospectiva [now, now + p_horizonte_horas] ────────────────────────
  params AS (
    SELECT
      now()                                                         AS t_inicio,
      now() + (p_horizonte_horas || ' hours')::interval            AS t_limite
  ),

  -- ── KPI 1 — Denominador ─────────────────────────────────────────────────────
  -- Equipamentos/setores distintos com agendamentos ativos na janela prospectiva.
  -- Cada equipment = 1 profissional/clínica responsável.
  equip_com_agenda AS (
    SELECT DISTINCT a.equipment_id
    FROM appointments a
    CROSS JOIN params
    WHERE a.status = 'agendado'
      AND a.scheduled_at BETWEEN params.t_inicio AND params.t_limite
  ),

  -- ── KPI 1 — Numerador ───────────────────────────────────────────────────────
  -- Equipamentos que já têm ao menos 1 confirmação de disponibilidade
  -- com appointment dentro da mesma janela prospectiva.
  equip_confirmou AS (
    SELECT DISTINCT ref.equipment_id
    FROM professional_confirmations pc
    JOIN appointments ref ON ref.id = pc.appointment_id
    CROSS JOIN params
    WHERE pc.status_resposta = 'confirmou_disponibilidade'
      AND ref.scheduled_at   BETWEEN params.t_inicio AND params.t_limite
  ),

  -- ── KPI 2 — Indisponibilidades reportadas ───────────────────────────────────
  -- Contagem nos últimos 30 dias (janela operacional padrão).
  indisponibilidades AS (
    SELECT COUNT(*)::integer AS total
    FROM professional_confirmations
    WHERE status_resposta = 'reportou_indisponibilidade'
      AND respondido_at   >= now() - interval '30 days'
  ),

  -- ── KPI 3 — Slots únicos com indisponibilidade (equipment_id + dia) ─────────
  -- De-duplica: múltiplos reenvios para o mesmo slot contam como 1 evento.
  slots_indisponiveis AS (
    SELECT DISTINCT
      ref.equipment_id,
      date(ref.scheduled_at AT TIME ZONE 'UTC') AS slot_day
    FROM professional_confirmations pc
    JOIN appointments ref ON ref.id = pc.appointment_id
    WHERE pc.status_resposta = 'reportou_indisponibilidade'
  ),

  -- ── KPI 3 — Pacientes protegidos ────────────────────────────────────────────
  -- Appointments em status ativo que caem em slots afetados.
  -- Cada appointment = 1 potencial deslocamento evitado pelo aviso preventivo.
  -- Valores válidos do enum status_local: aguardando | agendado | confirmado |
  --                                       realizado  | faltou   | cancelado
  pacientes_protegidos AS (
    SELECT COUNT(*)::integer AS total
    FROM appointments a
    JOIN slots_indisponiveis s
      ON  s.equipment_id = a.equipment_id
      AND s.slot_day     = date(a.scheduled_at AT TIME ZONE 'UTC')
    WHERE a.status IN ('aguardando', 'agendado', 'confirmado')
  )

SELECT json_build_object(
  -- KPI 1
  'agendas_confirmadas_pct',
    CASE
      WHEN (SELECT COUNT(*) FROM equip_com_agenda) > 0
      THEN round(
        (SELECT COUNT(*) FROM equip_confirmou)::numeric
        / (SELECT COUNT(*) FROM equip_com_agenda) * 100,
        1
      )
      ELSE null
    END,
  'equip_confirmaram',        (SELECT COUNT(*) FROM equip_confirmou),
  'equip_com_agenda',         (SELECT COUNT(*) FROM equip_com_agenda),
  -- KPI 2
  'indisponibilidades_count', (SELECT total FROM indisponibilidades),
  -- KPI 3
  'pacientes_protegidos',     (SELECT total FROM pacientes_protegidos)
);
$function$;

COMMENT ON FUNCTION public.rpc_kpis_profissionais(integer) IS
  'KPIs de BI — GestaoFilaProfissionaisPage. '
  'Retorna JSON com: agendas_confirmadas_pct (%), equip_confirmaram, equip_com_agenda, '
  'indisponibilidades_count (últimos 30d), pacientes_protegidos (deslocamentos evitados). '
  'p_horizonte_horas: janela prospectiva para KPI 1 (default 72h).';

-- ══════════════════════════════════════════════════════════════
--  VERIFICAÇÃO PÓS-EXECUÇÃO
-- ══════════════════════════════════════════════════════════════
-- V1 — Função existe e retorna JSON válido
-- SELECT rpc_kpis_profissionais(72)::jsonb;
--
-- V2 — Teste com horizonte 24h
-- SELECT rpc_kpis_profissionais(24)::jsonb;
--
-- Resultado esperado (demo seed):
--   agendas_confirmadas_pct: número ou null (se nenhum confirmou ainda)
--   equip_com_agenda: >0 se há appointments futuros
--   indisponibilidades_count: 0 inicialmente (seed não tem indisponibilidades)
--   pacientes_protegidos: 0 inicialmente (sem slots com indisponibilidade)
