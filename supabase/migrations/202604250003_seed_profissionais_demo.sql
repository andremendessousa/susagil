-- ============================================================
-- SUS RAIO-X — Migration 202604250003
-- Seed Demo: Profissionais — Boards 2 (Aguardando) + 3 (Confirmado/Indisponível)
-- Identificador rastreável: data_source = 'seed_profissionais_demo'
-- Rollback: DELETE FROM professional_confirmations WHERE data_source = 'seed_profissionais_demo'
--   OU executar 202604250002_rollback_profissionais.sql para rollback total
-- Pré-requisito: 202604250001 aplicado (tabelas profissionais + professional_confirmations)
-- ============================================================

BEGIN;

-- ── Idempotente: limpa seed anterior ─────────────────────────────────────────
DELETE FROM professional_confirmations WHERE data_source = 'seed_profissionais_demo';

-- ── Vincula equipment ao profissional correto (profissional_nome) ─────────────
-- Só atualiza se ainda NULL (não sobrescreve dados reais de produção)
UPDATE equipment SET profissional_nome = 'Dr. Carlos Silva'
  WHERE nome ILIKE 'RX-01 — Aroldo%' AND profissional_nome IS NULL;

UPDATE equipment SET profissional_nome = 'Dra. Fernanda Oliveira'
  WHERE nome ILIKE 'US-01 — Aroldo%' AND profissional_nome IS NULL;

UPDATE equipment SET profissional_nome = 'Dr. Carlos Silva'
  WHERE nome ILIKE 'RX-02 — Aroldo%' AND profissional_nome IS NULL;

UPDATE equipment SET profissional_nome = 'Téc. Radiologia Martinez'
  WHERE nome ILIKE '%-01 — ImageMed' AND profissional_nome IS NULL;

UPDATE equipment SET profissional_nome = 'Téc. Radiologia Pereira'
  WHERE nome ILIKE 'RX-01 — OrthoMed' AND profissional_nome IS NULL;

-- ── Seed principal ────────────────────────────────────────────────────────────
DO $$
DECLARE
  -- Profissionais (chave: telefone do seed 202604250001)
  v_p01 uuid; v_t01 text;  -- Dr. Carlos Silva
  v_p02 uuid; v_t02 text;  -- Dra. Fernanda Oliveira
  v_p03 uuid; v_t03 text;  -- Dra. Lúcia Santos
  v_p04 uuid; v_t04 text;  -- Téc. Radiologia Martinez
  v_p05 uuid; v_t05 text;  -- Téc. Radiologia Pereira
  v_p06 uuid; v_t06 text;  -- ImageMed Clínica
  v_p07 uuid; v_t07 text;  -- Ambulatório de Especialidades

  -- 8 appointments futuros (distintos via OFFSET)
  v_a01 uuid; v_a02 uuid; v_a03 uuid; v_a04 uuid;
  v_a05 uuid; v_a06 uuid; v_a07 uuid; v_a08 uuid;
BEGIN
  -- ── Buscar profissionais ──────────────────────────────────────────────
  SELECT id, COALESCE(telefone,'') INTO v_p01, v_t01 FROM profissionais WHERE telefone = '(38) 99801-0001';
  SELECT id, COALESCE(telefone,'') INTO v_p02, v_t02 FROM profissionais WHERE telefone = '(38) 99801-0002';
  SELECT id, COALESCE(telefone,'') INTO v_p03, v_t03 FROM profissionais WHERE telefone = '(38) 99801-0003';
  SELECT id, COALESCE(telefone,'') INTO v_p04, v_t04 FROM profissionais WHERE telefone = '(38) 99801-0004';
  SELECT id, COALESCE(telefone,'') INTO v_p05, v_t05 FROM profissionais WHERE telefone = '(38) 99801-0005';
  SELECT id, COALESCE(telefone,'') INTO v_p06, v_t06 FROM profissionais WHERE telefone = '(38) 99801-0006';
  SELECT id, COALESCE(telefone,'') INTO v_p07, v_t07 FROM profissionais WHERE telefone = '(38) 99801-0007';

  IF v_p01 IS NULL THEN
    RAISE EXCEPTION 'Profissionais não encontrados. Execute 202604250001 primeiro.';
  END IF;

  -- ── 8 appointments futuros distintos (por offset sobre scheduled_at) ─────
  SELECT id INTO v_a01 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 0;
  SELECT id INTO v_a02 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 1;
  SELECT id INTO v_a03 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 2;
  SELECT id INTO v_a04 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 3;
  SELECT id INTO v_a05 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 4;
  SELECT id INTO v_a06 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 5;
  SELECT id INTO v_a07 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 6;
  SELECT id INTO v_a08 FROM appointments WHERE status = 'agendado' AND scheduled_at > NOW() ORDER BY scheduled_at LIMIT 1 OFFSET 7;

  IF v_a01 IS NULL THEN
    RAISE EXCEPTION 'Nenhum appointment agendado futuro encontrado. Verifique seeds de agendamentos.';
  END IF;

  -- ── BOARD 2: Aguardando resposta (3 entradas) ─────────────────────────────
  -- Board 2 = status_resposta IS NULL → solicitação enviada, sem retorno ainda

  IF v_a01 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino, enviado_at, data_source)
    VALUES (
      v_p01, v_a01, 'lembrete_manual',
      '[Sistema de Regulação — Saúde Montes Claros]' || chr(10) || chr(10) ||
      'Prezado(a) *Dr. Carlos Silva*,' || chr(10) ||
      chr(10) || 'Sua agenda de *Ortopedia* está confirmada no *Hospital Aroldo Tourinho*.' || chr(10) ||
      'Por favor, confirme sua disponibilidade:' || chr(10) || chr(10) ||
      '✅ *[1 — CONFIRMO]* disponibilidade' || chr(10) ||
      '⚠️ *[2 — REPORTAR IMPEDIMENTO]*' || chr(10) || chr(10) ||
      '_Secretaria Municipal de Saúde — Montes Claros/MG_',
      v_t01, NOW() - INTERVAL '3 hours', 'seed_profissionais_demo'
    );
  END IF;

  IF v_a02 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino, enviado_at, data_source)
    VALUES (
      v_p02, v_a02, 'lembrete_manual',
      '[Sistema de Regulação — Saúde Montes Claros]' || chr(10) || chr(10) ||
      'Prezada *Dra. Fernanda Oliveira*,' || chr(10) ||
      chr(10) || 'Sua agenda de *Cardiologia* aguarda confirmação de disponibilidade.' || chr(10) ||
      chr(10) || '✅ *[1 — CONFIRMO]* disponibilidade' || chr(10) ||
      '⚠️ *[2 — REPORTAR IMPEDIMENTO]*' || chr(10) || chr(10) ||
      '_Secretaria Municipal de Saúde — Montes Claros/MG_',
      v_t02, NOW() - INTERVAL '1 hour', 'seed_profissionais_demo'
    );
  END IF;

  IF v_a03 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino, enviado_at, data_source)
    VALUES (
      v_p04, v_a03, 'lembrete_manual',
      '[Sistema de Regulação — Saúde Montes Claros]' || chr(10) || chr(10) ||
      'Prezado(a) *Téc. Radiologia Martinez*,' || chr(10) ||
      chr(10) || 'Sua agenda de *Radiologia* na *ImageMed* aguarda confirmação.' || chr(10) ||
      chr(10) || '✅ *[1 — CONFIRMO]* disponibilidade' || chr(10) ||
      '⚠️ *[2 — REPORTAR IMPEDIMENTO]*' || chr(10) || chr(10) ||
      '_Secretaria Municipal de Saúde — Montes Claros/MG_',
      v_t04, NOW() - INTERVAL '5 hours', 'seed_profissionais_demo'
    );
  END IF;

  -- ── BOARD 3: Confirmados — disponível (verde, 3 entradas) ─────────────────
  IF v_a04 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino,
       status_resposta, enviado_at, respondido_at, data_source)
    VALUES (
      v_p05, v_a04, 'lembrete_manual', '[Sistema de Regulação] Confirmação de agenda.', v_t05,
      'confirmou_disponibilidade',
      NOW() - INTERVAL '12 hours', NOW() - INTERVAL '10 hours',
      'seed_profissionais_demo'
    );
  END IF;

  IF v_a05 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino,
       status_resposta, enviado_at, respondido_at, data_source)
    VALUES (
      v_p06, v_a05, 'lembrete_manual', '[Sistema de Regulação] Confirmação de agenda.', v_t06,
      'confirmou_disponibilidade',
      NOW() - INTERVAL '23 hours', NOW() - INTERVAL '22 hours',
      'seed_profissionais_demo'
    );
  END IF;

  IF v_a06 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino,
       status_resposta, enviado_at, respondido_at, data_source)
    VALUES (
      v_p03, v_a06, 'lembrete_manual', '[Sistema de Regulação] Confirmação de agenda.', v_t03,
      'confirmou_disponibilidade',
      NOW() - INTERVAL '5 hours', NOW() - INTERVAL '4 hours',
      'seed_profissionais_demo'
    );
  END IF;

  -- ── BOARD 3: Indisponíveis — vermelho (2 entradas) ────────────────────────
  IF v_a07 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino,
       status_resposta, motivo_indisponibilidade, enviado_at, respondido_at, data_source)
    VALUES (
      v_p02, v_a07, 'lembrete_manual', '[Sistema de Regulação] Confirmação de agenda.', v_t02,
      'reportou_indisponibilidade', 'Equipamento em manutenção',
      NOW() - INTERVAL '8 hours', NOW() - INTERVAL '7 hours',
      'seed_profissionais_demo'
    );
  END IF;

  IF v_a08 IS NOT NULL THEN
    INSERT INTO professional_confirmations
      (profissional_id, appointment_id, tipo, mensagem, telefone_destino,
       status_resposta, motivo_indisponibilidade, enviado_at, respondido_at, data_source)
    VALUES (
      v_p07, v_a08, 'lembrete_manual', '[Sistema de Regulação] Confirmação de agenda.', v_t07,
      'reportou_indisponibilidade', 'Ausência do profissional',
      NOW() - INTERVAL '16 hours', NOW() - INTERVAL '15 hours',
      'seed_profissionais_demo'
    );
  END IF;

  RAISE NOTICE '✅ seed_profissionais_demo: confirmações inseridas com sucesso';
END $$;

-- ── Verificação consolidada ───────────────────────────────────────────────────
SELECT
  COALESCE(status_resposta, 'aguardando_resposta') AS board,
  COUNT(*) AS total
FROM professional_confirmations
WHERE data_source = 'seed_profissionais_demo'
GROUP BY status_resposta
ORDER BY status_resposta NULLS FIRST;

COMMIT;
