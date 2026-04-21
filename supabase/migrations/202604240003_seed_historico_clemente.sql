-- ============================================================
-- SUS RAIO-X — Migration 202604240003
-- Seed Final Demo: Histórico HU Clemente de Faria — Ortopedia
-- Data: 2026-04-20
-- ============================================================
-- ALVO: +90 appointments finalizados
--   ~63 realizados + ~27 faltou → absenteísmo final ~30%
--   3 por dia × 30 dias → gráfico de tendência Reg. Independência
--
-- NARRATIVA: Escopo Regional Independência. Consultas ortopédicas
--   (tipo_atendimento='consulta'). Absenteísmo moderado.
--   UBS reguladora dominante: Independência II.
--
-- IDENTIFICADOR: data_source = 'seed_final_demo'
-- ROLLBACK: executar 202604240001_rollback_seed_final.sql
-- ============================================================

BEGIN;

DO $$
DECLARE
  -- Equipment IDs: buscados dinâmicamente por nome em BEGIN
  v_eq_orto  uuid;
  v_eq_trau  uuid;

  -- UBSs reguladoras
  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mar3 uuid;
  v_ubs_mp1  uuid; v_ubs_mp2  uuid; v_ubs_cin1 uuid;
  v_ubs_boc  uuid; v_ubs_pir  uuid;

  -- Enum types
  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  -- Arrays
  v_patients uuid[];
  v_equips   uuid[];
  v_ubs_regs uuid[];

  -- Loop vars
  v_i       int := 0;
  v_n_pat   int;
  v_n_ubs   int;
  v_qe_id   uuid;
  v_pat_id  uuid;
  v_sched   timestamptz;
  v_status  text;
  v_eq      uuid;
  v_ubs_reg uuid;
BEGIN
  -- HU Clemente: consultas ortopédicas → tipo 'consulta'
  SELECT tipo_atendimento INTO v_ta
  FROM queue_entries WHERE tipo_atendimento::text = 'consulta' LIMIT 1;
  IF v_ta IS NULL THEN
    SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  END IF;

  SELECT tipo_vaga      INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- UBSs seed
  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mar3 FROM ubs WHERE nome = 'Maracanã III';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mp2  FROM ubs WHERE nome = 'Major Prates II';
  SELECT id INTO v_ubs_cin1 FROM ubs WHERE nome = 'Cintra I';
  SELECT id INTO v_ubs_boc  FROM ubs WHERE nome = 'UBS Bocaiúva';
  SELECT id INTO v_ubs_pir  FROM ubs WHERE nome = 'UBS Pirapora';

  IF v_ubs_ind2 IS NULL THEN
    RAISE EXCEPTION 'UBSs seed não encontradas.';
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients
  FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  -- Equipment IDs: lookup dinâmico por nome
  SELECT id INTO v_eq_orto FROM equipment WHERE nome = 'Ortopedia — Consultório Manhã';
  SELECT id INTO v_eq_trau FROM equipment WHERE nome = 'Traumatologia — Consultório Tarde';
  IF v_eq_orto IS NULL THEN
    RAISE EXCEPTION 'Equipment HU Clemente não encontrado. Verifique seed 202604210001.';
  END IF;

  -- HU Clemente: 2 equipamentos em rotação
  v_equips := ARRAY[v_eq_orto, v_eq_trau];

  -- UBS reguladora: ~60% Independência II, resto diversificado
  -- Padrão: a cada 5, 3 são Independência II
  v_ubs_regs := ARRAY[
    v_ubs_ind2, v_ubs_ind2, v_ubs_ind2, -- 3×
    v_ubs_mar2, v_ubs_mp1,              -- 2×
    v_ubs_ind2, v_ubs_ind2, v_ubs_ind2, -- 3×
    v_ubs_mar3, v_ubs_mp2,              -- 2×
    v_ubs_cin1, v_ubs_boc,              -- polo
    v_ubs_pir                           -- polo
  ];
  v_n_ubs := array_length(v_ubs_regs, 1);

  -- ──────────────────────────────────────────────────────────
  -- 90 appointments: intervalo 8h exatos → 90 × 8h = 720h = 30 dias
  -- 3 appointments/dia → gráfico de tendência suave
  -- Absenteísmo: v_i % 10 < 3 = 30%
  -- ──────────────────────────────────────────────────────────
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '30 days' + (n * INTERVAL '8 hours'))
    FROM generate_series(0, 89) n
  LOOP
    v_i := v_i + 1;

    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := v_equips  [1 + ((v_i - 1) % 2)];
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % v_n_ubs)];

    -- 30% faltou (3 de cada 10)
    v_status := CASE WHEN v_i % 10 < 3 THEN 'faltou' ELSE 'realizado' END;

    INSERT INTO queue_entries (
      id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco,
      tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente,
      data_solicitacao_sisreg, data_source
    ) VALUES (
      gen_random_uuid(), v_pat_id, v_ubs_reg, 'realizado',
      CASE WHEN v_i % 8 = 0 THEN 1
           WHEN v_i % 8 < 3  THEN 2
           WHEN v_i % 8 < 6  THEN 3
           ELSE 4 END,
      CASE WHEN v_i % 8 = 0 THEN 'vermelho'
           WHEN v_i % 8 < 3  THEN 'amarelo'
           WHEN v_i % 8 < 6  THEN 'verde'
           ELSE 'azul' END::prioridade_cor,
      v_ta, v_tv, v_tr,
      CASE WHEN v_i % 13 = 0 THEN 'Bocaiúva'
           WHEN v_i % 13 = 1 THEN 'Pirapora'
           ELSE 'Montes Claros' END,
      'MG',
      -- Espera histórica: 50-130 dias (regional Independência)
      v_sched - ((50 + (v_i % 81)) || ' days')::interval,
      'seed_final_demo'
    ) RETURNING id INTO v_qe_id;

    INSERT INTO appointments (
      id, queue_entry_id, equipment_id,
      scheduled_at, realized_at,
      status, st_falta_registrada, data_source
    ) VALUES (
      gen_random_uuid(), v_qe_id, v_eq,
      v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local,
      CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END,
      'seed_final_demo'
    );
  END LOOP;

  RAISE NOTICE 'HU Clemente de Faria: % appointments seed_final_demo inseridos', v_i;
END $$;

-- Verificação parcial pós-insert
SELECT
  'HU Clemente (seed_final_demo)' AS hospital,
  COUNT(*) FILTER (WHERE a.status = 'realizado') AS realizados,
  COUNT(*) FILTER (WHERE a.status = 'faltou')    AS faltou,
  ROUND(
    COUNT(*) FILTER (WHERE a.status = 'faltou') * 100.0 /
    NULLIF(COUNT(*) FILTER (WHERE a.status IN ('realizado','faltou')), 0), 1
  ) AS absenteismo_pct
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.nome LIKE 'HU Clemente%'
  AND a.data_source = 'seed_final_demo';

COMMIT;
