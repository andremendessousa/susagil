-- ============================================================
-- SUS RAIO-X — Migration 202604240009
-- Seed: Balanceamento frescos + velhos (3 escopos, Opção C)
-- Data: 2026-04-20
-- ============================================================
--
-- OBJETIVO: Popular os charts de "Procedimentos mais solicitados" e
--   "Espera e absenteísmo por município" na view de 30 DIAS nas 3 visões:
--
--   1. Montes Claros (municipal)    — UBSs com municipio='Montes Claros'
--   2. Macrorregião                 — polo: Bocaiúva, Pirapora, Janaúba
--   3. Reg. Independência           — Independência II (municipio='Montes Claros')
--
-- ESTRATÉGIA: pares fresh (20-29d) + old (182-194d):
--   • fresh → aparecem na view 30d (e 90d)
--   • old   → compensam a média V6 (par médio ≈ 107d > 80.5d atual)
--   • Seletor 90d mostrará TODOS (#frescos + #velhos + todos anteriores)
--
-- BALANCEAMENTO V6 (estimativa):
--   Estado anterior: ~104 aguardando × 80.5d = 8372d-paciente
--   +15 frescos × ~25d  =  375d-paciente
--   +15 velhos  × ~188d = 2820d-paciente
--   Total: (8372 + 375 + 2820) / 134 ≈ 86.3d ✅ (alvo: 80-130d)
--
-- UBSs utilizadas:
--   v_ubs_indep  = 'Independência II'                  (Montes Claros)
--   v_ubs_mc     = qualquer ESF tipo='S' em MC ≠ Indep (Montes Claros)
--   v_ubs_boc    = 'UBS Bocaiúva'                      (Bocaiúva)
--   v_ubs_pir    = 'UBS Pirapora'                      (Pirapora)
--   v_ubs_jan    = 'UBS Janaúba'                       (Janaúba)
--
-- ROLLBACK: coberto por 202604240001_rollback_seed_final.sql
--   DELETE FROM queue_entries WHERE data_source = 'seed_final_demo';
--   O rollback cobre TODOS os seeds 002-009 de forma atômica.
-- ============================================================

BEGIN;

DO $$
DECLARE
  -- UBSs encaminhadoras
  v_ubs_indep  uuid;   -- Independência II (Reg. Independência + MC view)
  v_ubs_mc     uuid;   -- ESF tipo='S' em Montes Claros, ≠ Independência II
  v_ubs_boc    uuid;   -- UBS Bocaiúva (Macrorregião)
  v_ubs_pir    uuid;   -- UBS Pirapora (Macrorregião)
  v_ubs_jan    uuid;   -- UBS Janaúba (Macrorregião)

  -- Tipos enum herdados de registros existentes
  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  -- Pool de pacientes seed (cns LIKE '800001%', criados em seed 202604200001)
  v_patients uuid[];
  v_n_pat    int;

  -- Nome da ESF MC descoberta dinamicamente (observabilidade no RAISE NOTICE)
  v_ubs_mc_nome text;

  v_rows_fresh int := 0;
  v_rows_old   int := 0;
BEGIN

  -- ── 1. Resolver IDs das UBSs ─────────────────────────────────────────────

  SELECT id INTO v_ubs_indep FROM ubs WHERE nome = 'Independência II'  LIMIT 1;
  SELECT id, nome INTO v_ubs_mc, v_ubs_mc_nome FROM ubs
    WHERE municipio = 'Montes Claros'
      AND tipo = 'S'
      AND nome != 'Independência II'
    LIMIT 1;
  SELECT id INTO v_ubs_boc FROM ubs WHERE nome = 'UBS Bocaiúva' LIMIT 1;
  SELECT id INTO v_ubs_pir FROM ubs WHERE nome = 'UBS Pirapora' LIMIT 1;
  SELECT id INTO v_ubs_jan FROM ubs WHERE nome = 'UBS Janaúba'  LIMIT 1;

  IF v_ubs_indep IS NULL THEN RAISE EXCEPTION 'Independência II não encontrada.'; END IF;
  IF v_ubs_mc    IS NULL THEN RAISE EXCEPTION 'ESF Montes Claros tipo=S não encontrada.'; END IF;
  IF v_ubs_boc   IS NULL THEN RAISE EXCEPTION 'UBS Bocaiúva não encontrada.'; END IF;
  IF v_ubs_pir   IS NULL THEN RAISE EXCEPTION 'UBS Pirapora não encontrada.'; END IF;
  IF v_ubs_jan   IS NULL THEN RAISE EXCEPTION 'UBS Janaúba não encontrada.'; END IF;

  -- ── 2. Herdar tipos enum de registros existentes ─────────────────────────

  SELECT tipo_atendimento INTO v_ta
    FROM queue_entries WHERE tipo_atendimento::text = 'consulta' LIMIT 1;
  IF v_ta IS NULL THEN
    SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  END IF;

  SELECT tipo_vaga      INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- ── 3. Pool de pacientes seed ─────────────────────────────────────────────

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients
    FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  IF v_n_pat IS NULL OR v_n_pat < 1 THEN
    RAISE EXCEPTION 'Pacientes 800001%% não encontrados. Execute seed 202604200001 antes.';
  END IF;
  -- Índices vão de 0..5 com módulo: seguro para qualquer v_n_pat >= 1 (wrapping garantido)

  RAISE NOTICE 'Pool de pacientes: % disponíveis', v_n_pat;
  RAISE NOTICE 'UBSs selecionadas:';
  RAISE NOTICE '  Independência II  = %', v_ubs_indep;
  RAISE NOTICE '  ESF MC (tipo=S)   = % [%]', v_ubs_mc_nome, v_ubs_mc;
  RAISE NOTICE '  UBS Bocaiúva      = %', v_ubs_boc;
  RAISE NOTICE '  UBS Pirapora      = %', v_ubs_pir;
  RAISE NOTICE '  UBS Janaúba       = %', v_ubs_jan;

  -- ════════════════════════════════════════════════════════════
  --  BLOCO A — FRESCOS (20-29 dias atrás)
  --  15 registros: 3 por UBS × 5 UBSs
  --  Objetivo: os charts 30d passam a ter dados após esta migration
  -- ════════════════════════════════════════════════════════════

  -- ── A1. Independência II — 3 registros (20-26d) ───────────────────────────
  -- Cobre: Reg. Independência + Montes Claros (espera_municipio = 'Montes Claros')
  -- Procedimentos: ortopedia + raio-x (coerentes com o escopo Reg. Ortopedia)
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (0 % v_n_pat)], v_ubs_indep,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Ortopedia e Traumatologia',
     NOW() - '20 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (1 % v_n_pat)], v_ubs_indep,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Consulta de Ortopedia',
     NOW() - '23 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (2 % v_n_pat)], v_ubs_indep,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Raio-X Convencional',
     NOW() - '26 days'::interval, 'seed_final_demo');
  v_rows_fresh := v_rows_fresh + 3;

  -- ── A2. MC UBS (ESF tipo='S') — 3 registros (21-27d) ─────────────────────
  -- Cobre: Montes Claros (complementa Independência II na view municipal)
  -- Procedimentos: imagem (diversidade no chart tipos_exame)
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (3 % v_n_pat)], v_ubs_mc,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Raio-X Convencional',
     NOW() - '21 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (4 % v_n_pat)], v_ubs_mc,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Ultrassonografia',
     NOW() - '24 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (5 % v_n_pat)], v_ubs_mc,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Tomografia Computadorizada',
     NOW() - '27 days'::interval, 'seed_final_demo');
  v_rows_fresh := v_rows_fresh + 3;

  -- ── A3. UBS Bocaiúva — 3 registros (22-28d) ──────────────────────────────
  -- Cobre: Macrorregião → Bocaiúva no chart espera_municipio
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (0 % v_n_pat)], v_ubs_boc,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Bocaiúva', 'MG', 'Consulta de Ortopedia',
     NOW() - '22 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (1 % v_n_pat)], v_ubs_boc,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Bocaiúva', 'MG', 'Raio-X Convencional',
     NOW() - '25 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (2 % v_n_pat)], v_ubs_boc,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Bocaiúva', 'MG', 'Ultrassonografia',
     NOW() - '28 days'::interval, 'seed_final_demo');
  v_rows_fresh := v_rows_fresh + 3;

  -- ── A4. UBS Pirapora — 3 registros (22-28d) ──────────────────────────────
  -- Cobre: Macrorregião → Pirapora no chart espera_municipio
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (3 % v_n_pat)], v_ubs_pir,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Pirapora', 'MG', 'Tomografia Computadorizada',
     NOW() - '22 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (4 % v_n_pat)], v_ubs_pir,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Pirapora', 'MG', 'Raio-X Convencional',
     NOW() - '25 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (5 % v_n_pat)], v_ubs_pir,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Pirapora', 'MG', 'Consulta de Ortopedia',
     NOW() - '28 days'::interval, 'seed_final_demo');
  v_rows_fresh := v_rows_fresh + 3;

  -- ── A5. UBS Janaúba — 3 registros (23-29d) ───────────────────────────────
  -- Cobre: Macrorregião → Janaúba no chart espera_municipio
  -- Procedimentos: RM vermelho (urgência narrativa para banca)
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (0 % v_n_pat)], v_ubs_jan,
     'aguardando', 1, 'vermelho'::prioridade_cor, v_ta, v_tv, v_tr,
     'Janaúba', 'MG', 'Ressonância Magnética',
     NOW() - '23 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (1 % v_n_pat)], v_ubs_jan,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Janaúba', 'MG', 'Raio-X Convencional',
     NOW() - '26 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (2 % v_n_pat)], v_ubs_jan,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Janaúba', 'MG', 'Ultrassonografia',
     NOW() - '29 days'::interval, 'seed_final_demo');
  v_rows_fresh := v_rows_fresh + 3;

  RAISE NOTICE 'BLOCO A: % queue_entries frescos inseridos (20-29d)', v_rows_fresh;

  -- ════════════════════════════════════════════════════════════
  --  BLOCO B — VELHOS (182-194 dias atrás)
  --  15 registros compensadores de V6
  --  Par fresh(25d) + old(188d) → média do par = 106.5d
  --  V6 estimado após: ≈ 86.3d ✅ (alvo: 80-130d)
  -- ════════════════════════════════════════════════════════════

  -- ── B1. Independência II — 3 registros (182-190d) ────────────────────────
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (3 % v_n_pat)], v_ubs_indep,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Ortopedia e Traumatologia',
     NOW() - '182 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (4 % v_n_pat)], v_ubs_indep,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Consulta de Ortopedia',
     NOW() - '186 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (5 % v_n_pat)], v_ubs_indep,
     'aguardando', 1, 'vermelho'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Ressonância Magnética',
     NOW() - '190 days'::interval, 'seed_final_demo');
  v_rows_old := v_rows_old + 3;

  -- ── B2. MC UBS — 3 registros (183-191d) ──────────────────────────────────
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (0 % v_n_pat)], v_ubs_mc,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Raio-X Convencional',
     NOW() - '183 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (1 % v_n_pat)], v_ubs_mc,
     'aguardando', 1, 'vermelho'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Tomografia Computadorizada',
     NOW() - '187 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (2 % v_n_pat)], v_ubs_mc,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Montes Claros', 'MG', 'Ultrassonografia',
     NOW() - '191 days'::interval, 'seed_final_demo');
  v_rows_old := v_rows_old + 3;

  -- ── B3. UBS Bocaiúva — 3 registros (184-192d) ────────────────────────────
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (3 % v_n_pat)], v_ubs_boc,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Bocaiúva', 'MG', 'Consulta de Ortopedia',
     NOW() - '184 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (4 % v_n_pat)], v_ubs_boc,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Bocaiúva', 'MG', 'Raio-X Convencional',
     NOW() - '188 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (5 % v_n_pat)], v_ubs_boc,
     'aguardando', 1, 'vermelho'::prioridade_cor, v_ta, v_tv, v_tr,
     'Bocaiúva', 'MG', 'Ressonância Magnética',
     NOW() - '192 days'::interval, 'seed_final_demo');
  v_rows_old := v_rows_old + 3;

  -- ── B4. UBS Pirapora — 3 registros (185-193d) ────────────────────────────
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (0 % v_n_pat)], v_ubs_pir,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Pirapora', 'MG', 'Tomografia Computadorizada',
     NOW() - '185 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (1 % v_n_pat)], v_ubs_pir,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Pirapora', 'MG', 'Ultrassonografia',
     NOW() - '189 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (2 % v_n_pat)], v_ubs_pir,
     'aguardando', 1, 'vermelho'::prioridade_cor, v_ta, v_tv, v_tr,
     'Pirapora', 'MG', 'Ressonância Magnética',
     NOW() - '193 days'::interval, 'seed_final_demo');
  v_rows_old := v_rows_old + 3;

  -- ── B5. UBS Janaúba — 3 registros (186-194d) ─────────────────────────────
  INSERT INTO queue_entries (
    id, patient_id, ubs_id, status_local,
    prioridade_codigo, cor_risco,
    tipo_atendimento, tipo_vaga, tipo_regulacao,
    municipio_paciente, uf_paciente,
    nome_grupo_procedimento, data_solicitacao_sisreg, data_source
  ) VALUES
    (gen_random_uuid(), v_patients[1 + (3 % v_n_pat)], v_ubs_jan,
     'aguardando', 1, 'vermelho'::prioridade_cor, v_ta, v_tv, v_tr,
     'Janaúba', 'MG', 'Ressonância Magnética',
     NOW() - '186 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (4 % v_n_pat)], v_ubs_jan,
     'aguardando', 2, 'amarelo'::prioridade_cor, v_ta, v_tv, v_tr,
     'Janaúba', 'MG', 'Tomografia Computadorizada',
     NOW() - '190 days'::interval, 'seed_final_demo'),
    (gen_random_uuid(), v_patients[1 + (5 % v_n_pat)], v_ubs_jan,
     'aguardando', 3, 'verde'::prioridade_cor, v_ta, v_tv, v_tr,
     'Janaúba', 'MG', 'Raio-X Convencional',
     NOW() - '194 days'::interval, 'seed_final_demo');
  v_rows_old := v_rows_old + 3;

  RAISE NOTICE 'BLOCO B: % queue_entries velhos inseridos (182-194d)', v_rows_old;
  RAISE NOTICE '─────────────────────────────────────────────────────────';
  RAISE NOTICE 'TOTAL Migration 009: % frescos + % velhos = % novos aguardando',
    v_rows_fresh, v_rows_old, v_rows_fresh + v_rows_old;
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  VERIFICAÇÕES PÓS-009
-- ════════════════════════════════════════════════════════════

-- VY1 — Frescos visíveis no filtro 30d (esperado: 15)
SELECT COUNT(*) AS frescos_30d
FROM queue_entries
WHERE data_source = 'seed_final_demo'
  AND status_local = 'aguardando'
  AND data_solicitacao_sisreg >= NOW() - '30 days'::interval;

-- VY2 — V6: espera média geral aguardando (target: 80-130d, estimativa ≈ 86d)
SELECT
  ROUND(AVG(
    EXTRACT(EPOCH FROM (NOW() - data_solicitacao_sisreg)) / 86400
  ), 1) AS espera_media_dias,
  COUNT(*) AS total_aguardando
FROM queue_entries
WHERE status_local = 'aguardando'
  AND data_solicitacao_sisreg IS NOT NULL;

-- VY3 — Procedimentos em 30d via RPC (esperado: ≥ 5 tipos com dados)
-- PRÉ-REQUISITO: migration 202604240008 deve ter sido executada antes.
-- Sem ela, a RPC usa lógica antiga (data_solicitacao_sisreg apenas) e pode retornar
-- resultados incompletos (sem erro explícito — falha silenciosa).
SELECT tipo_exame, total_solicitacoes
FROM get_tipos_exame_solicitados(30)
ORDER BY total_solicitacoes DESC;

-- VY4 — Espera por município em 30d (esperado: MC + Bocaiúva + Pirapora + Janaúba)
-- PRÉ-REQUISITO: migration 202604240008 deve ter sido executada antes.
SELECT municipio, total_pacientes, espera_media_dias
FROM get_espera_por_municipio(30)
ORDER BY espera_media_dias DESC;

-- VY5 — Comparação 30d vs 90d (esperado: 90d tem mais tipos e mais municípios)
SELECT '30d' AS periodo, COUNT(*) AS n_tipos FROM get_tipos_exame_solicitados(30)
UNION ALL
SELECT '90d', COUNT(*) FROM get_tipos_exame_solicitados(90);
