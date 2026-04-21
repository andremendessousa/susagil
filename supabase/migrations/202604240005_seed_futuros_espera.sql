-- ============================================================
-- SUS RAIO-X — Migration 202604240005
-- Seed Final Demo: Appointments Futuros + Fix Reaproveitamento
--   + Ajuste Espera Macrorregião + Verificações V1-V10
-- Data: 2026-04-20
-- ============================================================
-- BLOCO A: +50 agendamentos (próximos 7 dias, todos 15 equipamentos)
--   → Ocupação futura alvo: ~60% (50 + ~15 pipeline / 105 slots)
-- BLOCO B: +11 cancelamentos passados
--   → Reaproveitamento: 3 reaprov / (1+11) = 3/12 = 25% ✓
-- BLOCO C: UPDATE data_solicitacao_sisreg aguardando macrorregião
--   → Espera polo (Bocaiúva/Pirapora/Janaúba): 120-160 dias
--   → Espera MC UBSs: 50-110 dias
-- V1-V10: Verificações finais de todos os KPIs
-- ============================================================
-- IDENTIFICADOR: data_source = 'seed_final_demo'
-- ROLLBACK:       executar 202604240001_rollback_seed_final.sql
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
--  BLOCO A — Appointments futuros (próximos 7 dias)
--  Target: ~50 novos → ocupação futura ~60%
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  -- todos os 15 equipamentos (carregados dinamicamente a partir do cnes_code)
  v_equips uuid[];

  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mp1 uuid;
  v_ubs_mp2  uuid; v_ubs_mar3 uuid; v_ubs_cin1 uuid;

  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_ubs_regs uuid[];
  v_i int := 0; v_n_pat int; v_n_ubs int;
  v_qe_id uuid; v_pat_id uuid; v_sched timestamptz;
  v_eq uuid; v_ubs_reg uuid;
BEGIN
  SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  SELECT tipo_vaga      INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_ta IS NULL THEN v_ta := 'consulta'; END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mp2  FROM ubs WHERE nome = 'Major Prates II';
  SELECT id INTO v_ubs_mar3 FROM ubs WHERE nome = 'Maracanã III';
  SELECT id INTO v_ubs_cin1 FROM ubs WHERE nome = 'Cintra I';

  -- Carrega todos os 15 equipamentos dos hospitais-parceiro (cnes 9999%)
  SELECT ARRAY_AGG(eq.id ORDER BY eq.ubs_id, eq.nome)
  INTO v_equips
  FROM equipment eq
  JOIN ubs u ON u.id = eq.ubs_id
  WHERE u.cnes_code LIKE '9999%';

  IF array_length(v_equips, 1) < 15 THEN
    RAISE EXCEPTION 'Esperados 15 equipamentos, encontrados %. Verifique seed 202604210001.',
      COALESCE(array_length(v_equips, 1)::text, '0');
  END IF;

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_ubs_regs := ARRAY[v_ubs_ind2, v_ubs_mar2, v_ubs_mp1, v_ubs_mp2, v_ubs_mar3, v_ubs_cin1];
  v_n_ubs := array_length(v_ubs_regs, 1);

  -- 50 appointments futuros: intervalo ~3h22m → 50 × 3.37h ≈ 168h = 7 dias
  -- scheduled_at começa em NOW() + 6h para evitar conflito com agora
  FOR v_sched IN
    SELECT (NOW() + INTERVAL '6 hours' + (n * INTERVAL '3 hours 22 minutes'))
    FROM generate_series(0, 49) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := v_equips[1 + ((v_i - 1) % 15)];
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % v_n_ubs)];

    -- data_solicitacao_sisreg: recente (20-60 dias atrás = nova solicitação)
    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'aguardando',
      CASE WHEN v_i%10=0 THEN 1 WHEN v_i%10<3 THEN 2 WHEN v_i%10<7 THEN 3 ELSE 4 END,
      CASE WHEN v_i%10=0 THEN 'vermelho' WHEN v_i%10<3 THEN 'amarelo'
           WHEN v_i%10<7 THEN 'verde' ELSE 'azul' END::prioridade_cor,
      v_ta, v_tv, v_tr, 'Montes Claros', 'MG',
      NOW() - ((20 + (v_i % 41)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq, v_sched, NULL,
      'agendado', 0, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'Futuros: % appointments agendados inseridos', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO B — 11 Cancelamentos passados
--  Fix: reaproveitamento 3/1(300%) → 3/12(25%)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  -- Usar equipamentos variados para cancelamentos (buscados dinâmico)
  v_equips uuid[];

  v_ubs_ind2 uuid; v_ubs_mar2 uuid; v_ubs_mp1 uuid;
  v_ubs_mp3  uuid; v_ubs_cin1 uuid;

  v_ta  queue_entries.tipo_atendimento%TYPE;
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;

  v_patients uuid[];
  v_ubs_regs uuid[];
  v_i    int := 0;
  v_n_pat int;
  v_qe_id   uuid;
  v_pat_id  uuid;
  v_sched   timestamptz;
  v_eq      uuid;
  v_ubs_reg uuid;
BEGIN
  SELECT tipo_atendimento INTO v_ta FROM queue_entries LIMIT 1;
  SELECT tipo_vaga      INTO v_tv FROM queue_entries LIMIT 1;
  SELECT tipo_regulacao INTO v_tr FROM queue_entries LIMIT 1;
  IF v_ta IS NULL THEN v_ta := 'consulta'; END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera'; END IF;

  SELECT id INTO v_ubs_ind2 FROM ubs WHERE nome = 'Independência II';
  SELECT id INTO v_ubs_mar2 FROM ubs WHERE nome = 'Maracanã II';
  SELECT id INTO v_ubs_mp1  FROM ubs WHERE nome = 'Major Prates I';
  SELECT id INTO v_ubs_mp3  FROM ubs WHERE nome = 'Major Prates III';
  SELECT id INTO v_ubs_cin1 FROM ubs WHERE nome = 'Cintra I';

  -- Equipamentos: array de todos os 15, acesso por índice 1-11 (subconjunto)
  SELECT ARRAY_AGG(eq.id ORDER BY eq.ubs_id, eq.nome)
  INTO v_equips
  FROM equipment eq
  JOIN ubs u ON u.id = eq.ubs_id
  WHERE u.cnes_code LIKE '9999%';

  SELECT ARRAY_AGG(id ORDER BY cns) INTO v_patients FROM patients WHERE cns LIKE '800001%';
  v_n_pat := array_length(v_patients, 1);

  v_ubs_regs := ARRAY[v_ubs_ind2, v_ubs_mar2, v_ubs_mp1, v_ubs_mp3, v_ubs_cin1];

  -- 11 cancelamentos nos últimos 25 dias: intervalo ~54h
  FOR v_sched IN
    SELECT (NOW() - INTERVAL '25 days' + (n * INTERVAL '54 hours'))
    FROM generate_series(0, 10) n
  LOOP
    v_i      := v_i + 1;
    v_pat_id  := v_patients[1 + ((v_i - 1) % v_n_pat)];
    v_eq      := v_equips[v_i];   -- 11 equips distintos
    v_ubs_reg := v_ubs_regs[1 + ((v_i - 1) % 5)];

    INSERT INTO queue_entries (id, patient_id, ubs_id, status_local,
      prioridade_codigo, cor_risco, tipo_atendimento, tipo_vaga, tipo_regulacao,
      municipio_paciente, uf_paciente, data_solicitacao_sisreg, data_source)
    VALUES (gen_random_uuid(), v_pat_id, v_ubs_reg, 'cancelado',
      3, 'verde', v_ta, v_tv, v_tr, 'Montes Claros', 'MG',
      v_sched - ((40 + (v_i % 30)) || ' days')::interval,
      'seed_final_demo') RETURNING id INTO v_qe_id;

    INSERT INTO appointments (id, queue_entry_id, equipment_id,
      scheduled_at, realized_at, status, st_falta_registrada, data_source)
    VALUES (gen_random_uuid(), v_qe_id, v_eq, v_sched, NULL,
      'cancelado', 0, 'seed_final_demo');
  END LOOP;
  RAISE NOTICE 'Cancelamentos: % inseridos → reaproveitamento agora 3/12 = 25%%', v_i;
END $$;

-- ════════════════════════════════════════════════════════════
--  BLOCO C — Ajuste espera para UBSs macrorregião
--  Objetivo: espera polo (Bocaiúva/Pirapora/Janaúba) > 120 dias
--            espera MC  → 50-110 dias
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_ubs_boc uuid; v_ubs_pir uuid; v_ubs_jan uuid;
  v_rows_polo   int := 0;
  v_rows_mc     int := 0;
BEGIN
  SELECT id INTO v_ubs_boc FROM ubs WHERE nome = 'UBS Bocaiúva';
  SELECT id INTO v_ubs_pir FROM ubs WHERE nome = 'UBS Pirapora';
  SELECT id INTO v_ubs_jan FROM ubs WHERE nome = 'UBS Janaúba';

  -- Polo: forçar espera longa (narrativa: moradores de longe esperam mais)
  UPDATE queue_entries
  SET data_solicitacao_sisreg = CASE
    WHEN ubs_id = v_ubs_boc THEN NOW() - INTERVAL '130 days'
    WHEN ubs_id = v_ubs_pir THEN NOW() - INTERVAL '145 days'
    WHEN ubs_id = v_ubs_jan THEN NOW() - INTERVAL '150 days'
    ELSE data_solicitacao_sisreg
  END
  WHERE ubs_id IN (v_ubs_boc, v_ubs_pir, v_ubs_jan)
    AND status_local = 'aguardando';

  GET DIAGNOSTICS v_rows_polo = ROW_COUNT;

  -- MC aguardando: garantir que data_solicitacao_sisreg >= 50 dias atrás
  -- (Queue_entries muito recentes não contribuem para demanda reprimida > 30d)
  UPDATE queue_entries
  SET data_solicitacao_sisreg = NOW() - ((50 + abs(hashtext(id::text)) % 60) || ' days')::interval
  WHERE ubs_id NOT IN (v_ubs_boc, v_ubs_pir, v_ubs_jan)
    AND status_local = 'aguardando'
    AND data_solicitacao_sisreg > NOW() - INTERVAL '30 days';

  GET DIAGNOSTICS v_rows_mc = ROW_COUNT;
  RAISE NOTICE 'Espera polo atualizada: % registros | MC ajustados: %', v_rows_polo, v_rows_mc;
END $$;

COMMIT;

-- ════════════════════════════════════════════════════════════
--  VERIFICAÇÕES V1-V10 (diagnóstico pós-seed)
--  Execute individualmente para validar cada KPI
-- ════════════════════════════════════════════════════════════

-- V1 — Resumo geral do seed_final_demo
SELECT
  'TOTAL seed_final_demo' AS check_v1,
  COUNT(*) FILTER (WHERE a.status = 'realizado')   AS realizados,
  COUNT(*) FILTER (WHERE a.status = 'faltou')      AS faltou,
  COUNT(*) FILTER (WHERE a.status = 'agendado')    AS agendados_futuros,
  COUNT(*) FILTER (WHERE a.status = 'cancelado')   AS cancelados,
  COUNT(*)                                          AS total
FROM appointments a
WHERE a.data_source = 'seed_final_demo';

-- V2 — Absenteísmo global (seed_final_demo + seed_demo combinados)
SELECT
  'ABSENTEISMO GLOBAL' AS check_v2,
  COUNT(*) FILTER (WHERE a.status = 'realizado') AS realizados,
  COUNT(*) FILTER (WHERE a.status = 'faltou')    AS faltou,
  ROUND(
    COUNT(*) FILTER (WHERE a.status = 'faltou') * 100.0 /
    NULLIF(COUNT(*) FILTER (WHERE a.status IN ('realizado','faltou')), 0),
    1
  ) AS absenteismo_pct,
  'alvo: 28-32%' AS meta
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%';

-- V3 — Ocupação passada (últimos 30 dias)
SELECT
  'OCUPACAO PASSADA' AS check_v3,
  COUNT(*) FILTER (WHERE a.status = 'realizado') AS realizados,
  15 * 30                                         AS capacidade_total_30d,
  ROUND(
    COUNT(*) FILTER (WHERE a.status = 'realizado') * 100.0 / (15.0 * 30),
    1
  ) AS ocupacao_pct,
  'alvo: 40-55%' AS meta
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%'
  AND a.scheduled_at >= NOW() - INTERVAL '30 days'
  AND a.scheduled_at < NOW();

-- V4 — Reaproveitamento fix
SELECT
  'REAPROVEITAMENTO' AS check_v4,
  COUNT(*) FILTER (WHERE a.status = 'cancelado')         AS cancelados_total,
  COUNT(*) FILTER (WHERE a.reaproveitado_de_id IS NOT NULL) AS reaproveitados,
  ROUND(
    COUNT(*) FILTER (WHERE a.reaproveitado_de_id IS NOT NULL) * 100.0 /
    NULLIF(COUNT(*) FILTER (WHERE a.status = 'cancelado'), 0),
    1
  ) AS taxa_reaproveitamento_pct,
  'alvo: 15-30%' AS meta
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%';

-- V5 — Espera histórica (realizados com realized_at)
SELECT
  'ESPERA HISTORICA' AS check_v5,
  COUNT(*)                                               AS realizados_com_espera,
  ROUND(AVG(
    EXTRACT(EPOCH FROM (a.realized_at - qe.data_solicitacao_sisreg)) / 86400
  ), 1)                                                  AS espera_media_dias,
  'alvo: 70-130 dias' AS meta
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%'
  AND a.status = 'realizado'
  AND a.realized_at IS NOT NULL
  AND qe.data_solicitacao_sisreg IS NOT NULL;

-- V6 — Espera atual (aguardando)
SELECT
  'ESPERA ATUAL' AS check_v6,
  COUNT(*)                                               AS aguardando,
  ROUND(AVG(
    EXTRACT(EPOCH FROM (NOW() - qe.data_solicitacao_sisreg)) / 86400
  ), 1)                                                  AS espera_media_atual_dias,
  'alvo: 80-130 dias' AS meta
FROM queue_entries qe
JOIN ubs u ON u.id = qe.ubs_id
WHERE qe.status_local = 'aguardando'
  AND qe.data_solicitacao_sisreg IS NOT NULL;

-- V7 — Absenteísmo por hospital (incluindo existentes)
SELECT
  u.nome AS hospital,
  COUNT(*) FILTER (WHERE a.status = 'realizado') AS realizados,
  COUNT(*) FILTER (WHERE a.status = 'faltou')    AS faltou,
  ROUND(
    COUNT(*) FILTER (WHERE a.status = 'faltou') * 100.0 /
    NULLIF(COUNT(*) FILTER (WHERE a.status IN ('realizado','faltou')), 0),
    1
  ) AS absenteismo_pct
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%'
GROUP BY u.nome
ORDER BY absenteismo_pct DESC NULLS LAST;

-- V8 — Ocupação futura (próximos 7 dias)
SELECT
  'OCUPACAO FUTURA 7d' AS check_v8,
  COUNT(*) FILTER (WHERE a.status IN ('agendado','confirmado')
    AND a.scheduled_at BETWEEN NOW() AND NOW() + INTERVAL '7 days') AS comprometidos,
  (15 * 7)                                                           AS capacidade_7d,
  ROUND(
    COUNT(*) FILTER (WHERE a.status IN ('agendado','confirmado')
      AND a.scheduled_at BETWEEN NOW() AND NOW() + INTERVAL '7 days') * 100.0 / (15.0 * 7),
    1
  ) AS ocupacao_futura_pct,
  'alvo: 55-70%' AS meta
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs        u  ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%';

-- V9 — Distribuição de espera por UBS reguladora (top 8)
SELECT
  u.nome AS ubs_reguladora,
  COUNT(*) FILTER (WHERE qe.status_local = 'aguardando') AS n_aguardando,
  ROUND(AVG(
    EXTRACT(EPOCH FROM (NOW() - qe.data_solicitacao_sisreg)) / 86400
  ) FILTER (WHERE qe.status_local = 'aguardando'), 1)    AS espera_media_dias
FROM queue_entries qe
JOIN ubs u ON u.id = qe.ubs_id
WHERE qe.status_local = 'aguardando'
  AND qe.data_solicitacao_sisreg IS NOT NULL
GROUP BY u.nome
ORDER BY n_aguardando DESC
LIMIT 8;

-- V10 — Confirmação de rollback disponível
SELECT
  'ROLLBACK CHECK' AS check_v10,
  COUNT(*) FILTER (WHERE data_source = 'seed_final_demo') AS registros_seed_final,
  COUNT(*) FILTER (WHERE data_source = 'seed_demo')       AS registros_seed_base,
  'Rollback: DELETE WHERE data_source = seed_final_demo' AS instrucao
FROM appointments;
