-- ============================================================
-- SUS RAIO-X — Migration 202604240004
-- Seed Final Demo: Outros Hospitais (ImageMed, Das Clínicas,
--   Santa Casa, OrthoMed, Fundação Dilson Godinho)
-- Data: 2026-04-20
-- ============================================================
-- TOTAIS POR HOSPITAL (novos + existentes → absenteísmo final):
--   ImageMed Clinica de Imagem:  +28 → total ~35 fins. → ~14% absent.
--   Das Clínicas Dr. Mário Ribeiro: +22 → total ~31 fins. → ~19%
--   Santa Casa de Montes Claros: +18 → total ~24 fins. → ~33%
--   OrthoMed Clínica Especializada: +8 → total ~18 fins. → ~11%
--   Fundação Dilson Godinho: +7 → total ~11 fins. → ~27%
--
-- IDENTIFICADOR: data_source = 'seed_final_demo'
-- ROLLBACK: executar 202604240001_rollback_seed_final.sql
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
--  BLOCO A — ImageMed Clinica de Imagem
--  +28 finalizados → absenteísmo ~14% (parceiro privado imagem)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_eq_us01  uuid;  -- US-01 — ImageMed  (lookup dinâmico)
  v_eq_rx01  uuid;  -- RX-01 — ImageMed  (lookup dinâmico)

  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mp1 uuid;
  v_ubs_sjl3 uuid; v_ubs_cin1 uuid; v_ubs_boc uuid;
  v_ubs_pir  uuid; v_ubs_jan  uuid;

  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_ubs_regs uuid[];
  v_i int := 0; v_n_pat int; v_n_ubs int;
  v_qe_id uuid; v_pat_id uuid; v_sched timestamptz;
  v_status text; v_eq uuid; v_ubs_reg uuid;
BEGIN
  -- ImageMed: exames de imagem → tipo 'exame'
  SELECT tipo_atendimento INTO v_ta
  FROM queue_entries WHERE tipo_atendimento::text = 'exame' LIMIT 1;
  IF v_ta IS NULL THEN
    SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  END IF;
  SELECT tipo_vaga INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_sjl3 FROM ubs WHERE nome = 'São José e Lourdes III';
  SELECT id INTO v_ubs_cin1 FROM ubs WHERE nome = 'Cintra I';
  SELECT id INTO v_ubs_boc  FROM ubs WHERE nome = 'UBS Bocaiúva';
  SELECT id INTO v_ubs_pir  FROM ubs WHERE nome = 'UBS Pirapora';
  SELECT id INTO v_ubs_jan  FROM ubs WHERE nome = 'UBS Janaúba';
  SELECT id INTO v_eq_us01  FROM equipment WHERE nome = 'US-01 — ImageMed';
  SELECT id INTO v_eq_rx01  FROM equipment WHERE nome = 'RX-01 — ImageMed';
  IF v_eq_us01 IS NULL OR v_eq_rx01 IS NULL THEN
    RAISE EXCEPTION 'Equipment ImageMed não encontrado. Verifique seed 202604210001.';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients
  FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_ubs_regs := ARRAY[v_ubs_ind2, v_ubs_mar2, v_ubs_mp1, v_ubs_sjl3,
                      v_ubs_cin1, v_ubs_boc, v_ubs_pir, v_ubs_jan];
  v_n_ubs := array_length(v_ubs_regs, 1);

  -- 28 appointments: ~27h interval → 28 × 27h ≈ 31 dias
  -- Absenteísmo ~11%: v_i % 9 = 0 → 1/9 = 11.1%
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '30 days' + (n * INTERVAL '26 hours'))
    FROM generate_series(0, 27) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := CASE WHEN v_i % 2 = 0 THEN v_eq_rx01 ELSE v_eq_us01 END;
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % v_n_ubs)];
    v_status  := CASE WHEN v_i % 9 = 0 THEN 'faltou' ELSE 'realizado' END;

    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'realizado',
      CASE WHEN v_i%8=0 THEN 1 WHEN v_i%8<3 THEN 2 WHEN v_i%8<6 THEN 3 ELSE 4 END,
      CASE WHEN v_i%8=0 THEN 'vermelho' WHEN v_i%8<3 THEN 'amarelo'
           WHEN v_i%8<6 THEN 'verde' ELSE 'azul' END::prioridade_cor,
      v_ta, v_tv, v_tr,
      CASE WHEN v_i%12=0 THEN 'Bocaiúva' WHEN v_i%12=1 THEN 'Pirapora'
           WHEN v_i%12=2 THEN 'Janaúba' ELSE 'Montes Claros' END,
      'MG', v_sched - ((55 + (v_i % 71)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq, v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local, CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'ImageMed: % appointments inseridos', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO B — Hospital das Clínicas Dr. Mário Ribeiro
--  +22 finalizados → absenteísmo ~19% (referência qualidade)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_eq_rx01  uuid;  -- RX-01 — Das Clínicas  (lookup dinâmico)
  v_eq_tc01  uuid;  -- TC-01 — Das Clínicas  (lookup dinâmico)
  v_eq_rm01  uuid;  -- RM-01 — Das Clínicas  (lookup dinâmico)

  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mar3 uuid;
  v_ubs_mp1  uuid; v_ubs_mp3  uuid; v_ubs_boc  uuid;

  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_equips   uuid[];
  v_ubs_regs uuid[];
  v_i int := 0; v_n_pat int; v_n_ubs int;
  v_qe_id uuid; v_pat_id uuid; v_sched timestamptz;
  v_status text; v_eq uuid; v_ubs_reg uuid;
BEGIN
  -- Das Clínicas: RX, TC, RM → tipo 'exame'
  SELECT tipo_atendimento INTO v_ta
  FROM queue_entries WHERE tipo_atendimento::text = 'exame' LIMIT 1;
  IF v_ta IS NULL THEN SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1; END IF;
  SELECT tipo_vaga INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mar3 FROM ubs WHERE nome = 'Maracanã III';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mp3  FROM ubs WHERE nome = 'Major Prates III';
  SELECT id INTO v_ubs_boc  FROM ubs WHERE nome = 'UBS Bocaiúva';
  SELECT id INTO v_eq_rx01  FROM equipment WHERE nome = 'RX-01 — Das Clínicas';
  SELECT id INTO v_eq_tc01  FROM equipment WHERE nome = 'TC-01 — Das Clínicas';
  SELECT id INTO v_eq_rm01  FROM equipment WHERE nome = 'RM-01 — Das Clínicas';
  IF v_eq_rx01 IS NULL OR v_eq_tc01 IS NULL THEN
    RAISE EXCEPTION 'Equipment Das Clínicas não encontrado. Verifique seed 202604210001.';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_equips   := ARRAY[v_eq_rx01, v_eq_tc01, v_eq_rm01];
  v_ubs_regs := ARRAY[v_ubs_ind2, v_ubs_mar2, v_ubs_mar3, v_ubs_mp1, v_ubs_mp3, v_ubs_boc];
  v_n_ubs := array_length(v_ubs_regs, 1);

  -- 22 appointments: ~32h interval
  -- Absenteísmo ~18%: v_i % 5 = 0 → wait, 1/5 = 20%. Use v_i%11=0 = 9.1% → too low
  -- v_i % 5 = 0 → 20%, closest to 19% target
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '30 days' + (n * INTERVAL '33 hours'))
    FROM generate_series(0, 21) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := v_equips  [1 + ((v_i - 1) % 3)];
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % v_n_ubs)];
    v_status  := CASE WHEN v_i % 5 = 0 THEN 'faltou' ELSE 'realizado' END;

    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'realizado',
      CASE WHEN v_i%8=0 THEN 1 WHEN v_i%8<3 THEN 2 WHEN v_i%8<6 THEN 3 ELSE 4 END,
      CASE WHEN v_i%8=0 THEN 'vermelho' WHEN v_i%8<3 THEN 'amarelo'
           WHEN v_i%8<6 THEN 'verde' ELSE 'azul' END::prioridade_cor,
      v_ta, v_tv, v_tr,
      CASE WHEN v_i%10=0 THEN 'Bocaiúva' ELSE 'Montes Claros' END,
      'MG', v_sched - ((65 + (v_i % 65)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq, v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local, CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'Das Clínicas: % appointments inseridos', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO C — Santa Casa de Montes Claros
--  +18 finalizados → absenteísmo ~33% (acima da média)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_eq_rx01  uuid;  -- RX-01 — Santa Casa    (lookup dinâmico)
  v_eq_orto  uuid;  -- Ortopedia — Santa Casa (lookup dinâmico)

  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mp1  uuid;
  v_ubs_mp2  uuid; v_ubs_sjl3 uuid; v_ubs_cin2 uuid;

  v_ta_exame    queue_entries.tipo_atendimento%TYPE;
  v_ta_consulta queue_entries.tipo_atendimento%TYPE;
  v_tv          queue_entries.tipo_vaga%TYPE;
  v_tr          queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_ubs_regs uuid[];
  v_i int := 0; v_n_pat int; v_n_ubs int;
  v_qe_id uuid; v_pat_id uuid; v_sched timestamptz;
  v_status text; v_eq uuid; v_ubs_reg uuid; v_ta queue_entries.tipo_atendimento%TYPE;
BEGIN
  SELECT tipo_atendimento INTO v_ta_exame
  FROM queue_entries WHERE tipo_atendimento::text = 'exame' LIMIT 1;
  SELECT tipo_atendimento INTO v_ta_consulta
  FROM queue_entries WHERE tipo_atendimento::text = 'consulta' LIMIT 1;
  IF v_ta_exame IS NULL THEN v_ta_exame := v_ta_consulta; END IF;
  IF v_ta_consulta IS NULL THEN SELECT tipo_atendimento INTO v_ta_consulta FROM queue_entries LIMIT 1; END IF;
  SELECT tipo_vaga INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mp2  FROM ubs WHERE nome = 'Major Prates II';
  SELECT id INTO v_ubs_sjl3 FROM ubs WHERE nome = 'São José e Lourdes III';
  SELECT id INTO v_ubs_cin2 FROM ubs WHERE nome = 'Cintra II';
  SELECT id INTO v_eq_rx01  FROM equipment WHERE nome = 'RX-01 — Santa Casa';
  SELECT id INTO v_eq_orto  FROM equipment WHERE nome = 'Ortopedia — Santa Casa';
  IF v_eq_rx01 IS NULL OR v_eq_orto IS NULL THEN
    RAISE EXCEPTION 'Equipment Santa Casa não encontrado. Verifique seed 202604210001.';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_ubs_regs := ARRAY[v_ubs_ind2, v_ubs_mar2, v_ubs_mp1, v_ubs_mp2, v_ubs_sjl3, v_ubs_cin2];
  v_n_ubs := array_length(v_ubs_regs, 1);

  -- 18 appointments: ~40h interval
  -- Absenteísmo ~33%: v_i % 3 = 0 → 1/3 = 33.3%
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '30 days' + (n * INTERVAL '40 hours'))
    FROM generate_series(0, 17) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    -- Alterna: par=RX (exame), ímpar=Ortopedia (consulta)
    v_eq      := CASE WHEN v_i % 2 = 0 THEN v_eq_rx01 ELSE v_eq_orto END;
    v_ta      := CASE WHEN v_i % 2 = 0 THEN v_ta_exame ELSE v_ta_consulta END;
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % v_n_ubs)];
    v_status  := CASE WHEN v_i % 3 = 0 THEN 'faltou' ELSE 'realizado' END;

    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'realizado',
      CASE WHEN v_i%8=0 THEN 1 WHEN v_i%8<3 THEN 2 WHEN v_i%8<6 THEN 3 ELSE 4 END,
      CASE WHEN v_i%8=0 THEN 'vermelho' WHEN v_i%8<3 THEN 'amarelo'
           WHEN v_i%8<6 THEN 'verde' ELSE 'azul' END::prioridade_cor,
      v_ta, v_tv, v_tr, 'Montes Claros', 'MG',
      v_sched - ((55 + (v_i % 75)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq, v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local, CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'Santa Casa: % appointments inseridos', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO D — OrthoMed Clínica Especializada
--  +8 finalizados → absenteísmo ~11% (parceiro exemplar)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_eq_rx01     uuid;  -- RX-01 — OrthoMed              (lookup dinâmico)
  v_eq_consulta uuid;  -- Consulta Ortopédica — OrthoMed (lookup dinâmico)

  v_ubs_ind2 uuid; v_ubs_mp1 uuid; v_ubs_mar2 uuid; v_ubs_cin1 uuid;

  v_ta_exame    queue_entries.tipo_atendimento%TYPE;
  v_ta_consulta queue_entries.tipo_atendimento%TYPE;
  v_tv          queue_entries.tipo_vaga%TYPE;
  v_tr          queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_ubs_regs uuid[];
  v_i int := 0; v_n_pat int;
  v_qe_id uuid; v_pat_id uuid; v_sched timestamptz;
  v_status text; v_eq uuid; v_ubs_reg uuid; v_ta queue_entries.tipo_atendimento%TYPE;
BEGIN
  SELECT tipo_atendimento INTO v_ta_exame
  FROM queue_entries WHERE tipo_atendimento::text = 'exame' LIMIT 1;
  SELECT tipo_atendimento INTO v_ta_consulta
  FROM queue_entries WHERE tipo_atendimento::text = 'consulta' LIMIT 1;
  IF v_ta_exame IS NULL THEN v_ta_exame := v_ta_consulta; END IF;
  IF v_ta_consulta IS NULL THEN SELECT tipo_atendimento INTO v_ta_consulta FROM queue_entries LIMIT 1; END IF;
  SELECT tipo_vaga INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_cin1   FROM ubs WHERE nome = 'Cintra I';
  SELECT id INTO v_eq_rx01    FROM equipment WHERE nome = 'RX-01 — OrthoMed';
  SELECT id INTO v_eq_consulta FROM equipment WHERE nome = 'Consulta Ortopédica — OrthoMed';
  IF v_eq_rx01 IS NULL OR v_eq_consulta IS NULL THEN
    RAISE EXCEPTION 'Equipment OrthoMed não encontrado. Verifique seed 202604210001.';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_ubs_regs := ARRAY[v_ubs_ind2, v_ubs_mp1, v_ubs_mar2, v_ubs_cin1];

  -- 8 appointments: ~90h interval
  -- Absenteísmo ~12%: v_i % 8 = 0 → 1/8 = 12.5%
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '29 days' + (n * INTERVAL '88 hours'))
    FROM generate_series(0, 7) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := CASE WHEN v_i % 2 = 0 THEN v_eq_rx01 ELSE v_eq_consulta END;
    v_ta      := CASE WHEN v_i % 2 = 0 THEN v_ta_exame ELSE v_ta_consulta END;
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % 4)];
    v_status  := CASE WHEN v_i % 8 = 0 THEN 'faltou' ELSE 'realizado' END;

    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'realizado',
      3, 'verde', v_ta, v_tv, v_tr, 'Montes Claros', 'MG',
      v_sched - ((60 + (v_i % 50)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq, v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local, CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'OrthoMed: % appointments inseridos', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO E — Fundação Dilson Godinho
--  +7 finalizados → absenteísmo ~27%
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_eq_orto  uuid;  -- Ortopedia — Dilson Godinho (lookup dinâmico)

  v_ubs_mp2  uuid; v_ubs_mp3  uuid; v_ubs_mp4  uuid;
  v_ubs_cin2 uuid; v_ubs_sjl3 uuid;

  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_ubs_regs uuid[];
  v_i int := 0; v_n_pat int;
  v_qe_id uuid; v_pat_id uuid; v_sched timestamptz;
  v_status text; v_ubs_reg uuid;
BEGIN
  SELECT tipo_atendimento INTO v_ta
  FROM queue_entries WHERE tipo_atendimento::text = 'consulta' LIMIT 1;
  IF v_ta IS NULL THEN SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1; END IF;
  SELECT tipo_vaga INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_mp2  FROM ubs WHERE nome = 'Major Prates II';
  SELECT id INTO v_ubs_mp3  FROM ubs WHERE nome = 'Major Prates III';
  SELECT id INTO v_ubs_mp4  FROM ubs WHERE nome = 'Major Prates IV';
  SELECT id INTO v_ubs_cin2 FROM ubs WHERE nome = 'Cintra II';
  SELECT id INTO v_ubs_sjl3 FROM ubs WHERE nome = 'São José e Lourdes III';
  SELECT id INTO v_eq_orto  FROM equipment WHERE nome = 'Ortopedia — Dilson Godinho';
  IF v_eq_orto IS NULL THEN
    RAISE EXCEPTION 'Equipment Dilson Godinho não encontrado. Verifique seed 202604210001.';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_ubs_regs := ARRAY[v_ubs_mp2, v_ubs_mp3, v_ubs_mp4, v_ubs_cin2, v_ubs_sjl3];

  -- 7 appointments: ~100h interval
  -- Absenteísmo ~29%: v_i % 7 < 2 = 2/7 = 28.6%
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '29 days' + (n * INTERVAL '100 hours'))
    FROM generate_series(0, 6) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % 5)];
    v_status  := CASE WHEN v_i % 7 < 2 THEN 'faltou' ELSE 'realizado' END;

    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'realizado',
      3, 'verde', v_ta, v_tv, v_tr, 'Montes Claros', 'MG',
      v_sched - ((70 + (v_i % 40)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq_orto, v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local, CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'Fundação Dilson Godinho: % appointments inseridos', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  Verificação consolidada todos hospitais seed_final_demo
-- ════════════════════════════════════════════════════════════
SELECT
  u.nome AS hospital,
  COUNT(*) FILTER (WHERE a.status = 'realizado') AS realizados_novos,
  COUNT(*) FILTER (WHERE a.status = 'faltou')    AS faltou_novos
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE a.data_source = 'seed_final_demo'
  AND u.cnes_code LIKE '9999%'
GROUP BY u.nome
ORDER BY u.nome;

COMMIT;
