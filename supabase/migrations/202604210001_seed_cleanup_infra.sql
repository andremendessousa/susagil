-- ============================================================
-- SUS RAIO-X — Migration 202604210001
-- Seed: Cleanup Seguro + Infraestrutura (UBSs + Equipment)
-- Data: 2026-04-21
-- Referência: Edital CPSI 004/2026
--
-- PROPÓSITO: Limpar dados do seed anterior (scoped, seguro) e
-- recriar toda a infraestrutura de UBSs e equipment para o demo.
--
-- ESCOPO REGIONAL INDEPENDÊNCIA:
--   UBS_REGIONAL_INDEPENDENCIA = ['Independência II'] (1 UBS)
--   Todos os hospitais/clínicas atendem pacientes de qualquer UBS.
--
-- Execute ANTES de 202604210002 e 202604210003.
-- ============================================================

-- ════════════════════════════════════════════════════════════
--  BLOCO 0 — Cleanup seguro (scoped por CNS e CNES prefixo)
--
--  NUNCA usa DELETE global por data_source.
--  Ordem: notification_log → appointments → queue_entries
--         → patients → equipment → ubs
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE v_ids uuid[];
BEGIN
  -- 1. notification_log: pacientes seed + appointments de equipment seed
  DELETE FROM notification_log
  WHERE patient_id IN (SELECT id FROM patients WHERE cns LIKE '800001%')
     OR appointment_id IN (
       SELECT a.id FROM appointments a
       JOIN equipment eq ON eq.id = a.equipment_id
       JOIN ubs u ON u.id = eq.ubs_id
       WHERE u.cnes_code LIKE '9999%'
     );
  RAISE NOTICE 'notification_log limpo';

  -- 2a. appointments via queue_entries de pacientes seed
  SELECT ARRAY_AGG(qe.id) INTO v_ids
  FROM queue_entries qe
  JOIN patients p ON p.id = qe.patient_id
  WHERE p.cns LIKE '800001%';
  IF v_ids IS NOT NULL THEN
    DELETE FROM appointments WHERE queue_entry_id = ANY(v_ids);
    RAISE NOTICE 'appointments (pacientes) limpos: % queue_entries', array_length(v_ids,1);
  END IF;

  -- 2b. appointments que referenciam equipment seed diretamente (previne FK violation)
  DELETE FROM appointments
  WHERE equipment_id IN (
    SELECT eq.id FROM equipment eq
    JOIN ubs u ON u.id = eq.ubs_id
    WHERE u.cnes_code LIKE '9999%'
  );
  RAISE NOTICE 'appointments (equipment seed) limpos';

  -- 3. queue_entries de pacientes seed
  DELETE FROM queue_entries
  WHERE patient_id IN (SELECT id FROM patients WHERE cns LIKE '800001%');
  RAISE NOTICE 'queue_entries limpos';

  -- 4. patients seed (CNS prefixo 800001)
  DELETE FROM patients WHERE cns LIKE '800001%';
  RAISE NOTICE 'patients limpos';

  -- 5. equipment vinculado a UBSs seed (cnes_code prefixo 9999)
  DELETE FROM equipment
  WHERE ubs_id IN (SELECT id FROM ubs WHERE cnes_code LIKE '9999%');
  RAISE NOTICE 'equipment limpo';

  -- 6. UBSs seed (cnes_code prefixo 9999)
  DELETE FROM ubs WHERE cnes_code LIKE '9999%';
  RAISE NOTICE 'ubs limpas';

  RAISE NOTICE '✅ BLOCO 0 — Cleanup seguro concluído';
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO A — UBSs solicitantes + executantes + equipment
--
--  14 UBSs solicitantes (tipo='S') — 11 em Montes Claros + 3 municípios polo
--  8 UBSs executantes   (tipo='R') — realizam atendimentos
--
--  Equipment existente (IDs reais) é vinculado por lookup de nome.
--  Equipment novo (Santa Casa, Dilson Godinho, OrthoMed, Centro
--  Diagnóstico Norte) é criado aqui.
--
--  TODOS os hospitais atendem pacientes de QUALQUER UBS — sem
--  exclusividade de regional. O filtro "Regional Independência"
--  no frontend filtra apenas por ubs_id = Independência II.
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  -- UBSs solicitantes (Montes Claros)
  v_ind2   uuid; v_mar2  uuid; v_mar3  uuid; v_mar4  uuid;
  v_mp1    uuid; v_mp2   uuid; v_mp3   uuid; v_mp4   uuid;
  v_sjl3   uuid; v_cin1  uuid; v_cin2  uuid;
  -- UBSs solicitantes (municípios polo — macrorregião)
  v_boc    uuid; v_pir   uuid; v_jan   uuid;
  -- UBSs executantes
  v_aroldo uuid; v_clinicas uuid; v_hu   uuid;
  v_santa  uuid; v_dilson   uuid; v_clemente uuid;
  v_ortho  uuid; v_imagemed uuid;
  -- tipos (copiados de registro existente para garantir ENUM)
  v_tr equipment.tipo_recurso%TYPE;
  v_ta equipment.tipo_atendimento%TYPE;
  v_enum_text text;
BEGIN

  -- ── UBSs SOLICITANTES (tipo='S') ──────────────────────────────────────────

  SELECT id INTO v_ind2 FROM ubs WHERE nome = 'Independência II' LIMIT 1;
  IF v_ind2 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999201','Independência II','Montes Claros','MG','S',true)
    RETURNING id INTO v_ind2;
  END IF;
  RAISE NOTICE 'Independência II: %', v_ind2;

  SELECT id INTO v_mar2 FROM ubs WHERE nome = 'Maracanã II' LIMIT 1;
  IF v_mar2 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999202','Maracanã II','Montes Claros','MG','S',true)
    RETURNING id INTO v_mar2;
  END IF;

  SELECT id INTO v_mar3 FROM ubs WHERE nome = 'Maracanã III' LIMIT 1;
  IF v_mar3 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999203','Maracanã III','Montes Claros','MG','S',true)
    RETURNING id INTO v_mar3;
  END IF;

  SELECT id INTO v_mar4 FROM ubs WHERE nome = 'Maracanã IV' LIMIT 1;
  IF v_mar4 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999204','Maracanã IV','Montes Claros','MG','S',true)
    RETURNING id INTO v_mar4;
  END IF;

  SELECT id INTO v_mp1 FROM ubs WHERE nome = 'Major Prates I' LIMIT 1;
  IF v_mp1 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999205','Major Prates I','Montes Claros','MG','S',true)
    RETURNING id INTO v_mp1;
  END IF;

  SELECT id INTO v_mp2 FROM ubs WHERE nome = 'Major Prates II' LIMIT 1;
  IF v_mp2 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999206','Major Prates II','Montes Claros','MG','S',true)
    RETURNING id INTO v_mp2;
  END IF;

  SELECT id INTO v_mp3 FROM ubs WHERE nome = 'Major Prates III' LIMIT 1;
  IF v_mp3 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999207','Major Prates III','Montes Claros','MG','S',true)
    RETURNING id INTO v_mp3;
  END IF;

  SELECT id INTO v_mp4 FROM ubs WHERE nome = 'Major Prates IV' LIMIT 1;
  IF v_mp4 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999208','Major Prates IV','Montes Claros','MG','S',true)
    RETURNING id INTO v_mp4;
  END IF;

  SELECT id INTO v_sjl3 FROM ubs WHERE nome = 'São José e Lourdes III' LIMIT 1;
  IF v_sjl3 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999209','São José e Lourdes III','Montes Claros','MG','S',true)
    RETURNING id INTO v_sjl3;
  END IF;

  SELECT id INTO v_cin1 FROM ubs WHERE nome = 'Cintra I' LIMIT 1;
  IF v_cin1 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999210','Cintra I','Montes Claros','MG','S',true)
    RETURNING id INTO v_cin1;
  END IF;

  SELECT id INTO v_cin2 FROM ubs WHERE nome = 'Cintra II' LIMIT 1;
  IF v_cin2 IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999211','Cintra II','Montes Claros','MG','S',true)
    RETURNING id INTO v_cin2;
  END IF;

  RAISE NOTICE '✅ 11 UBSs solicitantes Montes Claros criadas';

  -- ── UBSs SOLICITANTES macrorregionais (municípios polo) ─────────────────────
  -- Necessárias para que get_fila_por_ubs, get_desempenho_por_ubs e
  -- get_espera_por_municipio retornem dados distintos no escopo Macrorregião.

  SELECT id INTO v_boc FROM ubs WHERE nome = 'UBS Bocaiúva' LIMIT 1;
  IF v_boc IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999221','UBS Bocaiúva','Bocaiúva','MG','S',true)
    RETURNING id INTO v_boc;
  END IF;

  SELECT id INTO v_pir FROM ubs WHERE nome = 'UBS Pirapora' LIMIT 1;
  IF v_pir IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999222','UBS Pirapora','Pirapora','MG','S',true)
    RETURNING id INTO v_pir;
  END IF;

  SELECT id INTO v_jan FROM ubs WHERE nome = 'UBS Janaúba' LIMIT 1;
  IF v_jan IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999223','UBS Janaúba','Janaúba','MG','S',true)
    RETURNING id INTO v_jan;
  END IF;

  RAISE NOTICE '✅ 3 UBSs macrorregionais criadas (Bocaiúva, Pirapora, Janaúba)';

  -- ── UBSs EXECUTANTES (tipo='R') ───────────────────────────────────────────

  SELECT id INTO v_aroldo FROM ubs WHERE nome = 'Hospital Aroldo Tourinho' LIMIT 1;
  IF v_aroldo IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999301','Hospital Aroldo Tourinho','Montes Claros','MG','R',true)
    RETURNING id INTO v_aroldo;
  END IF;

  SELECT id INTO v_clinicas FROM ubs WHERE nome = 'Hospital das Clínicas Dr. Mário Ribeiro' LIMIT 1;
  IF v_clinicas IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999302','Hospital das Clínicas Dr. Mário Ribeiro','Montes Claros','MG','R',true)
    RETURNING id INTO v_clinicas;
  END IF;

  SELECT id INTO v_hu FROM ubs WHERE nome = 'Hospital Universitário' LIMIT 1;
  IF v_hu IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999303','Hospital Universitário','Montes Claros','MG','R',true)
    RETURNING id INTO v_hu;
  END IF;

  SELECT id INTO v_santa FROM ubs WHERE nome = 'Santa Casa de Montes Claros' LIMIT 1;
  IF v_santa IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999304','Santa Casa de Montes Claros','Montes Claros','MG','R',true)
    RETURNING id INTO v_santa;
  END IF;

  SELECT id INTO v_dilson FROM ubs WHERE nome = 'Fundação Dilson Godinho' LIMIT 1;
  IF v_dilson IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999305','Fundação Dilson Godinho','Montes Claros','MG','R',true)
    RETURNING id INTO v_dilson;
  END IF;

  SELECT id INTO v_clemente FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia' LIMIT 1;
  IF v_clemente IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999306','HU Clemente de Faria — Ortopedia','Montes Claros','MG','R',true)
    RETURNING id INTO v_clemente;
  END IF;

  SELECT id INTO v_ortho FROM ubs WHERE nome = 'OrthoMed Clínica Especializada' LIMIT 1;
  IF v_ortho IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999307','OrthoMed Clínica Especializada','Montes Claros','MG','R',true)
    RETURNING id INTO v_ortho;
  END IF;

  SELECT id INTO v_imagemed FROM ubs WHERE nome = 'ImageMed Clinica de Imagem' LIMIT 1;
  IF v_imagemed IS NULL THEN
    INSERT INTO ubs (id, cnes_code, nome, municipio, uf, tipo, ativo)
    VALUES (gen_random_uuid(),'9999308','ImageMed Clinica de Imagem','Montes Claros','MG','R',true)
    RETURNING id INTO v_imagemed;
  END IF;

  RAISE NOTICE '✅ 8 UBSs executantes criadas';

  -- ── EQUIPMENT ─────────────────────────────────────────────────────────────
  -- Tenta copiar ENUMs de registro existente; se não houver nenhum (cleanup
  -- total), lê diretamente do catálogo pg_enum — funciona sem linhas na tabela.
  SELECT tipo_recurso, tipo_atendimento INTO v_tr, v_ta
  FROM equipment LIMIT 1;

  IF v_tr IS NULL THEN
    -- %TYPE não é válido em casts SQL — busca como text e PL/pgSQL converte
    SELECT e.enumlabel INTO v_enum_text
    FROM pg_enum e
    JOIN pg_attribute a ON a.atttypid = e.enumtypid
    WHERE a.attrelid = 'equipment'::regclass AND a.attname = 'tipo_recurso'
    ORDER BY e.enumsortorder LIMIT 1;
    v_tr := v_enum_text;

    SELECT e.enumlabel INTO v_enum_text
    FROM pg_enum e
    JOIN pg_attribute a ON a.atttypid = e.enumtypid
    WHERE a.attrelid = 'equipment'::regclass AND a.attname = 'tipo_atendimento'
    ORDER BY e.enumsortorder LIMIT 1;
    v_ta := v_enum_text;

    RAISE NOTICE 'ENUMs de equipment obtidos do catálogo (tabela estava vazia)';
  END IF;

  IF v_tr IS NULL THEN
    RAISE EXCEPTION 'Não foi possível determinar ENUMs de equipment. Verifique o schema.';
  END IF;

  -- Hospital Aroldo Tourinho: atualiza ubs_id se equipment existe, cria se foi deletado pelo cleanup
  UPDATE equipment SET ubs_id = v_aroldo
  WHERE nome IN ('RX-01 — Aroldo Tourinho','RX-02 — Aroldo Tourinho','US-01 — Aroldo Tourinho');
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RX-01 — Aroldo Tourinho') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_aroldo, 'RX-01 — Aroldo Tourinho', v_tr, v_ta, 'manha', 14, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RX-02 — Aroldo Tourinho') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_aroldo, 'RX-02 — Aroldo Tourinho', v_tr, v_ta, 'tarde', 10, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'US-01 — Aroldo Tourinho') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_aroldo, 'US-01 — Aroldo Tourinho', v_tr, v_ta, 'manha', 8, 'ativo');
  END IF;

  -- HU Clemente de Faria — Ortopedia (c71425a1, da05ca58)
  UPDATE equipment SET ubs_id = v_clemente
  WHERE nome IN ('Ortopedia — Consultório Manhã','Traumatologia — Consultório Tarde');
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'Ortopedia — Consultório Manhã') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_clemente, 'Ortopedia — Consultório Manhã', v_tr, v_ta, 'manha', 8, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'Traumatologia — Consultório Tarde') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_clemente, 'Traumatologia — Consultório Tarde', v_tr, v_ta, 'tarde', 6, 'ativo');
  END IF;

  -- ImageMed (6f66f18a, b59e4721)
  UPDATE equipment SET ubs_id = v_imagemed
  WHERE nome IN ('RX-01 — ImageMed','US-01 — ImageMed');
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RX-01 — ImageMed') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_imagemed, 'RX-01 — ImageMed', v_tr, v_ta, 'manha', 12, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'US-01 — ImageMed') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_imagemed, 'US-01 — ImageMed', v_tr, v_ta, 'tarde', 8, 'ativo');
  END IF;

  -- Hospital das Clínicas — equipment novo
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RX-01 — Das Clínicas') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_clinicas, 'RX-01 — Das Clínicas', v_tr, v_ta, 'manha', 12, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'TC-01 — Das Clínicas') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_clinicas, 'TC-01 — Das Clínicas', v_tr, v_ta, 'tarde', 6, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RM-01 — Das Clínicas') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_clinicas, 'RM-01 — Das Clínicas', v_tr, v_ta, 'manha', 4, 'ativo');
  END IF;

  -- Santa Casa
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'Ortopedia — Santa Casa') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_santa, 'Ortopedia — Santa Casa', v_tr, v_ta, 'manha', 8, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RX-01 — Santa Casa') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_santa, 'RX-01 — Santa Casa', v_tr, v_ta, 'tarde', 10, 'ativo');
  END IF;

  -- Dilson Godinho
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'Ortopedia — Dilson Godinho') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_dilson, 'Ortopedia — Dilson Godinho', v_tr, v_ta, 'manha', 6, 'ativo');
  END IF;

  -- OrthoMed (parceiro privado — baixo absenteísmo narrativa)
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'Consulta Ortopédica — OrthoMed') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_ortho, 'Consulta Ortopédica — OrthoMed', v_tr, v_ta, 'manha', 10, 'ativo');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM equipment WHERE nome = 'RX-01 — OrthoMed') THEN
    INSERT INTO equipment (id, ubs_id, nome, tipo_recurso, tipo_atendimento, turno, capacidade_dia, status)
    VALUES (gen_random_uuid(), v_ortho, 'RX-01 — OrthoMed', v_tr, v_ta, 'tarde', 8, 'ativo');
  END IF;

  RAISE NOTICE '✅ BLOCO A concluído — UBSs + equipment prontos';
END $$;

COMMIT;

-- Verificação BLOCO A:
SELECT cnes_code, nome, municipio, tipo, ativo FROM ubs WHERE cnes_code LIKE '9999%' ORDER BY tipo DESC, municipio, nome;
-- Esperado: 14 linhas tipo='S' (11 Montes Claros + 3 macrorregião) + 8 linhas tipo='R' = 22 total

SELECT eq.nome, u.nome AS ubs FROM equipment eq
JOIN ubs u ON u.id = eq.ubs_id
WHERE u.cnes_code LIKE '9999%'
ORDER BY u.nome, eq.nome;
