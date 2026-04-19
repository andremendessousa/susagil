-- ============================================================
-- SUS RAIO-X — Migration 0010
-- Seed: Regional Independência — Piloto Ortopedia/Traumatologia
-- Data: 2026-04-20
-- Referência: Edital CPSI 004/2026
--
-- Objetivo: popular o pipeline completo de notificações e fila
-- para demonstrar a "limpeza da fila" da Regional Independência.
--
-- Schema confirmado (2026-04-19):
--   ubs: id, cnes_code (varchar NOT NULL), nome, municipio, uf (char NOT NULL),
--        tipo (char NOT NULL), ativo (boolean NOT NULL)
--   tipo_atendimento enum: 'exame' | 'consulta'
--   tipo_vaga enum: 'primeira_vez' | 'retorno' | 'reserva' | 'fila'
--
-- CNES: prefixo 9999 (fictício — não colide com SCNES)
--   HU Clemente de Faria CNES real = 2219018 (substituir na aceleração)
-- CNS dos pacientes: prefixo 800001 (não colide com seed existente)
--
-- NARRATIVA DE DEMO (pipeline de notificações):
--   "A Regional Independência tem 8 pacientes aguardando vaga de ortopedia.
--    Há 4 agendamentos para as próximas 48h sem confirmação → Board 1.
--    3 já foram notificados e aguardam resposta → Board 2.
--    1 confirmou presença. 1 cancelou — o FIFO convocou o próximo da fila → Board 3.
--    Histórico: 5 realizados + 3 faltou = 37,5% absenteísmo → justifica o sistema."
--
-- Execute em sequência no Supabase SQL Editor:
--   BLOCO A → 4 ESFs (solicitantes) + HU Clemente de Faria (executante)
--   BLOCO B → 2 agendas médicas vinculadas ao HU
--   BLOCO C → 20 pacientes da regional
--   BLOCO D → Histórico KPI — 8 queue_entries + appointments passados
--   BLOCO E → Fila de espera — 8 pacientes aguardando (backlog)
--   BLOCO F → Agendamentos ativos + pipeline de notificações (7 pacientes)
--   BLOCO G → Verificação final
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  BLOCO A — UBSs da Regional Independência
--
--  Idempotente: verifica por nome antes de inserir.
--  cnes_code, uf e ativo são NOT NULL — obrigatórios.
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  v_esf_onix        uuid;
  v_esf_coral       uuid;
  v_esf_santos_reis uuid;
  v_esf_alto_bv     uuid;
  v_hu_ortopedia    uuid;
BEGIN

  -- ESF Ônix
  -- Bairros: Independência, Santos Dumont, Nova Suíça
  SELECT id INTO v_esf_onix FROM ubs WHERE nome = 'ESF Ônix' LIMIT 1;
  IF v_esf_onix IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(), '9999101', 'ESF Ônix', 'Montes Claros', 'MG', 'S', true)
    RETURNING id INTO v_esf_onix;
    RAISE NOTICE 'Criada: ESF Ônix (%)', v_esf_onix;
  ELSE
    RAISE NOTICE 'Já existe: ESF Ônix (%)', v_esf_onix;
  END IF;

  -- ESF Coral — Ibituruna
  -- Bairros: Ibituruna, Vila Santa Maria, Melo
  SELECT id INTO v_esf_coral FROM ubs WHERE nome = 'ESF Coral — Ibituruna' LIMIT 1;
  IF v_esf_coral IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(), '9999102', 'ESF Coral — Ibituruna', 'Montes Claros', 'MG', 'S', true)
    RETURNING id INTO v_esf_coral;
    RAISE NOTICE 'Criada: ESF Coral — Ibituruna (%)', v_esf_coral;
  ELSE
    RAISE NOTICE 'Já existe: ESF Coral — Ibituruna (%)', v_esf_coral;
  END IF;

  -- ESF Santos Reis
  -- Bairros: Santos Reis, Vila São Francisco de Assis
  SELECT id INTO v_esf_santos_reis FROM ubs WHERE nome = 'ESF Santos Reis' LIMIT 1;
  IF v_esf_santos_reis IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(), '9999103', 'ESF Santos Reis', 'Montes Claros', 'MG', 'S', true)
    RETURNING id INTO v_esf_santos_reis;
    RAISE NOTICE 'Criada: ESF Santos Reis (%)', v_esf_santos_reis;
  ELSE
    RAISE NOTICE 'Já existe: ESF Santos Reis (%)', v_esf_santos_reis;
  END IF;

  -- ESF Alto Boa Vista
  -- Bairros: Alto Boa Vista, Vila Sion I e II
  SELECT id INTO v_esf_alto_bv FROM ubs WHERE nome = 'ESF Alto Boa Vista' LIMIT 1;
  IF v_esf_alto_bv IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(), '9999104', 'ESF Alto Boa Vista', 'Montes Claros', 'MG', 'S', true)
    RETURNING id INTO v_esf_alto_bv;
    RAISE NOTICE 'Criada: ESF Alto Boa Vista (%)', v_esf_alto_bv;
  ELSE
    RAISE NOTICE 'Já existe: ESF Alto Boa Vista (%)', v_esf_alto_bv;
  END IF;

  -- HU Clemente de Faria — Ortopedia
  -- tipo='R' → executante/reguladora (aparece no modal AgendarModal)
  -- CNES real do HU Clemente de Faria: 2219018 — substituir na aceleração
  SELECT id INTO v_hu_ortopedia FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia' LIMIT 1;
  IF v_hu_ortopedia IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(), '9999150', 'HU Clemente de Faria — Ortopedia', 'Montes Claros', 'MG', 'R', true)
    RETURNING id INTO v_hu_ortopedia;
    RAISE NOTICE 'Criado executante: HU Clemente de Faria — Ortopedia (%)', v_hu_ortopedia;
  ELSE
    RAISE NOTICE 'Já existe: HU Clemente de Faria — Ortopedia (%)', v_hu_ortopedia;
  END IF;

  RAISE NOTICE '✅ BLOCO A — 4 ESFs + 1 HU executante';
END $$;

COMMIT;

-- Verificação BLOCO A:
SELECT cnes_code, nome, municipio, uf, tipo, ativo FROM ubs
WHERE cnes_code LIKE '9999%'
ORDER BY tipo DESC, nome;
-- Esperado: 5 linhas (tipo='S'=4 ESFs, tipo='R'=1 HU)


-- ════════════════════════════════════════════════════════════
--  BLOCO B — Equipamentos (agendas médicas no HU)
--
--  2 agendas ortopédicas para mostrar produção por consultório
--  nos KPIs de ocupação e no ranking do AssistenteIA.
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  v_hu_id  uuid;
  v_tipo_r equipment.tipo_recurso%TYPE;
  v_tipo_a equipment.tipo_atendimento%TYPE;
  v_eq1    uuid;
  v_eq2    uuid;
BEGIN
  SELECT id INTO v_hu_id FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia' LIMIT 1;
  IF v_hu_id IS NULL THEN
    RAISE EXCEPTION 'HU não encontrado. Execute o BLOCO A primeiro.';
  END IF;

  -- Copia os ENUMs de um equipment ativo existente para garantir compatibilidade
  SELECT tipo_recurso, tipo_atendimento
    INTO v_tipo_r, v_tipo_a
    FROM equipment WHERE status = 'ativo' LIMIT 1;

  IF v_tipo_r IS NULL THEN
    RAISE EXCEPTION 'Nenhum equipment ativo para referenciar ENUMs. '
                    'Verifique se o seed original foi aplicado.';
  END IF;

  -- Ortopedia e Traumatologia — manhã — 8 consultas/dia
  SELECT id INTO v_eq1 FROM equipment
  WHERE ubs_id = v_hu_id AND nome = 'Ortopedia — Consultório Manhã' LIMIT 1;
  IF v_eq1 IS NULL THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_hu_id,
            'Ortopedia — Consultório Manhã', v_tipo_r, v_tipo_a, 'manha', 8, 'ativo')
    RETURNING id INTO v_eq1;
    RAISE NOTICE 'Criado: Ortopedia — Consultório Manhã (%)', v_eq1;
  ELSE
    RAISE NOTICE 'Já existe: Ortopedia — Consultório Manhã (%)', v_eq1;
  END IF;

  -- Traumatologia — tarde — 6 consultas/dia
  SELECT id INTO v_eq2 FROM equipment
  WHERE ubs_id = v_hu_id AND nome = 'Traumatologia — Consultório Tarde' LIMIT 1;
  IF v_eq2 IS NULL THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_hu_id,
            'Traumatologia — Consultório Tarde', v_tipo_r, v_tipo_a, 'tarde', 6, 'ativo')
    RETURNING id INTO v_eq2;
    RAISE NOTICE 'Criado: Traumatologia — Consultório Tarde (%)', v_eq2;
  ELSE
    RAISE NOTICE 'Já existe: Traumatologia — Consultório Tarde (%)', v_eq2;
  END IF;

  RAISE NOTICE '✅ BLOCO B — 2 agendas (cap. total 14 consultas/dia)';
END $$;

COMMIT;

-- Verificação BLOCO B:
SELECT eq.nome, eq.turno, eq.capacidade_dia
FROM equipment eq JOIN ubs u ON u.id = eq.ubs_id
WHERE u.nome = 'HU Clemente de Faria — Ortopedia';
-- Esperado: 2 linhas


-- ════════════════════════════════════════════════════════════
--  BLOCO C — 20 pacientes da Regional Independência
--
--  CNS prefixo 800001 (não colide com seed existente).
--  Distribuídos entre os 4 bairros principais da regional.
--  ON CONFLICT (cns) DO NOTHING — idempotente.
-- ════════════════════════════════════════════════════════════

BEGIN;

-- ── Bairro Independência / Santos Dumont (ESF Ônix) ─────────────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source)
VALUES
  ('800001000010001', 'José Augusto Carneiro',       'Montes Claros', 'MG', '38991230001', 'seed_demo'),
  ('800001000010002', 'Maria das Graças Oliveira',   'Montes Claros', 'MG', '38991230002', 'seed_demo'),
  ('800001000010003', 'Paulo Henrique Alves',        'Montes Claros', 'MG', '38991230003', 'seed_demo'),
  ('800001000010004', 'Ana Paula Ferreira Santos',   'Montes Claros', 'MG', '38991230004', 'seed_demo'),
  ('800001000010005', 'Antônio Pereira da Silva',    'Montes Claros', 'MG', '38991230005', 'seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── Bairro Ibituruna / Melo (ESF Coral — Ibituruna) ─────────────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source)
VALUES
  ('800001000010006', 'Rosângela Aparecida Dias',    'Montes Claros', 'MG', '38991230006', 'seed_demo'),
  ('800001000010007', 'Francisco das Chagas Rocha',  'Montes Claros', 'MG', '38991230007', 'seed_demo'),
  ('800001000010008', 'Benedita Maria Costa',        'Montes Claros', 'MG', '38991230008', 'seed_demo'),
  ('800001000010009', 'Geraldo Ferreira Nunes',      'Montes Claros', 'MG', '38991230009', 'seed_demo'),
  ('800001000010010', 'Luíza Helena Mendes',         'Montes Claros', 'MG', '38991230010', 'seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── Bairro Santos Reis / Vila São Francisco (ESF Santos Reis) ────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source)
VALUES
  ('800001000010011', 'Roberto Carlos da Silva',     'Montes Claros', 'MG', '38991230011', 'seed_demo'),
  ('800001000010012', 'Valdir José Teixeira',        'Montes Claros', 'MG', '38991230012', 'seed_demo'),
  ('800001000010013', 'Terezinha Aparecida Lima',    'Montes Claros', 'MG', '38991230013', 'seed_demo'),
  ('800001000010014', 'Edilson Moreira Campos',      'Montes Claros', 'MG', '38991230014', 'seed_demo'),
  ('800001000010015', 'Sílvio Correia Martins',      'Montes Claros', 'MG', '38991230015', 'seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── Bairro Alto Boa Vista / Vila Sion (ESF Alto Boa Vista) ──────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source)
VALUES
  ('800001000010016', 'Conceição Ferreira Ramos',    'Montes Claros', 'MG', '38991230016', 'seed_demo'),
  ('800001000010017', 'Sebastião Rodrigues Pinto',   'Montes Claros', 'MG', '38991230017', 'seed_demo'),
  ('800001000010018', 'Irene Batista dos Santos',    'Montes Claros', 'MG', '38991230018', 'seed_demo'),
  ('800001000010019', 'Adilson Gomes Barbosa',       'Montes Claros', 'MG', '38991230019', 'seed_demo'),
  ('800001000010020', 'Marlene Sousa Carvalho',      'Montes Claros', 'MG', '38991230020', 'seed_demo')
ON CONFLICT (cns) DO NOTHING;

COMMIT;

-- Verificação BLOCO C:
SELECT cns, nome FROM patients WHERE cns LIKE '800001%' ORDER BY cns;
-- Esperado: 20 linhas


-- ════════════════════════════════════════════════════════════
--  BLOCO D — Histórico de atendimentos (KPIs de absenteísmo)
--
--  8 pacientes com appointments passados — base dos KPIs.
--  5 realizados + 3 faltou = 37,5% absenteísmo
--  (>meta de 20% → narrativa "problema que o sistema resolve")
--
--  Pacientes: p001–p008 (José, Maria, Paulo, Ana, Antônio, Rosângela,
--             Francisco, Benedita)
--
--  Procedimentos variados do SUS (refletem casos reais ortopédicos):
--    Consulta de Ortopedia e Traumatologia
--    Avaliação Ortopédica — Joelho
--    Avaliação Ortopédica — Coluna Vertebral
-- ════════════════════════════════════════════════════════════

BEGIN;

-- Remove histórico anterior deste seed (idempotente)
DO $$
DECLARE v_ids uuid[];
BEGIN
  SELECT ARRAY_AGG(qe.id) INTO v_ids
  FROM queue_entries qe
  WHERE qe.data_source = 'seed_demo'
    AND qe.status_local IN ('realizado', 'faltou');
  IF v_ids IS NOT NULL THEN
    DELETE FROM appointments WHERE queue_entry_id = ANY(v_ids);
    DELETE FROM queue_entries   WHERE id           = ANY(v_ids);
  END IF;
END $$;

DO $$
DECLARE
  v_hu   uuid; v_eq1  uuid; v_eq2  uuid;
  v_esf1 uuid; v_esf2 uuid; v_esf3 uuid; v_esf4 uuid;
  p01 uuid; p02 uuid; p03 uuid; p04 uuid;
  p05 uuid; p06 uuid; p07 uuid; p08 uuid;
  qe  uuid;

  -- Copiar tipo_atendimento e tipo_vaga de um registro existente
  v_ta queue_entries.tipo_atendimento%TYPE;
  v_tv queue_entries.tipo_vaga%TYPE;
  v_tr queue_entries.tipo_regulacao%TYPE;
BEGIN
  SELECT id INTO v_hu   FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia' LIMIT 1;
  SELECT id INTO v_esf1 FROM ubs WHERE nome = 'ESF Ônix'              LIMIT 1;
  SELECT id INTO v_esf2 FROM ubs WHERE nome = 'ESF Coral — Ibituruna' LIMIT 1;
  SELECT id INTO v_esf3 FROM ubs WHERE nome = 'ESF Santos Reis'        LIMIT 1;
  SELECT id INTO v_esf4 FROM ubs WHERE nome = 'ESF Alto Boa Vista'     LIMIT 1;
  SELECT id INTO v_eq1 FROM equipment WHERE ubs_id = v_hu AND nome LIKE '%Manhã%' LIMIT 1;
  SELECT id INTO v_eq2 FROM equipment WHERE ubs_id = v_hu AND nome LIKE '%Tarde%' LIMIT 1;

  IF v_eq1 IS NULL OR v_eq2 IS NULL THEN
    RAISE EXCEPTION 'Agendas não encontradas. Execute os BLOCOs A e B primeiro.';
  END IF;

  -- Pega os tipos enum de um registro real para garantir compatibilidade
  SELECT tipo_atendimento, tipo_vaga, tipo_regulacao
    INTO v_ta, v_tv, v_tr
    FROM queue_entries LIMIT 1;

  -- Fallback para caso não haja queue_entries — usa 'consulta','primeira_vez','fila_espera'
  -- (valores confirmados como válidos no banco em 2026-04-19)
  IF v_ta IS NULL THEN v_ta := 'consulta';     END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- Pacientes
  SELECT id INTO p01 FROM patients WHERE cns = '800001000010001';
  SELECT id INTO p02 FROM patients WHERE cns = '800001000010002';
  SELECT id INTO p03 FROM patients WHERE cns = '800001000010003';
  SELECT id INTO p04 FROM patients WHERE cns = '800001000010004';
  SELECT id INTO p05 FROM patients WHERE cns = '800001000010005';
  SELECT id INTO p06 FROM patients WHERE cns = '800001000010006';
  SELECT id INTO p07 FROM patients WHERE cns = '800001000010007';
  SELECT id INTO p08 FROM patients WHERE cns = '800001000010008';

  IF p01 IS NULL THEN
    RAISE EXCEPTION 'Pacientes não encontrados. Execute o BLOCO C primeiro.';
  END IF;

  -- ══ REALIZADOS (5 pacientes — compareceram) ══════════════════════════════

  -- José Augusto — Consulta de Ortopedia e Traumatologia — 35 dias atrás
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p01, v_esf1, 2, v_tr, v_tv, v_ta,
    'Consulta de Ortopedia e Traumatologia', 'realizado', now() - INTERVAL '90 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() - INTERVAL '35 days', v_tv, 'realizado', 1, 'seed_demo');

  -- Maria das Graças — Avaliação Ortopédica — Joelho — 28 dias atrás
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p02, v_esf1, 3, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Joelho', 'realizado', now() - INTERVAL '80 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() - INTERVAL '28 days', v_tv, 'realizado', 1, 'seed_demo');

  -- Paulo Henrique — Avaliação Ortopédica — Coluna Vertebral — 20 dias atrás
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p03, v_esf1, 4, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Coluna Vertebral', 'realizado', now() - INTERVAL '75 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() - INTERVAL '20 days', v_tv, 'realizado', 1, 'seed_demo');

  -- Antônio Pereira — Avaliação Ortopédica — Quadril — 12 dias atrás
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p05, v_esf2, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Quadril', 'realizado', now() - INTERVAL '70 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() - INTERVAL '12 days', v_tv, 'realizado', 1, 'seed_demo');

  -- Rosângela Dias — Avaliação Ortopédica — Ombro — 6 dias atrás
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p06, v_esf2, 3, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Ombro', 'realizado', now() - INTERVAL '65 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() - INTERVAL '6 days', v_tv, 'realizado', 1, 'seed_demo');

  -- ══ FALTOU (3 pacientes — não compareceram) ══════════════════════════════
  -- st_falta_registrada=1 conta no KPI calcular_absenteismo()

  -- Ana Paula — faltou há 25 dias
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p04, v_esf1, 3, v_tr, v_tv, v_ta,
    'Consulta de Ortopedia e Traumatologia', 'faltou', now() - INTERVAL '85 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, st_falta_registrada, data_source)
  VALUES (qe, v_eq2, now() - INTERVAL '25 days', v_tv, 'faltou', 1, 1, 'seed_demo');

  -- Francisco das Chagas — faltou há 16 dias
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p07, v_esf2, 4, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Joelho', 'faltou', now() - INTERVAL '78 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, st_falta_registrada, data_source)
  VALUES (qe, v_eq1, now() - INTERVAL '16 days', v_tv, 'faltou', 1, 1, 'seed_demo');

  -- Benedita Costa — faltou há 10 dias
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p08, v_esf3, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Coluna Vertebral', 'faltou', now() - INTERVAL '72 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, st_falta_registrada, data_source)
  VALUES (qe, v_eq2, now() - INTERVAL '10 days', v_tv, 'faltou', 1, 1, 'seed_demo');

  RAISE NOTICE '✅ BLOCO D — 5 realizados + 3 faltou (37,5%% absenteísmo histórico)';
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO E — Fila de espera (backlog aguardando regulação)
--
--  8 pacientes aguardando vaga — mostram o problema de backlog
--  da regional. Prioridades mistas para demo FIFO:
--    Prioridade 1 (vermelho/urgência): 2 pacientes
--    Prioridade 2 (amarelo/prioridade): 3 pacientes
--    Prioridade 3 (verde): 2 pacientes
--    Prioridade 4 (azul/rotina): 1 paciente
--
--  Orden FIFO de convocação (o que o RPC selecionará):
--    1º Geraldo Nunes      (prio=1, 55 dias)
--    2º Roberto Carlos     (prio=1, 42 dias)
--    3º Valdir Teixeira    (prio=2, 68 dias — mais antigo na prio 2)
--    4º Terezinha Lima     (prio=2, 50 dias)
--    5º Edilson Campos     (prio=2, 38 dias)
--    6º Sílvio Correia     (prio=3, 60 dias)
--    7º Conceição Ramos    (prio=3, 45 dias)
--    8º Sebastião Pinto    (prio=4, 120 dias — rotina, aguarda mais)
-- ════════════════════════════════════════════════════════════

BEGIN;

-- Remove fila anterior deste seed (idempotente)
DELETE FROM queue_entries
WHERE data_source = 'seed_demo' AND status_local = 'aguardando';

DO $$
DECLARE
  v_esf1 uuid; v_esf2 uuid; v_esf3 uuid; v_esf4 uuid;
  p09 uuid; p10 uuid; p11 uuid; p12 uuid;
  p13 uuid; p14 uuid; p15 uuid; p16 uuid;
  p17 uuid;
  v_ta queue_entries.tipo_atendimento%TYPE;
  v_tv queue_entries.tipo_vaga%TYPE;
  v_tr queue_entries.tipo_regulacao%TYPE;
BEGIN
  SELECT id INTO v_esf1 FROM ubs WHERE nome = 'ESF Ônix'              LIMIT 1;
  SELECT id INTO v_esf2 FROM ubs WHERE nome = 'ESF Coral — Ibituruna' LIMIT 1;
  SELECT id INTO v_esf3 FROM ubs WHERE nome = 'ESF Santos Reis'        LIMIT 1;
  SELECT id INTO v_esf4 FROM ubs WHERE nome = 'ESF Alto Boa Vista'     LIMIT 1;

  SELECT tipo_atendimento, tipo_vaga, tipo_regulacao
    INTO v_ta, v_tv, v_tr
    FROM queue_entries LIMIT 1;

  IF v_ta IS NULL THEN v_ta := 'consulta';     END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  SELECT id INTO p09 FROM patients WHERE cns = '800001000010009';  -- Geraldo
  SELECT id INTO p10 FROM patients WHERE cns = '800001000010010';  -- Luíza Helena
  SELECT id INTO p11 FROM patients WHERE cns = '800001000010011';  -- Roberto Carlos
  SELECT id INTO p12 FROM patients WHERE cns = '800001000010012';  -- Valdir
  SELECT id INTO p13 FROM patients WHERE cns = '800001000010013';  -- Terezinha
  SELECT id INTO p14 FROM patients WHERE cns = '800001000010014';  -- Edilson
  SELECT id INTO p15 FROM patients WHERE cns = '800001000010015';  -- Sílvio
  SELECT id INTO p16 FROM patients WHERE cns = '800001000010016';  -- Conceição
  SELECT id INTO p17 FROM patients WHERE cns = '800001000010017';  -- Sebastião

  IF p09 IS NULL THEN
    RAISE EXCEPTION 'Pacientes não encontrados. Execute o BLOCO C primeiro.';
  END IF;

  -- ── Urgência (prioridade 1 — vermelho) ──────────────────────────────────

  -- Geraldo Nunes — gonalgia aguda traumática, aguarda 55 dias → 1º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p09, v_esf2, 1, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Joelho', 'aguardando', now() - INTERVAL '55 days', 'seed_demo');

  -- Roberto Carlos — fratura clavícula (consolidada, dor persistente), 42 dias → 2º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p11, v_esf3, 1, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Ombro', 'aguardando', now() - INTERVAL '42 days', 'seed_demo');

  -- ── Prioridade (prioridade 2 — amarelo) ────────────────────────────────

  -- Valdir Teixeira — artrose grau II, 68 dias de espera → 3º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p12, v_esf3, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Joelho', 'aguardando', now() - INTERVAL '68 days', 'seed_demo');

  -- Luíza Helena — hérnia de disco L4-L5, 50 dias → 4º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p10, v_esf2, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Coluna Vertebral', 'aguardando', now() - INTERVAL '50 days', 'seed_demo');

  -- Edilson Campos — gonartrose bilateral, 38 dias → 5º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p14, v_esf4, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Quadril', 'aguardando', now() - INTERVAL '38 days', 'seed_demo');

  -- ── Verde (prioridade 3) ────────────────────────────────────────────────

  -- Sílvio Correia — tendinite calcificada, 60 dias → 6º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p15, v_esf4, 3, v_tr, v_tv, v_ta,
    'Consulta de Ortopedia e Traumatologia', 'aguardando', now() - INTERVAL '60 days', 'seed_demo');

  -- Conceição Ramos — artralgia crônica, 45 dias → 7º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p16, v_esf4, 3, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Ombro', 'aguardando', now() - INTERVAL '45 days', 'seed_demo');

  -- ── Rotina (prioridade 4 — azul) ───────────────────────────────────────

  -- Sebastião Pinto — escoliose leve, aguarda 120 dias (rotina) → 8º FIFO
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p17, v_esf3, 4, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Coluna Vertebral', 'aguardando', now() - INTERVAL '120 days', 'seed_demo');

  RAISE NOTICE '✅ BLOCO E — 8 pacientes na fila (2 urgência + 3 prioridade + 2 verde + 1 rotina)';
END $$;

COMMIT;

-- Verificação BLOCO E — ordem FIFO para narração:
SELECT
  ROW_NUMBER() OVER (ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg) AS posicao,
  p.nome,
  qe.prioridade_codigo  AS prio,
  EXTRACT(DAY FROM now() - qe.data_solicitacao_sisreg)::int                    AS dias_espera,
  qe.nome_grupo_procedimento                                                    AS procedimento,
  u.nome                                                                        AS ubs_origem
FROM queue_entries qe
JOIN patients p ON p.id = qe.patient_id
JOIN ubs u      ON u.id = qe.ubs_id
WHERE qe.data_source = 'seed_demo' AND qe.status_local = 'aguardando'
ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg;
-- Narração demo: "Se cancelar uma vaga, o sistema convoca automaticamente o posicao=1"


-- ════════════════════════════════════════════════════════════
--  BLOCO F — Pipeline completo de notificações
--
--  DEMO NARRATIVA (Board 1 → Board 2 → Board 3):
--
--  Board 1 — "Pendente de notificação" (4 pacientes):
--    Irene, Adilson, Marlene, Sílvio Correia
--    appointments futuros (próximas 48h), st_paciente_avisado=NULL
--    → precisa enviar WhatsApp agora
--
--  Board 2 — "Aguardando confirmação" (3 pacientes):
--    Terezinha, Luíza Helena, Roberto Carlos
--    notification_log sem resposta → enviou WhatsApp, ainda sem retorno
--
--  Board 3 — "Histórico" (3 pacientes):
--    Valdir: confirmou presença ✅
--    Conceição: confirmou presença ✅
--    Edilson: cancelou ❌ → vaga liberada para FIFO
--      (o FIFO convoca Geraldo Nunes: prio=1, 55 dias de espera)
--
--  Idempotente: remove appointments futuros seed_demo antes de reinserir.
-- ════════════════════════════════════════════════════════════

BEGIN;

-- Remove appointments futuros deste seed (idempotente)
DO $$
DECLARE v_ids uuid[];
BEGIN
  SELECT ARRAY_AGG(qe.id) INTO v_ids
  FROM queue_entries qe
  WHERE qe.data_source = 'seed_demo'
    AND qe.status_local IN ('agendado', 'confirmado', 'cancelado');
  IF v_ids IS NOT NULL THEN
    DELETE FROM notification_log WHERE appointment_id IN (
      SELECT a.id FROM appointments a WHERE a.queue_entry_id = ANY(v_ids)
    );
    -- Remove TODOS os appointments (não só futuros) antes de deletar queue_entries
    -- para evitar violação de FK quando o bloco é re-executado após falha parcial.
    DELETE FROM appointments WHERE queue_entry_id = ANY(v_ids);
    DELETE FROM queue_entries   WHERE id = ANY(v_ids);
  END IF;
END $$;

DO $$
DECLARE
  v_hu   uuid; v_eq1  uuid; v_eq2  uuid;
  v_esf1 uuid; v_esf2 uuid; v_esf3 uuid; v_esf4 uuid;
  -- Board 1: pendentes de notificação
  p18 uuid; p19 uuid; p20 uuid;
  p15 uuid;  -- Sílvio — já na fila aguardando, promove aqui
  -- Board 2: notificados sem resposta
  p13 uuid; p10 uuid; p11 uuid;
  -- Board 3: com resposta (confirmou / cancelou)
  p12 uuid; p16 uuid; p14 uuid;
  -- FIFO: Geraldo (1º da fila) — convocado após cancelamento de Edilson
  p09 uuid;
  qe  uuid; appt uuid;
  v_ta queue_entries.tipo_atendimento%TYPE;
  v_tv queue_entries.tipo_vaga%TYPE;
  v_tr queue_entries.tipo_regulacao%TYPE;
BEGIN
  SELECT id INTO v_hu   FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia' LIMIT 1;
  SELECT id INTO v_esf1 FROM ubs WHERE nome = 'ESF Ônix'              LIMIT 1;
  SELECT id INTO v_esf2 FROM ubs WHERE nome = 'ESF Coral — Ibituruna' LIMIT 1;
  SELECT id INTO v_esf3 FROM ubs WHERE nome = 'ESF Santos Reis'        LIMIT 1;
  SELECT id INTO v_esf4 FROM ubs WHERE nome = 'ESF Alto Boa Vista'     LIMIT 1;
  SELECT id INTO v_eq1 FROM equipment WHERE ubs_id = v_hu AND nome LIKE '%Manhã%' LIMIT 1;
  SELECT id INTO v_eq2 FROM equipment WHERE ubs_id = v_hu AND nome LIKE '%Tarde%' LIMIT 1;

  SELECT tipo_atendimento, tipo_vaga, tipo_regulacao
    INTO v_ta, v_tv, v_tr FROM queue_entries LIMIT 1;
  IF v_ta IS NULL THEN v_ta := 'consulta';     END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- Pacientes
  SELECT id INTO p18 FROM patients WHERE cns = '800001000010018'; -- Irene
  SELECT id INTO p19 FROM patients WHERE cns = '800001000010019'; -- Adilson
  SELECT id INTO p20 FROM patients WHERE cns = '800001000010020'; -- Marlene
  SELECT id INTO p15 FROM patients WHERE cns = '800001000010015'; -- Sílvio
  SELECT id INTO p10 FROM patients WHERE cns = '800001000010010'; -- Luíza Helena
  SELECT id INTO p11 FROM patients WHERE cns = '800001000010011'; -- Roberto Carlos
  SELECT id INTO p12 FROM patients WHERE cns = '800001000010012'; -- Valdir
  SELECT id INTO p13 FROM patients WHERE cns = '800001000010013'; -- Terezinha
  SELECT id INTO p14 FROM patients WHERE cns = '800001000010014'; -- Edilson
  SELECT id INTO p16 FROM patients WHERE cns = '800001000010016'; -- Conceição
  SELECT id INTO p09 FROM patients WHERE cns = '800001000010009'; -- Geraldo (FIFO)

  IF p18 IS NULL OR p09 IS NULL THEN
    RAISE EXCEPTION 'Pacientes não encontrados. Execute o BLOCO C primeiro.';
  END IF;

  -- ════════════════════════════════════════════════════════
  --  BOARD 1 — Pendente de notificação (4 pacientes)
  --  st_paciente_avisado IS NULL → aparecem no Board 1
  -- ════════════════════════════════════════════════════════

  -- Irene Batista — Consultório Manhã — daqui 6h
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p18, v_esf3, 3, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Ombro', 'agendado', now() - INTERVAL '45 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() + INTERVAL '6 hours', v_tv, 'agendado', NULL, 'seed_demo');

  -- Adilson Gomes — Consultório Tarde — daqui 10h
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p19, v_esf4, 2, v_tr, v_tv, v_ta,
    'Consulta de Ortopedia e Traumatologia', 'agendado', now() - INTERVAL '38 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() + INTERVAL '10 hours', v_tv, 'agendado', NULL, 'seed_demo');

  -- Marlene Carvalho — Consultório Manhã — amanhã cedo (daqui 22h)
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p20, v_esf4, 4, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Quadril', 'agendado', now() - INTERVAL '32 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() + INTERVAL '22 hours', v_tv, 'agendado', NULL, 'seed_demo');

  -- Sílvio Correia — Consultório Tarde — amanhã tarde (daqui 30h)
  -- Nota: Sílvio estava na fila aguardando (BLOCO E). Aqui ele já recebeu uma vaga.
  -- Para evitar duplicata: usamos um patient que ainda não tem qe ativa.
  -- Sílvio já tem qe 'aguardando' então criamos nova qe para o appointment.
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p15, v_esf4, 3, v_tr, v_tv, v_ta,
    'Consulta de Ortopedia e Traumatologia', 'agendado', now() - INTERVAL '60 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() + INTERVAL '30 hours', v_tv, 'agendado', NULL, 'seed_demo');

  -- ════════════════════════════════════════════════════════
  --  BOARD 2 — Aguardando confirmação (3 pacientes)
  --  notification_log enviado, sem resposta_paciente
  -- ════════════════════════════════════════════════════════

  -- Terezinha Lima — notificada há 90min, sem resposta
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p13, v_esf4, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Coluna Vertebral', 'agendado', now() - INTERVAL '50 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() + INTERVAL '14 hours', v_tv, 'agendado', 1, 'seed_demo')
  RETURNING id INTO appt;
  INSERT INTO notification_log (patient_id, appointment_id, tipo, canal, mensagem,
    telefone_destino, enviado_at, entregue, data_source)
  VALUES (p13, appt, 'lembrete_manual', 'whatsapp',
    'Olá Terezinha! Você tem consulta de Ortopedia amanhã no HU Clemente de Faria. '
    'Confirme sua presença respondendo 1 ou cancele respondendo 2.',
    '38991230013', now() - INTERVAL '90 minutes', true, 'seed_demo');

  -- Luíza Helena Mendes — notificada há 45min, sem resposta
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p10, v_esf2, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Joelho', 'agendado', now() - INTERVAL '50 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() + INTERVAL '18 hours', v_tv, 'agendado', 1, 'seed_demo')
  RETURNING id INTO appt;
  INSERT INTO notification_log (patient_id, appointment_id, tipo, canal, mensagem,
    telefone_destino, enviado_at, entregue, data_source)
  VALUES (p10, appt, 'lembrete_manual', 'whatsapp',
    'Olá Luíza! Você tem consulta de Ortopedia amanhã no HU Clemente de Faria. '
    'Confirme sua presença respondendo 1 ou cancele respondendo 2.',
    '38991230010', now() - INTERVAL '45 minutes', true, 'seed_demo');

  -- Roberto Carlos da Silva — notificado há 20min, sem resposta
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p11, v_esf3, 1, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Ombro', 'agendado', now() - INTERVAL '42 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() + INTERVAL '20 hours', v_tv, 'agendado', 1, 'seed_demo')
  RETURNING id INTO appt;
  INSERT INTO notification_log (patient_id, appointment_id, tipo, canal, mensagem,
    telefone_destino, enviado_at, entregue, data_source)
  VALUES (p11, appt, 'lembrete_manual', 'whatsapp',
    'Olá Roberto! Você tem consulta de Ortopedia amanhã no HU Clemente de Faria. '
    'Confirme sua presença respondendo 1 ou cancele respondendo 2.',
    '38991230011', now() - INTERVAL '20 minutes', true, 'seed_demo');

  -- ════════════════════════════════════════════════════════
  --  BOARD 3 — Histórico (3 pacientes com resposta)
  --  2 confirmaram + 1 cancelou → FIFO convocou Geraldo
  -- ════════════════════════════════════════════════════════

  -- Valdir José Teixeira — CONFIRMOU presença ✅
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p12, v_esf3, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Joelho', 'confirmado', now() - INTERVAL '68 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() + INTERVAL '26 hours', v_tv, 'confirmado', 1, 'seed_demo')
  RETURNING id INTO appt;
  INSERT INTO notification_log (patient_id, appointment_id, tipo, canal, mensagem,
    telefone_destino, enviado_at, respondido_at, resposta_paciente, entregue, data_source)
  VALUES (p12, appt, 'lembrete_manual', 'whatsapp',
    'Olá Valdir! Você tem consulta de Ortopedia amanhã no HU Clemente de Faria. '
    'Confirme sua presença respondendo 1 ou cancele respondendo 2.',
    '38991230012',
    now() - INTERVAL '4 hours', now() - INTERVAL '3 hours 30 minutes',
    'confirmou', true, 'seed_demo');

  -- Conceição Ferreira Ramos — CONFIRMOU presença ✅
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p16, v_esf4, 3, v_tr, v_tv, v_ta,
    'Consulta de Ortopedia e Traumatologia', 'confirmado', now() - INTERVAL '45 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq1, now() + INTERVAL '36 hours', v_tv, 'confirmado', 1, 'seed_demo')
  RETURNING id INTO appt;
  INSERT INTO notification_log (patient_id, appointment_id, tipo, canal, mensagem,
    telefone_destino, enviado_at, respondido_at, resposta_paciente, entregue, data_source)
  VALUES (p16, appt, 'lembrete_manual', 'whatsapp',
    'Olá Conceição! Você tem consulta de Ortopedia amanhã no HU Clemente de Faria. '
    'Confirme sua presença respondendo 1 ou cancele respondendo 2.',
    '38991230016',
    now() - INTERVAL '6 hours', now() - INTERVAL '5 hours 45 minutes',
    'confirmou', true, 'seed_demo');

  -- Edilson Moreira Campos — CANCELOU ❌
  -- Vaga cancelada → FIFO convoca Geraldo Nunes (prio=1, 55 dias de espera)
  INSERT INTO queue_entries (patient_id, ubs_id, prioridade_codigo, tipo_regulacao, tipo_vaga,
    tipo_atendimento, nome_grupo_procedimento, status_local, data_solicitacao_sisreg, data_source)
  VALUES (p14, v_esf4, 2, v_tr, v_tv, v_ta,
    'Avaliação Ortopédica — Quadril', 'cancelado', now() - INTERVAL '38 days', 'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, data_source)
  VALUES (qe, v_eq2, now() + INTERVAL '12 hours', v_tv, 'cancelado', 1, 'seed_demo')
  RETURNING id INTO appt;
  INSERT INTO notification_log (patient_id, appointment_id, tipo, canal, mensagem,
    telefone_destino, enviado_at, respondido_at, resposta_paciente, entregue, data_source)
  VALUES (p14, appt, 'lembrete_manual', 'whatsapp',
    'Olá Edilson! Você tem consulta de Ortopedia amanhã no HU Clemente de Faria. '
    'Confirme sua presença respondendo 1 ou cancele respondendo 2.',
    '38991230014',
    now() - INTERVAL '3 hours', now() - INTERVAL '2 hours 40 minutes',
    'cancelou', true, 'seed_demo');

  -- ════════════════════════════════════════════════════════
  --  FIFO: Geraldo Nunes convocado após cancelamento de Edilson
  --  Cria novo appointment para Geraldo no horário liberado pelo Edilson.
  --  reaproveitado_de_id → aponta para o appointment de Edilson → alimenta KPI.
  -- ════════════════════════════════════════════════════════

  -- Promoção de Geraldo na fila: aguardando → agendado
  UPDATE queue_entries
     SET status_local = 'agendado'
   WHERE patient_id = p09
     AND status_local = 'aguardando'
     AND data_source = 'seed_demo';

  -- Novo appointment para Geraldo no slot liberado (mesmo horário de Edilson)
  INSERT INTO appointments (queue_entry_id, equipment_id, scheduled_at, tipo_vaga, status,
    st_paciente_avisado, reaproveitado_de_id, data_source)
  SELECT qe.id, v_eq2, now() + INTERVAL '12 hours', v_tv, 'agendado', NULL, appt, 'seed_demo'
    FROM queue_entries qe
   WHERE qe.patient_id = p09 AND qe.status_local = 'agendado' AND qe.data_source = 'seed_demo'
  LIMIT 1;

  RAISE NOTICE '✅ BLOCO F — Board 1: 4 pendentes | Board 2: 3 aguardando | Board 3: 2 confirmados + 1 cancelado + FIFO Geraldo convocado';
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO G — VERIFICAÇÃO FINAL
-- ════════════════════════════════════════════════════════════

-- 1. UBSs
SELECT 'UBSs criadas' AS secao, COUNT(*) AS total
FROM ubs WHERE cnes_code LIKE '9999%';
-- Esperado: 10 (5 do seed anterior + 5 da Regional Independência)

-- 2. Equipamentos
SELECT 'Agendas ortopédicas' AS secao, COUNT(*) AS total
FROM equipment eq JOIN ubs u ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%';
-- Esperado: total varia (2 novas + equipamentos do seed anterior com prefixo 9999)

-- 3. Pacientes
SELECT 'Pacientes seed' AS secao, COUNT(*) AS total
FROM patients WHERE cns LIKE '800001%';
-- Esperado: 20

-- 4. Distribuição de status da fila
SELECT qe.status_local, COUNT(*) AS total
FROM queue_entries qe
JOIN patients p ON p.id = qe.patient_id
WHERE p.cns LIKE '800001%'
GROUP BY qe.status_local ORDER BY qe.status_local;
-- Esperado:
--   agendado  : 8  (4 brd1 + 3 brd2 + 1 fifo Geraldo)
--   aguardando: 7  (8 inseridos - 1 Geraldo promovido para agendado)
--   cancelado : 1  (Edilson)
--   confirmado: 2  (Valdir + Conceição)
--   faltou    : 3  (KPI histórico)
--   realizado : 5  (KPI histórico)

-- 5. Pipeline de notificações (os 3 boards)
SELECT
  CASE
    WHEN nl.resposta_paciente IS NOT NULL THEN 'Board 3 — Histórico'
    WHEN nl.id IS NOT NULL                THEN 'Board 2 — Aguardando confirmação'
    ELSE                                       'Board 1 — Pendente notificação'
  END                           AS board,
  COUNT(DISTINCT a.id)          AS appointments
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
JOIN patients p       ON p.id  = qe.patient_id
LEFT JOIN notification_log nl ON nl.appointment_id = a.id
WHERE p.cns LIKE '800001%'
  AND a.scheduled_at > now()
  AND a.status IN ('agendado', 'confirmado', 'cancelado')
GROUP BY 1 ORDER BY 1;
-- Esperado:
--   Board 1 — Pendente notificação    : 5 (4 sem notification_log + Geraldo sem aviso)
--   Board 2 — Aguardando confirmação  : 3
--   Board 3 — Histórico               : 3

-- 6. KPI de absenteísmo historical
SELECT
  COUNT(*) FILTER (WHERE a.status = 'faltou')                           AS faltas,
  COUNT(*) FILTER (WHERE a.status IN ('realizado','faltou'))             AS total_finalizados,
  ROUND(
    COUNT(*) FILTER (WHERE a.status = 'faltou')::numeric
    / NULLIF(COUNT(*) FILTER (WHERE a.status IN ('realizado','faltou')), 0) * 100, 1
  )                                                                      AS taxa_pct
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
JOIN patients p       ON p.id  = qe.patient_id
WHERE p.cns LIKE '800001%' AND a.scheduled_at < now();
-- Esperado: faltas=3, total=8, taxa=37,5%

-- 7. Fila aguardando em ordem FIFO (narração do demo)
SELECT
  ROW_NUMBER() OVER (ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg) AS pos,
  p.nome, qe.prioridade_codigo AS prio,
  EXTRACT(DAY FROM now() - qe.data_solicitacao_sisreg)::int AS dias_espera
FROM queue_entries qe
JOIN patients p ON p.id = qe.patient_id
WHERE p.cns LIKE '800001%' AND qe.status_local = 'aguardando'
ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg;
-- Esperado: 7 linhas (Geraldo foi promovido para 'agendado' pelo FIFO — não aparece mais na fila)
