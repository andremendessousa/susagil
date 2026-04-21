-- ============================================================
-- SUS RAIO-X — ROLLBACK do Seed Final Demo
-- ============================================================
-- PROPÓSITO: Reverter COMPLETAMENTE os seeds 202604240002-005.
-- SEGURO: Preserva integralmente o seed base (data_source = 'seed_demo').
--
-- IDENTIFICADOR RASTREÁVEL: data_source = 'seed_final_demo'
-- Todos os rows inseridos pelos seeds 2-5 têm esse valor.
--
-- ORDEM de execução: notification_log → appointments → queue_entries
-- (respeita FKs)
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_notif  int;
  v_apts   int;
  v_qes    int;
BEGIN
  -- 1. notification_log referenciando appointments do seed final
  DELETE FROM notification_log
  WHERE appointment_id IN (
    SELECT id FROM appointments WHERE data_source = 'seed_final_demo'
  );
  GET DIAGNOSTICS v_notif = ROW_COUNT;

  -- 2. appointments do seed final
  DELETE FROM appointments WHERE data_source = 'seed_final_demo';
  GET DIAGNOSTICS v_apts = ROW_COUNT;

  -- 3. queue_entries do seed final
  DELETE FROM queue_entries WHERE data_source = 'seed_final_demo';
  GET DIAGNOSTICS v_qes = ROW_COUNT;

  RAISE NOTICE '=== ROLLBACK SEED_FINAL_DEMO CONCLUÍDO ===';
  RAISE NOTICE 'notification_log removidos: %', v_notif;
  RAISE NOTICE 'appointments removidos: %',    v_apts;
  RAISE NOTICE 'queue_entries removidos: %',   v_qes;
END $$;

-- Verificação pós-rollback
DO $$
DECLARE
  v_apts_base int;
  v_qes_base  int;
BEGIN
  SELECT COUNT(*) INTO v_apts_base
  FROM appointments WHERE data_source = 'seed_demo';

  SELECT COUNT(*) INTO v_qes_base
  FROM queue_entries WHERE data_source = 'seed_demo';

  RAISE NOTICE 'appointments seed_demo restantes: %', v_apts_base;
  RAISE NOTICE 'queue_entries seed_demo restantes: %', v_qes_base;

  IF EXISTS (SELECT 1 FROM appointments WHERE data_source = 'seed_final_demo') THEN
    RAISE EXCEPTION 'ROLLBACK INCOMPLETO: ainda existem appointments seed_final_demo!';
  END IF;
  RAISE NOTICE 'Rollback verificado com sucesso.';
END $$;

COMMIT;
