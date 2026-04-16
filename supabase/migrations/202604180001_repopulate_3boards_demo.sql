-- ============================================================
-- SUS RAIO-X — Repopulação para Demo Kanban 3 Boards
-- 202604180001_repopulate_3boards_demo.sql
--
-- Objetivo: popular o banco com pacientes em 3 estados distintos
-- para demonstrar o pipeline Kanban da NotificacoesPage:
--
--   Board 1 → Pendente de Notificação  (≥15 pacientes, sem notification_log)
--   Board 2 → Aguardando Confirmação   (4 pacientes notificados, sem resposta)
--   Board 3 → Histórico               (3 pacientes respondidos: 2 confirmou, 1 cancelou)
--
-- Execute os blocos em sequência no Supabase SQL Editor:
--
--   BLOCO E → Reset: limpa estado de testes anteriores
--   BLOCO F → Reschedule: move 22 appointments para janela de 48h
--   BLOCO G → Board 2: cria notification_log sem resposta (4 pacientes)
--   BLOCO H → Board 3: cria notification_log com resposta (3 pacientes)
--   BLOCO I → Verificação: confirma distribuição nos 3 boards
--
-- Idempotente: pode ser re-executado entre sessões de teste.
-- Seed FIFO (queue_entries data_source='seed_demo') NÃO é afetado.
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  BLOCO E — RESET (mesmo comportamento do BLOCO B anterior)
-- ════════════════════════════════════════════════════════════

BEGIN;

-- Remove notificações manuais de testes sem resposta
DELETE FROM notification_log
WHERE data_source = 'manual';

-- Remove appointments órfãos criados pelo RPC durante testes
DELETE FROM appointments
WHERE reaproveitado_de_id IS NOT NULL
  AND scheduled_at > now();

-- Retorna queue_entries reaproveitadas de volta para 'aguardando'
UPDATE queue_entries
SET status_local = 'aguardando'
WHERE status_local = 'agendado'
  AND id NOT IN (
    SELECT queue_entry_id FROM appointments WHERE queue_entry_id IS NOT NULL
  );

-- Reseta appointments confirmados/cancelados de volta para agendado
UPDATE appointments
SET status = 'agendado', st_paciente_avisado = NULL
WHERE scheduled_at > now()
  AND status IN ('confirmado', 'cancelado');

-- Sincroniza queue_entries canceladas que têm appointment ativo
UPDATE queue_entries qe
SET status_local = 'agendado'
WHERE qe.status_local = 'cancelado'
  AND EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.queue_entry_id = qe.id
      AND a.status = 'agendado'
      AND a.scheduled_at > now()
  );

-- Zera st_paciente_avisado em todos os appointments futuros
UPDATE appointments
SET st_paciente_avisado = NULL
WHERE scheduled_at > now()
  AND status = 'agendado'
  AND st_paciente_avisado IS NOT NULL;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO F — RESCHEDULE
--  Move os primeiros 22 appointments futuros para dentro da
--  janela de 48h, espaçados ~1h entre si (3h a 24h a partir de now).
--  Garante que Board 1 tenha pelo menos 15 pacientes visíveis.
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  r   RECORD;
  idx INT := 0;
BEGIN
  FOR r IN
    SELECT id FROM appointments
    WHERE status = 'agendado'
      AND scheduled_at > now()
    ORDER BY scheduled_at
    LIMIT 22
  LOOP
    idx := idx + 1;
    -- Espaça cada appointment 1h a partir de 3h de agora
    UPDATE appointments
    SET scheduled_at = now()
                     + INTERVAL '3 hours'
                     + (idx::text || ' hours')::INTERVAL
    WHERE id = r.id;
  END LOOP;

  RAISE NOTICE 'Rescheduled % appointments dentro da janela de 48h.', idx;
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO G — BOARD 2: primeiros 4 appointments → notificados
--  Cria notification_log sem resposta (→ aparecem no Board 2)
--  e marca st_paciente_avisado = 1 (→ somem do Board 1)
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  r   RECORD;
  idx INT := 0;
BEGIN
  FOR r IN
    SELECT
      a.id          AS appt_id,
      qe.patient_id AS patient_id,
      p.telefone    AS telefone,
      COALESCE(e.nome, 'Equipamento') AS equip_nome,
      a.scheduled_at
    FROM appointments a
    JOIN queue_entries qe ON qe.id = a.queue_entry_id
    JOIN patients      p  ON p.id  = qe.patient_id
    LEFT JOIN equipment e ON e.id  = a.equipment_id
    WHERE a.status = 'agendado'
      AND a.scheduled_at > now()
      AND (a.st_paciente_avisado IS NULL OR a.st_paciente_avisado = 0)
    ORDER BY a.scheduled_at
    LIMIT 4
  LOOP
    idx := idx + 1;

    INSERT INTO notification_log (
      patient_id, appointment_id, tipo, canal, mensagem,
      telefone_destino, enviado_at, entregue, data_source
    ) VALUES (
      r.patient_id,
      r.appt_id,
      'lembrete_manual',
      'whatsapp',
      'Lembrete: você tem um agendamento em ' || r.equip_nome
        || '. Confirme sua presença respondendo 1.',
      COALESCE(r.telefone, ''),
      -- Notificações enviadas entre 20min e 80min atrás (simula envio escalonado)
      now() - (idx * INTERVAL '20 minutes'),
      false,
      'manual'
    );

    -- Marca como avisado → sai do Board 1, fica no Board 2
    UPDATE appointments
    SET st_paciente_avisado = 1
    WHERE id = r.appt_id;

  END LOOP;

  RAISE NOTICE 'Board 2: % pacientes notificados aguardando resposta.', idx;
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO H — BOARD 3: próximos 3 → notificados COM resposta
--  2 confirmaram presença, 1 cancelou (disparará "Vaga Recuperada").
--  Esses pacientes ficam no Histórico (Board 3).
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  r   RECORD;
  idx INT := 0;
BEGIN
  FOR r IN
    SELECT
      a.id          AS appt_id,
      qe.patient_id AS patient_id,
      p.nome        AS patient_nome,
      p.telefone    AS telefone,
      COALESCE(e.nome, 'Equipamento') AS equip_nome,
      a.scheduled_at
    FROM appointments a
    JOIN queue_entries qe ON qe.id = a.queue_entry_id
    JOIN patients      p  ON p.id  = qe.patient_id
    LEFT JOIN equipment e ON e.id  = a.equipment_id
    WHERE a.status = 'agendado'
      AND a.scheduled_at > now()
      AND (a.st_paciente_avisado IS NULL OR a.st_paciente_avisado = 0)
    ORDER BY a.scheduled_at
    LIMIT 3
  LOOP
    idx := idx + 1;

    IF idx <= 2 THEN
      -- ── CONFIRMOU ──────────────────────────────────────────────────────────
      INSERT INTO notification_log (
        patient_id, appointment_id, tipo, canal, mensagem,
        telefone_destino, enviado_at, respondido_at, resposta_paciente,
        entregue, data_source
      ) VALUES (
        r.patient_id, r.appt_id, 'lembrete_manual', 'whatsapp',
        'Lembrete: você tem um agendamento em ' || r.equip_nome || '. Confirme presença respondendo 1.',
        COALESCE(r.telefone, ''),
        now() - INTERVAL '3 hours',
        now() - INTERVAL '2 hours',
        'confirmou',
        true, 'manual'
      );
      UPDATE appointments
      SET st_paciente_avisado = 1, status = 'confirmado'
      WHERE id = r.appt_id;

    ELSE
      -- ── CANCELOU ───────────────────────────────────────────────────────────
      INSERT INTO notification_log (
        patient_id, appointment_id, tipo, canal, mensagem,
        telefone_destino, enviado_at, respondido_at, resposta_paciente,
        entregue, data_source
      ) VALUES (
        r.patient_id, r.appt_id, 'lembrete_manual', 'whatsapp',
        'Lembrete: você tem um agendamento em ' || r.equip_nome || '. Confirme presença respondendo 1.',
        COALESCE(r.telefone, ''),
        now() - INTERVAL '3 hours',
        now() - INTERVAL '2 hours 30 minutes',
        'cancelou',
        true, 'manual'
      );
      UPDATE appointments
      SET st_paciente_avisado = 1, status = 'cancelado'
      WHERE id = r.appt_id;

      -- Sincroniza status da queue_entry
      UPDATE queue_entries
      SET status_local = 'cancelado'
      WHERE id = (
        SELECT queue_entry_id FROM appointments WHERE id = r.appt_id
      );
    END IF;

  END LOOP;

  RAISE NOTICE 'Board 3: % pacientes com resposta no histórico.', idx;
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO I — VERIFICAÇÃO FINAL
--  Rode após os blocos E-H para confirmar a distribuição.
--  Esperado:
--    Board 1: ≥ 15 pacientes
--    Board 2: 4 pacientes
--    Board 3: 3 notificações respondidas
-- ════════════════════════════════════════════════════════════

SELECT
  'Board 1 — Pendente de Notificação' AS board,
  COUNT(*)                            AS total
FROM appointments a
WHERE a.status = 'agendado'
  AND (a.st_paciente_avisado IS NULL OR a.st_paciente_avisado = 0)
  AND a.scheduled_at > now()
  AND a.scheduled_at <= now() + INTERVAL '48 hours'

UNION ALL

SELECT
  'Board 2 — Aguardando Confirmação',
  COUNT(DISTINCT nl.patient_id)
FROM notification_log nl
JOIN appointments a ON a.id = nl.appointment_id
WHERE nl.resposta_paciente IS NULL
  AND a.scheduled_at > now()

UNION ALL

SELECT
  'Board 3 — Histórico (respondidos)',
  COUNT(*)
FROM notification_log nl
WHERE nl.resposta_paciente IS NOT NULL

ORDER BY board;
