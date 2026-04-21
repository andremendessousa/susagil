-- ============================================================
-- SUS RAIO-X — Migration 202604240007
-- Fix: nome_grupo_procedimento + polo macrorregional aguardando
-- Data: 2026-04-20
-- ============================================================
-- BLOCO A: UPDATE nome_grupo_procedimento nos 312 registros seed_final_demo
--   → Resolve "Procedimentos mais solicitados" vazio (fallback insuficiente)
--   → Seguro: toca APENAS registros data_source='seed_final_demo'
--   → Rollback automático: DELETE FROM queue_entries WHERE data_source='seed_final_demo'
--
-- BLOCO B: INSERT ~24 fila aguardando para UBSs polo (Bocaiúva/Pirapora/Janaúba)
--   → Resolve "Espera e absenteísmo por município" vazio no escopo Macrorregião
--   → Resolve V6 (espera atual abaixo de 80d)
--   → Resolve V9 (Janaúba ausente)
--   → data_source='seed_final_demo' → coberto pelo rollback 202604240001
--
-- ROLLBACK: executar 202604240001_rollback_seed_final.sql
--   (DELETE cadeia: queue_entries/appointments WHERE data_source='seed_final_demo')
--   O UPDATE do BLOCO A é revertido implicitamente pois os REGISTROS são deletados.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
--  BLOCO A — Preencher nome_grupo_procedimento
--  Estratégia: derivar do nome do equipamento usado no appointment
--  vinculado. Cada queue_entry seed_final_demo tem exatamente 1 appointment.
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_rows int;
BEGIN
  UPDATE queue_entries qe
  SET nome_grupo_procedimento = CASE
    WHEN eq.nome LIKE '%RX%'                                    THEN 'Raio-X Convencional'
    WHEN eq.nome LIKE '%US%'                                    THEN 'Ultrassonografia'
    WHEN eq.nome LIKE '%TC%'                                    THEN 'Tomografia Computadorizada'
    WHEN eq.nome LIKE '%RM%'                                    THEN 'Ressonância Magnética'
    WHEN eq.nome LIKE '%Traumatologia%'                         THEN 'Ortopedia e Traumatologia'
    WHEN eq.nome LIKE '%Ortopedia%' OR eq.nome LIKE '%Ortopéd%' THEN 'Consulta de Ortopedia'
    ELSE qe.tipo_atendimento::text
  END
  FROM appointments a
  JOIN equipment eq ON eq.id = a.equipment_id
  WHERE a.queue_entry_id = qe.id
    AND qe.data_source = 'seed_final_demo'
    AND (qe.nome_grupo_procedimento IS NULL
         OR trim(qe.nome_grupo_procedimento) = '');

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RAISE NOTICE 'BLOCO A: nome_grupo_procedimento atualizado em % queue_entries', v_rows;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO B — Inserir fila aguardando para municípios polo
--  8 Bocaiúva (130d) + 8 Pirapora (145d) + 8 Janaúba (150d) = 24 entradas
--  SEM appointments vinculados → são pacientes na fila pura, aguardando vaga
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_ubs_boc  uuid;
  v_ubs_pir  uuid;
  v_ubs_jan  uuid;

  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_n_pat    int;
  v_i        int := 0;
  v_rows     int := 0;
BEGIN
  -- UBSs polo (reguladoras dos municípios satélite)
  SELECT id INTO v_ubs_boc FROM ubs WHERE nome = 'UBS Bocaiúva';
  SELECT id INTO v_ubs_pir FROM ubs WHERE nome = 'UBS Pirapora';
  SELECT id INTO v_ubs_jan FROM ubs WHERE nome = 'UBS Janaúba';

  IF v_ubs_boc IS NULL THEN
    RAISE EXCEPTION 'UBS Bocaiúva não encontrada. Verifique seed 202604210001.';
  END IF;

  -- Herdar tipos enum de registro existente (mesmo padrão dos outros seeds)
  SELECT tipo_atendimento INTO v_ta
  FROM queue_entries
  WHERE tipo_atendimento::text = 'consulta' LIMIT 1;
  IF v_ta IS NULL THEN
    SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  END IF;
  SELECT tipo_vaga      INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  -- Pacientes seed
  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients
  FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  -- ── Bocaiúva: 8 pacientes aguardando, espera 120-140 dias ──────────────
  -- Prioridade variada para mostrar diversidade na narrativa
  FOR v_i IN 1..8 LOOP
    INSERT INTO queue_entries (
      id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco,
      tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente,
      nome_grupo_procedimento,
      data_solicitacao_sisreg, data_source
    ) VALUES (
      gen_random_uuid(),
      v_patients[1 + ((v_i - 1) % v_n_pat)],
      v_ubs_boc,
      'aguardando',
      CASE WHEN v_i % 4 = 0 THEN 1 WHEN v_i % 4 = 1 THEN 2 ELSE 3 END,
      CASE WHEN v_i % 4 = 0 THEN 'vermelho'::prioridade_cor
           WHEN v_i % 4 = 1 THEN 'amarelo'::prioridade_cor
           ELSE 'verde'::prioridade_cor END,
      v_ta, v_tv, v_tr,
      'Bocaiúva', 'MG',
      CASE WHEN v_i % 2 = 0 THEN 'Consulta de Ortopedia'
           ELSE 'Raio-X Convencional' END,
      NOW() - ((120 + (v_i * 2)) || ' days')::interval,
      'seed_final_demo'
    );
  END LOOP;
  v_rows := v_rows + 8;

  -- ── Pirapora: 8 pacientes aguardando, espera 135-155 dias ──────────────
  FOR v_i IN 1..8 LOOP
    INSERT INTO queue_entries (
      id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco,
      tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente,
      nome_grupo_procedimento,
      data_solicitacao_sisreg, data_source
    ) VALUES (
      gen_random_uuid(),
      v_patients[1 + (v_i % v_n_pat)],
      v_ubs_pir,
      'aguardando',
      CASE WHEN v_i % 4 = 0 THEN 1 WHEN v_i % 4 = 1 THEN 2 ELSE 3 END,
      CASE WHEN v_i % 4 = 0 THEN 'vermelho'::prioridade_cor
           WHEN v_i % 4 = 1 THEN 'amarelo'::prioridade_cor
           ELSE 'verde'::prioridade_cor END,
      v_ta, v_tv, v_tr,
      'Pirapora', 'MG',
      CASE WHEN v_i % 2 = 0 THEN 'Consulta de Ortopedia'
           ELSE 'Raio-X Convencional' END,
      NOW() - ((135 + (v_i * 2)) || ' days')::interval,
      'seed_final_demo'
    );
  END LOOP;
  v_rows := v_rows + 8;

  -- ── Janaúba: 8 pacientes aguardando, espera 145-165 dias ───────────────
  FOR v_i IN 1..8 LOOP
    INSERT INTO queue_entries (
      id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco,
      tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente,
      nome_grupo_procedimento,
      data_solicitacao_sisreg, data_source
    ) VALUES (
      gen_random_uuid(),
      v_patients[1 + ((v_i + 2) % v_n_pat)],
      v_ubs_jan,
      'aguardando',
      CASE WHEN v_i % 4 = 0 THEN 1 WHEN v_i % 4 = 1 THEN 2 ELSE 3 END,
      CASE WHEN v_i % 4 = 0 THEN 'vermelho'::prioridade_cor
           WHEN v_i % 4 = 1 THEN 'amarelo'::prioridade_cor
           ELSE 'verde'::prioridade_cor END,
      v_ta, v_tv, v_tr,
      'Janaúba', 'MG',
      CASE WHEN v_i % 2 = 0 THEN 'Consulta de Ortopedia'
           ELSE 'Raio-X Convencional' END,
      NOW() - ((145 + (v_i * 2)) || ' days')::interval,
      'seed_final_demo'
    );
  END LOOP;
  v_rows := v_rows + 8;

  RAISE NOTICE 'BLOCO B: % queue_entries polo inseridas (aguardando)', v_rows;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════
--  VERIFICAÇÕES PÓS-007
-- ════════════════════════════════════════════════════════════

-- VX1 — Conferir nome_grupo_procedimento preenchido
SELECT
  nome_grupo_procedimento,
  COUNT(*) AS qtd
FROM queue_entries
WHERE data_source = 'seed_final_demo'
  AND nome_grupo_procedimento IS NOT NULL
GROUP BY nome_grupo_procedimento
ORDER BY qtd DESC;

-- VX2 — Conferir polo: espera atualizada e municípios presentes
SELECT
  u.nome AS ubs_polo,
  COUNT(*) AS n_aguardando,
  ROUND(AVG(
    EXTRACT(EPOCH FROM (NOW() - qe.data_solicitacao_sisreg)) / 86400
  ), 1) AS espera_media_dias,
  MIN(qe.municipio_paciente) AS municipio_paciente
FROM queue_entries qe
JOIN ubs u ON u.id = qe.ubs_id
WHERE u.nome IN ('UBS Bocaiúva', 'UBS Pirapora', 'UBS Janaúba')
  AND qe.status_local = 'aguardando'
GROUP BY u.nome
ORDER BY espera_media_dias DESC;

-- VX3 — Espera atual nova (target: > 80d)
SELECT
  ROUND(AVG(
    EXTRACT(EPOCH FROM (NOW() - qe.data_solicitacao_sisreg)) / 86400
  ), 1) AS espera_media_geral_dias,
  COUNT(*) AS total_aguardando
FROM queue_entries qe
WHERE qe.status_local = 'aguardando'
  AND qe.data_solicitacao_sisreg IS NOT NULL;
