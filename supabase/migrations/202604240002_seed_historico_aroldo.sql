-- ============================================================
-- SUS RAIO-X — Migration 202604240002
-- Seed Final Demo: Histórico Hospital Aroldo Tourinho
-- Data: 2026-04-20
-- ============================================================
-- ALVO: +78 appointments finalizados
--   ~44 realizados + ~34 faltou → absenteísmo final ~42%
--   Distribuídos em ~30 dias → ~2.6/dia para tendência
--
-- NARRATIVA: Aroldo Tourinho = hospital público com maior taxa
--   de absenteísmo. Principal justificativa do sistema.
--
-- IDENTIFICADOR: data_source = 'seed_final_demo'
-- ROLLBACK: executar 202604240001_rollback_seed_final.sql
-- EXECUTE APÓS: seeds 202604210001/2/3 (infra já executada)
-- ============================================================

BEGIN;

DO $$
DECLARE
  -- Equipment IDs: buscados dinâmicamente por nome em BEGIN
  v_eq_rx01  uuid;
  v_eq_rx02  uuid;
  v_eq_us01  uuid;

  -- UBSs reguladoras (lookup dinâmico por nome)
  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mar3 uuid; v_ubs_mar4 uuid;
  v_ubs_mp1  uuid; v_ubs_mp2  uuid; v_ubs_mp3  uuid; v_ubs_mp4  uuid;
  v_ubs_sjl3 uuid; v_ubs_cin1 uuid; v_ubs_cin2 uuid;
  v_ubs_boc  uuid; v_ubs_pir  uuid; v_ubs_jan  uuid;

  -- Enum types
  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  -- Arrays de trabalho
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
  -- Carregar enums de registro existente
  -- Aroldo: RX e US → tipo 'exame'
  SELECT tipo_atendimento INTO v_ta
  FROM queue_entries WHERE tipo_atendimento::text = 'exame' LIMIT 1;
  IF v_ta IS NULL THEN
    SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  END IF;

  SELECT tipo_vaga INTO v_tv FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;

  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  -- UBSs reguladoras
  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mar3 FROM ubs WHERE nome = 'Maracanã III';
  SELECT id INTO v_ubs_mar4 FROM ubs WHERE nome = 'Maracanã IV';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mp2  FROM ubs WHERE nome = 'Major Prates II';
  SELECT id INTO v_ubs_mp3  FROM ubs WHERE nome = 'Major Prates III';
  SELECT id INTO v_ubs_mp4  FROM ubs WHERE nome = 'Major Prates IV';
  SELECT id INTO v_ubs_sjl3 FROM ubs WHERE nome = 'São José e Lourdes III';
  SELECT id INTO v_ubs_cin1 FROM ubs WHERE nome = 'Cintra I';
  SELECT id INTO v_ubs_cin2 FROM ubs WHERE nome = 'Cintra II';
  SELECT id INTO v_ubs_boc  FROM ubs WHERE nome = 'UBS Bocaiúva';
  SELECT id INTO v_ubs_pir  FROM ubs WHERE nome = 'UBS Pirapora';
  SELECT id INTO v_ubs_jan  FROM ubs WHERE nome = 'UBS Janaúba';

  IF v_ubs_ind2 IS NULL THEN
    RAISE EXCEPTION 'UBSs seed não encontradas. Execute 202604210001 primeiro.';
  END IF;

  -- Pacientes seed (54 total, CNS prefixo 800001)
  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients
  FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);
  IF v_n_pat = 0 THEN
    RAISE EXCEPTION 'Pacientes seed não encontrados.';
  END IF;

  -- Equipment IDs: lookup dinâmico por nome
  SELECT id INTO v_eq_rx01 FROM equipment WHERE nome = 'RX-01 — Aroldo Tourinho';
  SELECT id INTO v_eq_rx02 FROM equipment WHERE nome = 'RX-02 — Aroldo Tourinho';
  SELECT id INTO v_eq_us01 FROM equipment WHERE nome = 'US-01 — Aroldo Tourinho';
  IF v_eq_rx01 IS NULL THEN
    RAISE EXCEPTION 'Equipment Aroldo Tourinho não encontrado. Verifique seed 202604210001.';
  END IF;

  -- Rotação de equipamentos (3 de Aroldo)
  v_equips := ARRAY[v_eq_rx01, v_eq_rx02, v_eq_us01];

  -- Rotação de UBSs reguladoras (14 ao total)
  -- Distribuição favorece MC, mas inclui macrorregião para narrativa
  v_ubs_regs := ARRAY[
    v_ubs_ind2, v_ubs_mar2, v_ubs_mp1,  v_ubs_mar3,
    v_ubs_mp2,  v_ubs_mar4, v_ubs_mp3,  v_ubs_sjl3,
    v_ubs_mp4,  v_ubs_cin1, v_ubs_cin2,
    v_ubs_boc,  v_ubs_pir,  v_ubs_jan
  ];
  v_n_ubs := array_length(v_ubs_regs, 1);

  -- ──────────────────────────────────────────────────────────
  -- 78 appointments: intervalo ~9h20m → 78 × 9.33h ≈ 728h ≈ 30 dias
  -- Absenteísmo: v_i % 7 < 3 = 3/7 = 42.9% faltou
  -- ──────────────────────────────────────────────────────────
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '30 days' + (n * INTERVAL '9 hours 20 minutes'))
    FROM generate_series(0, 77) n
  LOOP
    v_i := v_i + 1;

    -- Rotação cíclica: paciente, equipamento, UBS reguladora
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := v_equips  [1 + ((v_i - 1) % 3)];
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % v_n_ubs)];

    -- Status: 42.9% faltou (3 de cada 7)
    v_status := CASE WHEN v_i % 7 < 3 THEN 'faltou' ELSE 'realizado' END;

    -- queue_entry: registro de encaminhamento (histórico já realizado)
    INSERT INTO queue_entries (
      id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco,
      tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente,
      data_solicitacao_sisreg, data_source
    ) VALUES (
      gen_random_uuid(),
      v_pat_id,
      v_ubs_reg,
      'realizado',
      -- Distribuição de prioridade: 1 urgente, 2 médio, 3 padrão, 4 eletivo
      CASE WHEN v_i % 10 = 0 THEN 1
           WHEN v_i % 10 < 3  THEN 2
           WHEN v_i % 10 < 7  THEN 3
           ELSE 4 END,
      CASE WHEN v_i % 10 = 0 THEN 'vermelho'
           WHEN v_i % 10 < 3  THEN 'amarelo'
           WHEN v_i % 10 < 7  THEN 'verde'
           ELSE 'azul' END::prioridade_cor,
      v_ta, v_tv, v_tr,
      -- Municípios: maioria MC, polo macrorregional ciclicamente
      CASE WHEN v_i % 14 < 2 THEN 'Bocaiúva'
           WHEN v_i % 14 = 2 THEN 'Pirapora'
           WHEN v_i % 14 = 3 THEN 'Janaúba'
           ELSE 'Montes Claros' END,
      'MG',
      -- Espera histórica: 60-140 dias antes do agendamento
      -- Média ≈ 100 dias → contribui para espera_media_dias ~95d
      v_sched - ((60 + (v_i % 81)) || ' days')::interval,
      'seed_final_demo'
    ) RETURNING id INTO v_qe_id;

    -- appointment vinculado ao queue_entry
    INSERT INTO appointments (
      id, queue_entry_id, equipment_id,
      scheduled_at, realized_at,
      status, st_falta_registrada, data_source
    ) VALUES (
      gen_random_uuid(),
      v_qe_id,
      v_eq,
      v_sched,
      CASE WHEN v_status = 'realizado' THEN v_sched + INTERVAL '1 hour' ELSE NULL END,
      v_status::status_local,
      CASE WHEN v_status = 'faltou' THEN 1 ELSE 0 END,
      'seed_final_demo'
    );
  END LOOP;

  RAISE NOTICE 'Hospital Aroldo Tourinho: % appointments seed_final_demo inseridos', v_i;
END $$;

-- Verificação parcial pós-insert
SELECT
  'Aroldo Tourinho (seed_final_demo)' AS hospital,
  COUNT(*) FILTER (WHERE a.status = 'realizado') AS realizados,
  COUNT(*) FILTER (WHERE a.status = 'faltou')    AS faltou,
  ROUND(
    COUNT(*) FILTER (WHERE a.status = 'faltou') * 100.0 /
    NULLIF(COUNT(*) FILTER (WHERE a.status IN ('realizado','faltou')), 0), 1
  ) AS absenteismo_pct
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.nome = 'Hospital Aroldo Tourinho'
  AND a.data_source = 'seed_final_demo';

COMMIT;
