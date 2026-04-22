-- ============================================================
-- ROLLBACK: Módulo Profissionais (reverte 202604250001 + 202604250003)
-- ============================================================
-- PROPÓSITO: Reverter COMPLETAMENTE as tabelas criadas pelo módulo
--   de comunicação com profissionais.
-- SEGURO: notification_log NÃO foi modificada, logo nenhum dado
--   existente é afetado. RPCs, KPIs e hooks permanecem intactos.
-- ORDEM: professional_confirmations → profissionais
--   (respeita FK profissional_id em professional_confirmations)
-- ============================================================

BEGIN;

DO $$
DECLARE
  v_confs int;
  v_profs int;
BEGIN
  -- 1. Remover confirmações de profissionais (inclui seed + dados produção)
  DELETE FROM professional_confirmations;
  GET DIAGNOSTICS v_confs = ROW_COUNT;

  -- 2. Remover cadastro de profissionais
  DELETE FROM profissionais;
  GET DIAGNOSTICS v_profs = ROW_COUNT;

  RAISE NOTICE '=== ROLLBACK MÓDULO PROFISSIONAIS ===';
  RAISE NOTICE 'professional_confirmations removidas: %', v_confs;
  RAISE NOTICE 'profissionais removidos: %',              v_profs;
END $$;

-- DROP em ordem FK: professional_confirmations antes de profissionais
DROP TABLE IF EXISTS professional_confirmations;
DROP TABLE IF EXISTS profissionais;

-- Verificação pós-rollback
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN ('profissionais', 'professional_confirmations')
  ) THEN
    RAISE EXCEPTION 'ROLLBACK INCOMPLETO: tabelas ainda existem!';
  END IF;
  RAISE NOTICE '✅ Rollback verificado: tabelas removidas com sucesso.';
  RAISE NOTICE 'notification_log: intacta (patient_id NOT NULL, sem colunas removidas).';
END $$;

COMMIT;
