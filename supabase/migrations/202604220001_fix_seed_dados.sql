-- ============================================================
-- SUS RAIO-X — Migration 202604220001
-- Fix: Correção de seed pós-diagnóstico Fase 0 (2026-04-20)
-- Referência: Edital CPSI 004/2026
--
-- PARTE A: tipo_atendimento — corrige 53 entradas 'exame' → 'consulta'
--          (procedimentos clínicos: "Consulta de Ortopedia" e "Avaliação Ortopédica")
-- PARTE B: Datas prio-4 — 3 pacientes com >90 dias de espera ajustados
--          para dentro da janela de análise (max 90d nos dashboards)
-- PARTE C: Capacidade dos equipamentos seed: 4-14/dia → 1/dia
--          (41 realizados / 450 capacity = ~9% ocupação — realista SUS)
-- PARTE D: Fila aguardando municípios polo + 2 novos pacientes seed
--          Bocaiúva +1, Pirapora +3, Janaúba +2 (total fila polo: 6 entradas)
-- ============================================================


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE A — Corrigir tipo_atendimento
--  Regra clínica:
--    'consulta' → "Consulta de Ortopedia e Traumatologia"
--                 "Avaliação Ortopédica — *" (joelho, ombro, coluna, quadril, tornozelo)
--    'exame'    → Radiografia, Tomografia, Ressonância, Ultrassonografia
--                 (já estão corretos — não serão tocados)
--  Impacto: ~53 linhas atualizadas em queue_entries (BLOCO C + BLOCO D)
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

UPDATE queue_entries
SET tipo_atendimento = 'consulta'
WHERE data_source = 'seed_demo'
  AND (
    nome_grupo_procedimento ILIKE '%Consulta%'
    OR nome_grupo_procedimento ILIKE '%Avaliação Ortopédica%'
  );

COMMIT;

-- ── Verificação Parte A ───────────────────────────────────────────────────────
-- SELECT tipo_atendimento::text, count(*)
-- FROM queue_entries
-- WHERE data_source = 'seed_demo'
-- GROUP BY 1;
-- Esperado: 'consulta' 53, 'exame' 52


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE B — Ajustar datas dos pacientes prio-4 para dentro da janela de 90 dias
--
--  Os dashboards usam horizontes de 7 / 30 / 90 dias.
--  Sebastião (130d), Irene (110d) e José Augusto (95d) ficam fora do
--  get_demanda_por_municipio e indicadores de espera quando horizonte ≤ 90d.
--
--  Ajuste preserva a narrativa ("meses esperando") e mantém a ordem FIFO:
--  Sebastião 87d > Irene 82d > José Augusto 80d > Ana Paula 85d * (reordenado, OK)
--  * Ana Paula (85d) já está dentro da janela — não alterada
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- Sebastião Rodrigues Pinto (CNS 800001000010017): 130d → 87d
UPDATE queue_entries
SET data_solicitacao_sisreg = now() - '87 days'::interval
WHERE data_source = 'seed_demo'
  AND status_local = 'aguardando'
  AND prioridade_codigo = 4
  AND patient_id = (
    SELECT id FROM patients
    WHERE cns = '800001000010017' AND data_source = 'seed_demo'
  );

-- Irene Batista dos Santos (CNS 800001000010018): 110d → 82d
UPDATE queue_entries
SET data_solicitacao_sisreg = now() - '82 days'::interval
WHERE data_source = 'seed_demo'
  AND status_local = 'aguardando'
  AND prioridade_codigo = 4
  AND patient_id = (
    SELECT id FROM patients
    WHERE cns = '800001000010018' AND data_source = 'seed_demo'
  );

-- José Augusto Carneiro (CNS 800001000010001): 95d → 80d
UPDATE queue_entries
SET data_solicitacao_sisreg = now() - '80 days'::interval
WHERE data_source = 'seed_demo'
  AND status_local = 'aguardando'
  AND prioridade_codigo = 4
  AND patient_id = (
    SELECT id FROM patients
    WHERE cns = '800001000010001' AND data_source = 'seed_demo'
  );

COMMIT;

-- ── Verificação Parte B ───────────────────────────────────────────────────────
-- SELECT p.nome,
--        floor(extract(epoch from (now() - qe.data_solicitacao_sisreg))/86400)::int AS dias_espera
-- FROM queue_entries qe
-- JOIN patients p ON p.id = qe.patient_id
-- WHERE qe.data_source = 'seed_demo'
--   AND qe.status_local = 'aguardando'
--   AND qe.prioridade_codigo = 4
-- ORDER BY dias_espera DESC;
-- Esperado: todos ≤ 87 dias (nenhum acima de 90)


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE C — Ajustar capacidade_dia dos equipamentos seed
--
--  Situação atual:  capacidade_dia entre 4 e 14  →  3.900 slots/30d
--  Impacto atual:   41 realizados / 3.900 = 1% ocupação (irreal)
--
--  Após ajuste:     capacidade_dia = 1  →  450 slots/30d (15 equip × 1 × 30)
--  Impacto esperado: 41 / 450 = ~9% ocupação (coerente com SUS público)
--
--  Escopo: only seed equipment (vinculados a UBSs com cnes_code LIKE '9999%')
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

UPDATE equipment
SET capacidade_dia = 1
WHERE nome IN (
  'RX-01 — Aroldo Tourinho',
  'RX-02 — Aroldo Tourinho',
  'US-01 — Aroldo Tourinho',
  'Ortopedia — Consultório Manhã',
  'Traumatologia — Consultório Tarde',
  'RX-01 — ImageMed',
  'US-01 — ImageMed',
  'RX-01 — Das Clínicas',
  'TC-01 — Das Clínicas',
  'RM-01 — Das Clínicas',
  'Ortopedia — Santa Casa',
  'RX-01 — Santa Casa',
  'Ortopedia — Dilson Godinho',
  'Consulta Ortopédica — OrthoMed',
  'RX-01 — OrthoMed'
);

COMMIT;

-- ── Verificação Parte C ───────────────────────────────────────────────────────
-- SELECT eq.nome, eq.capacidade_dia,
--        eq.capacidade_dia * 30 AS slots_30d
-- FROM equipment eq
-- JOIN ubs u ON u.id = eq.ubs_id
-- WHERE u.cnes_code LIKE '9999%'
-- ORDER BY eq.nome;
-- Esperado: capacidade_dia = 1 em todas as 15 linhas


-- ══════════════════════════════════════════════════════════════════════════════
--  PARTE D — Adicionar fila aguardando para municípios polo da macrorregião
--
--  Contexto SUS: pacientes de Bocaiúva, Pirapora e Janaúba encaminhados para
--  especialidade de ortopedia em Montes Claros (único polo de referência).
--  Sem este cenário o gráfico "Demanda por município" só exibe Montes Claros.
--
--  Distribuição:
--    Bocaiúva: Edmar (prio 3, consulta, 42d espera)
--    Pirapora:  Fátima (prio 2, consulta, 38d) + Iran (prio 3, exame, 22d)
--               + Rodrigo NOVO (prio 2, exame, 30d)
--    Janaúba:   Gildásio (prio 2, consulta, 35d)
--               + Neres NOVO (prio 3, exame, 19d)
--
--  2 novos pacientes inseridos: CNS 800001000060001 e 800001000060002
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  -- UBSs municipios polo
  v_boc    uuid;
  v_pir    uuid;
  v_jan    uuid;
  -- pacientes polo existentes (BLOCO B do migration 202604210002)
  p_edmar    uuid; -- 800001000050001 — Bocaiúva
  p_fatima   uuid; -- 800001000050002 — Pirapora
  p_gildasio uuid; -- 800001000050003 — Janaúba
  p_iran     uuid; -- 800001000050005 — Pirapora
  -- novos pacientes seed
  p_neres    uuid; -- 800001000060001 — Janaúba
  p_rodrigo  uuid; -- 800001000060002 — Pirapora
  -- enums (capturados de registro existente)
  v_tv  queue_entries.tipo_vaga%TYPE;
  v_tr  queue_entries.tipo_regulacao%TYPE;
BEGIN

  -- ── Lookups UBSs polo ─────────────────────────────────────────────────────
  SELECT id INTO v_boc FROM ubs WHERE nome = 'UBS Bocaiúva' LIMIT 1;
  SELECT id INTO v_pir FROM ubs WHERE nome = 'UBS Pirapora' LIMIT 1;
  SELECT id INTO v_jan FROM ubs WHERE nome = 'UBS Janaúba'  LIMIT 1;

  IF v_boc IS NULL OR v_pir IS NULL OR v_jan IS NULL THEN
    RAISE EXCEPTION 'UBSs macrorregionais não encontradas. Execute 202604210001 primeiro.';
  END IF;

  -- ── Lookups pacientes polo existentes ────────────────────────────────────
  SELECT id INTO p_edmar    FROM patients WHERE cns = '800001000050001' AND data_source = 'seed_demo';
  SELECT id INTO p_fatima   FROM patients WHERE cns = '800001000050002' AND data_source = 'seed_demo';
  SELECT id INTO p_gildasio FROM patients WHERE cns = '800001000050003' AND data_source = 'seed_demo';
  SELECT id INTO p_iran     FROM patients WHERE cns = '800001000050005' AND data_source = 'seed_demo';

  IF p_edmar IS NULL OR p_fatima IS NULL OR p_gildasio IS NULL OR p_iran IS NULL THEN
    RAISE EXCEPTION 'Pacientes polo não encontrados (Edmar/Fátima/Gildásio/Iran). Execute 202604210002 primeiro.';
  END IF;

  -- ── Inserir 2 novos pacientes seed ────────────────────────────────────────
  INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source)
  VALUES ('800001000060001', 'Neres Alves Figueiredo', 'Janaúba', 'MG', '38996230001', 'seed_demo')
  ON CONFLICT (cns) DO NOTHING;

  INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source)
  VALUES ('800001000060002', 'Rodrigo Castro Pinheiro', 'Pirapora', 'MG', '38996230002', 'seed_demo')
  ON CONFLICT (cns) DO NOTHING;

  SELECT id INTO p_neres   FROM patients WHERE cns = '800001000060001';
  SELECT id INTO p_rodrigo FROM patients WHERE cns = '800001000060002';

  -- ── Enums: capturar de registro existente ────────────────────────────────
  SELECT tipo_vaga, tipo_regulacao INTO v_tv, v_tr
  FROM queue_entries LIMIT 1;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- ──────────────────────────────────────────────────────────────────────────
  --  BOCAIÚVA +1
  --  Edmar, 58a, agricultor — prio 3 (verde) — espera 42 dias
  --  Narrativa: encaminhado da zona rural de Bocaiúva para ortopedia em MC
  -- ──────────────────────────────────────────────────────────────────────────

  INSERT INTO queue_entries (
    patient_id, ubs_id, municipio_paciente, uf_paciente,
    prioridade_codigo, tipo_regulacao, tipo_vaga, tipo_atendimento,
    nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source
  ) VALUES (
    p_edmar, v_boc, 'Bocaiúva', 'MG',
    3, v_tr, v_tv, 'consulta',
    'Avaliação Ortopédica — Joelho',
    'aguardando', now() - '42 days'::interval, 'seed_demo'
  );

  -- ──────────────────────────────────────────────────────────────────────────
  --  PIRAPORA +3
  --  Pirapora: cidade às margens do Rio São Francisco, ~60 mil hab.
  --  Sem ortopedista local — 100% dos casos regulados para MC (260 km)
  -- ──────────────────────────────────────────────────────────────────────────

  -- Fátima, 49a — prio 2 (amarelo) — consulta — espera 38 dias
  INSERT INTO queue_entries (
    patient_id, ubs_id, municipio_paciente, uf_paciente,
    prioridade_codigo, tipo_regulacao, tipo_vaga, tipo_atendimento,
    nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source
  ) VALUES (
    p_fatima, v_pir, 'Pirapora', 'MG',
    2, v_tr, v_tv, 'consulta',
    'Consulta de Ortopedia e Traumatologia',
    'aguardando', now() - '38 days'::interval, 'seed_demo'
  );

  -- Iran, 41a — prio 3 (verde) — exame — espera 22 dias
  INSERT INTO queue_entries (
    patient_id, ubs_id, municipio_paciente, uf_paciente,
    prioridade_codigo, tipo_regulacao, tipo_vaga, tipo_atendimento,
    nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source
  ) VALUES (
    p_iran, v_pir, 'Pirapora', 'MG',
    3, v_tr, v_tv, 'exame',
    'Radiografia de Coluna Lombar',
    'aguardando', now() - '22 days'::interval, 'seed_demo'
  );

  -- Rodrigo (novo), 35a — prio 2 (amarelo) — exame — espera 30 dias
  INSERT INTO queue_entries (
    patient_id, ubs_id, municipio_paciente, uf_paciente,
    prioridade_codigo, tipo_regulacao, tipo_vaga, tipo_atendimento,
    nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source
  ) VALUES (
    p_rodrigo, v_pir, 'Pirapora', 'MG',
    2, v_tr, v_tv, 'exame',
    'Ultrassonografia Musculoesquelética',
    'aguardando', now() - '30 days'::interval, 'seed_demo'
  );

  -- ──────────────────────────────────────────────────────────────────────────
  --  JANAÚBA +2
  --  Janaúba: polo do Alto Rio Pardo, ~70 mil hab., sem ortopedia pública local
  -- ──────────────────────────────────────────────────────────────────────────

  -- Gildásio, 62a — prio 2 (amarelo) — consulta — espera 35 dias
  INSERT INTO queue_entries (
    patient_id, ubs_id, municipio_paciente, uf_paciente,
    prioridade_codigo, tipo_regulacao, tipo_vaga, tipo_atendimento,
    nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source
  ) VALUES (
    p_gildasio, v_jan, 'Janaúba', 'MG',
    2, v_tr, v_tv, 'consulta',
    'Avaliação Ortopédica — Coluna Vertebral',
    'aguardando', now() - '35 days'::interval, 'seed_demo'
  );

  -- Neres (nova), 55a — prio 3 (verde) — exame — espera 19 dias
  INSERT INTO queue_entries (
    patient_id, ubs_id, municipio_paciente, uf_paciente,
    prioridade_codigo, tipo_regulacao, tipo_vaga, tipo_atendimento,
    nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source
  ) VALUES (
    p_neres, v_jan, 'Janaúba', 'MG',
    3, v_tr, v_tv, 'exame',
    'Radiografia de Coluna Lombar',
    'aguardando', now() - '19 days'::interval, 'seed_demo'
  );

  RAISE NOTICE '✅ PARTE D — Municípios polo: Bocaiúva+1, Pirapora+3, Janaúba+2 | +2 pacientes novos';

END $$;

COMMIT;
