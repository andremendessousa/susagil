-- ============================================================
-- SUS RAIO-X — Reset + Seed Controlado para Demo GovTech
-- 202604170002_reset_demo_seed_controlado.sql
--
-- Execute no Supabase SQL Editor em 3 blocos independentes:
--
--   BLOCO A → Diagnóstico: mostra estado atual dos appointments
--   BLOCO B → Reset: limpa estado dos testes anteriores
--   BLOCO C → Seed FIFO: cria fila de espera auditável para demo
--
-- BLOCO B resolve o problema imediato (lista vazia).
-- BLOCO C cria os candidatos FIFO rotulados para a demo em vídeo.
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  BLOCO A — DIAGNÓSTICO (rode primeiro, não modifica nada)
-- ════════════════════════════════════════════════════════════

SELECT
  p.nome,
  a.status,
  a.st_paciente_avisado,
  a.scheduled_at,
  e.nome AS equipamento,
  a.reaproveitado_de_id IS NOT NULL AS criado_por_rpc
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
JOIN patients      p  ON p.id  = qe.patient_id
LEFT JOIN equipment e ON e.id  = a.equipment_id
WHERE a.scheduled_at > now()
ORDER BY a.scheduled_at;

-- Esperado: linha por appointment futuro com seu status atual.
-- Se todos tiverem st_paciente_avisado=1 ou status<>'agendado',
-- a lista "Vagas sem confirmação" fica vazia — é exatamente esse o bug.


-- ════════════════════════════════════════════════════════════
--  BLOCO B — RESET DE ESTADO (executa o reset)
-- ════════════════════════════════════════════════════════════

BEGIN;

-- 1. Remove notifications de teste que não tiveram resposta
--    (inseridas manualmente durante desenvolvimento/testes)
DELETE FROM notification_log
WHERE data_source = 'manual'
  AND resposta_paciente IS NULL;

-- 2. Remove appointments criados pelo RPC de reaproveitamento
--    durante os testes (têm reaproveitado_de_id preenchido).
--    Esses são "órfãos" de teste — não representam fluxo real.
DELETE FROM appointments
WHERE reaproveitado_de_id IS NOT NULL
  AND scheduled_at > now();

-- 3. Retorna queue_entries reaproveitadas de volta para 'aguardando'
--    (o RPC as promoveu para 'agendado', mas apagamos o appointment acima)
UPDATE queue_entries
SET status_local = 'aguardando'
WHERE status_local = 'agendado'
  AND id NOT IN (
    SELECT queue_entry_id FROM appointments WHERE queue_entry_id IS NOT NULL
  );

-- 4. Resetar status dos appointments confirmedos/cancelados via simulação
--    para que apareçam novamente em "Vagas sem confirmação"
UPDATE appointments
SET
  status             = 'agendado',
  st_paciente_avisado = NULL
WHERE scheduled_at > now()
  AND status IN ('confirmado', 'cancelado');

-- Sincroniza queue_entries que foram marcadas como 'cancelado' pelo RPC
-- de volta para 'agendado' (têm appointment ativo)
UPDATE queue_entries qe
SET status_local = 'agendado'
WHERE qe.status_local = 'cancelado'
  AND EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.queue_entry_id = qe.id
      AND a.status = 'agendado'
      AND a.scheduled_at > now()
  );

-- 5. Zera st_paciente_avisado em todos os appointments futuros
--    (durante os testes, o fix de bulk-mark marcou todos)
UPDATE appointments
SET st_paciente_avisado = NULL
WHERE scheduled_at > now()
  AND status = 'agendado'
  AND st_paciente_avisado IS NOT NULL;

COMMIT;

-- Verificação rápida após o BLOCO B:
SELECT COUNT(*) AS vagas_para_notificar
FROM appointments
WHERE status = 'agendado'
  AND st_paciente_avisado IS NULL
  AND scheduled_at > now()
  AND scheduled_at <= now() + INTERVAL '48 hours';
-- Esperado: número > 0


-- ════════════════════════════════════════════════════════════
--  BLOCO C — SEED FIFO AUDITÁVEL (para demo em vídeo)
--
--  Cria fila de espera rotulada usando PACIENTES EXISTENTES
--  do banco. Não cria pacientes novos (evita problemas com
--  colunas NOT NULL desconhecidas).
--
--  Estratégia FIFO para demo:
--    [FIFO-01] prioridade 1, mais antigo → 1º a ser convocado
--    [FIFO-02] prioridade 2, mais antigo → 2º
--    [FIFO-03] prioridade 2, mais recente → 3º
--
--  O nome do paciente convocado aparecerá no toast do WhatsApp
--  quando alguém cancelar — isso prova o funcionamento do RPC.
-- ════════════════════════════════════════════════════════════

BEGIN;

-- Remove seeds FIFO de execuções anteriores (idempotente)
DELETE FROM queue_entries
WHERE data_source = 'seed_demo'
  AND status_local = 'aguardando';

DO $$
DECLARE
  v_ubs_id        uuid;
  v_proc          text;

  -- 3 pacientes distintos do banco que NÃO têm appointment futuro 'agendado'
  -- (evita conflito com a lista de "Vagas sem confirmação")
  p_fifo1         uuid;
  p_fifo2         uuid;
  p_fifo3         uuid;
BEGIN

  -- UBS de referência: mesma UBS dos appointments existentes
  SELECT qe.ubs_id INTO v_ubs_id
  FROM appointments a
  JOIN queue_entries qe ON qe.id = a.queue_entry_id
  WHERE a.status = 'agendado'
    AND a.scheduled_at > now()
  LIMIT 1;

  IF v_ubs_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum appointment futuro encontrado. Execute o BLOCO B primeiro.';
  END IF;

  -- Procedimento mais comum nos appointments futuros
  SELECT qe.nome_grupo_procedimento INTO v_proc
  FROM appointments a
  JOIN queue_entries qe ON qe.id = a.queue_entry_id
  WHERE a.status = 'agendado'
    AND a.scheduled_at > now()
    AND qe.ubs_id = v_ubs_id
    AND qe.nome_grupo_procedimento IS NOT NULL
  GROUP BY qe.nome_grupo_procedimento
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- 3 pacientes sem appointment futuro ativo (candidatos FIFO)
  SELECT id INTO p_fifo1
  FROM patients
  WHERE id NOT IN (
    SELECT qe.patient_id FROM queue_entries qe
    JOIN appointments a ON a.queue_entry_id = qe.id
    WHERE a.status = 'agendado' AND a.scheduled_at > now()
  )
  ORDER BY nome
  LIMIT 1;

  SELECT id INTO p_fifo2
  FROM patients
  WHERE id NOT IN (
    SELECT qe.patient_id FROM queue_entries qe
    JOIN appointments a ON a.queue_entry_id = qe.id
    WHERE a.status = 'agendado' AND a.scheduled_at > now()
  )
    AND id != p_fifo1
  ORDER BY nome
  LIMIT 1;

  SELECT id INTO p_fifo3
  FROM patients
  WHERE id NOT IN (
    SELECT qe.patient_id FROM queue_entries qe
    JOIN appointments a ON a.queue_entry_id = qe.id
    WHERE a.status = 'agendado' AND a.scheduled_at > now()
  )
    AND id NOT IN (p_fifo1, p_fifo2)
  ORDER BY nome
  LIMIT 1;

  IF p_fifo1 IS NULL OR p_fifo2 IS NULL OR p_fifo3 IS NULL THEN
    RAISE EXCEPTION 'Não há pacientes suficientes sem appointment futuro. Verifique os dados.';
  END IF;

  -- Cria fila de espera rotulada
  -- FIFO-01: urgente (prioridade 1) + mais antigo → PRIMEIRO convocado
  -- Cria fila de espera rotulada
  -- tipo_atendimento é enum USER-DEFINED — não aceita literal text; puxar do banco via SELECT
  -- FIFO-01: urgente (prioridade 1) + mais antigo → PRIMEIRO convocado
  INSERT INTO queue_entries (
    patient_id, ubs_id, tipo_atendimento, nome_grupo_procedimento,
    status_local, prioridade_codigo, data_solicitacao_sisreg, data_source
  )
  SELECT p_fifo1, v_ubs_id, qe.tipo_atendimento, v_proc,
    'aguardando', 1, now() - INTERVAL '10 days', 'seed_demo'
  FROM appointments a
  JOIN queue_entries qe ON qe.id = a.queue_entry_id
  WHERE a.status = 'agendado' AND a.scheduled_at > now() AND qe.ubs_id = v_ubs_id
  LIMIT 1;

  -- FIFO-02: rotina (prioridade 2) + mais antigo → SEGUNDO convocado
  INSERT INTO queue_entries (
    patient_id, ubs_id, tipo_atendimento, nome_grupo_procedimento,
    status_local, prioridade_codigo, data_solicitacao_sisreg, data_source
  )
  SELECT p_fifo2, v_ubs_id, qe.tipo_atendimento, v_proc,
    'aguardando', 2, now() - INTERVAL '8 days', 'seed_demo'
  FROM appointments a
  JOIN queue_entries qe ON qe.id = a.queue_entry_id
  WHERE a.status = 'agendado' AND a.scheduled_at > now() AND qe.ubs_id = v_ubs_id
  LIMIT 1;

  -- FIFO-03: rotina (prioridade 2) + mais recente → TERCEIRO convocado
  INSERT INTO queue_entries (
    patient_id, ubs_id, tipo_atendimento, nome_grupo_procedimento,
    status_local, prioridade_codigo, data_solicitacao_sisreg, data_source
  )
  SELECT p_fifo3, v_ubs_id, qe.tipo_atendimento, v_proc,
    'aguardando', 2, now() - INTERVAL '6 days', 'seed_demo'
  FROM appointments a
  JOIN queue_entries qe ON qe.id = a.queue_entry_id
  WHERE a.status = 'agendado' AND a.scheduled_at > now() AND qe.ubs_id = v_ubs_id
  LIMIT 1;
  RAISE NOTICE 'Seed FIFO criado com sucesso. UBS: %, Proc: %', v_ubs_id, v_proc;
END $$;

COMMIT;

-- ── VERIFICAÇÃO FINAL ─────────────────────────────────────────────────────────
-- Rode após o BLOCO C para confirmar a ordem exata de convocação:

SELECT
  p.nome                              AS paciente,
  qe.prioridade_codigo                AS prioridade,
  qe.data_solicitacao_sisreg::date    AS solicitado_em,
  qe.nome_grupo_procedimento          AS procedimento,
  qe.status_local,
  CASE qe.prioridade_codigo
    WHEN 1 THEN '⚡ URGENTE — 1º a ser convocado'
    ELSE        '📋 ROTINA  — ordem por data'
  END AS ordem_demo
FROM queue_entries qe
JOIN patients p ON p.id = qe.patient_id
WHERE qe.status_local = 'aguardando'
  AND qe.data_source = 'seed_demo'
ORDER BY qe.prioridade_codigo ASC, qe.data_solicitacao_sisreg ASC;

-- Esta query mostra EXATAMENTE a ordem em que os pacientes
-- serão convocados pelo RPC quando alguém cancelar.
-- Use para narrar o demo: "se este paciente cancelar, o próximo
-- será [nome do FIFO-01]..."
