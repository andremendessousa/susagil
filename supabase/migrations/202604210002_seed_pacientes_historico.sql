-- ============================================================
-- SUS RAIO-X — Migration 202604210002
-- Seed: Pacientes + Histórico 30 dias
-- Data: 2026-04-21
-- Referência: Edital CPSI 004/2026
--
-- Execute APÓS 202604210001.
--
-- BLOCO B: 52 pacientes (CNS prefixo 800001)
--   - 22 com ubs_origem = Independência II (escopo Regional)
--   - 25 de outras UBSs de Montes Claros
--   - 5 de municípios da macrorregião (Bocaiúva, Pirapora, Janaúba)
--
-- BLOCO C: Histórico 30 dias — appointments passados (realizados + faltou)
--   Target: ~30% absenteísmo global
--   Distribuição por hospital (narrativa):
--     Aroldo Tourinho: 38% absenteísmo (alto — justifica sistema)
--     Hospital das Clínicas: 22% (referência de qualidade)
--     OrthoMed: 10% (parceiro privado, baixíssimo absenteísmo)
--     HU Clemente: 28% (regional Independência)
--     Santa Casa / Dilson: 30% (média)
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  BLOCO B — 52 pacientes (CNS prefixo 800001)
-- ════════════════════════════════════════════════════════════

BEGIN;

-- ── Regional Independência — Independência II (22 pacientes) ─────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source) VALUES
  ('800001000010001','José Augusto Carneiro',       'Montes Claros','MG','38991230001','seed_demo'),
  ('800001000010002','Maria das Graças Oliveira',   'Montes Claros','MG','38991230002','seed_demo'),
  ('800001000010003','Paulo Henrique Alves',        'Montes Claros','MG','38991230003','seed_demo'),
  ('800001000010004','Ana Paula Ferreira Santos',   'Montes Claros','MG','38991230004','seed_demo'),
  ('800001000010005','Antônio Pereira da Silva',    'Montes Claros','MG','38991230005','seed_demo'),
  ('800001000010006','Rosângela Aparecida Dias',    'Montes Claros','MG','38991230006','seed_demo'),
  ('800001000010007','Francisco das Chagas Rocha',  'Montes Claros','MG','38991230007','seed_demo'),
  ('800001000010008','Benedita Maria Costa',        'Montes Claros','MG','38991230008','seed_demo'),
  ('800001000010009','Geraldo Ferreira Nunes',      'Montes Claros','MG','38991230009','seed_demo'),
  ('800001000010010','Luíza Helena Mendes',         'Montes Claros','MG','38991230010','seed_demo'),
  ('800001000010011','Roberto Carlos da Silva',     'Montes Claros','MG','38991230011','seed_demo'),
  ('800001000010012','Valdir José Teixeira',        'Montes Claros','MG','38991230012','seed_demo'),
  ('800001000010013','Terezinha Aparecida Lima',    'Montes Claros','MG','38991230013','seed_demo'),
  ('800001000010014','Edilson Moreira Campos',      'Montes Claros','MG','38991230014','seed_demo'),
  ('800001000010015','Sílvio Correia Martins',      'Montes Claros','MG','38991230015','seed_demo'),
  ('800001000010016','Conceição Ferreira Ramos',    'Montes Claros','MG','38991230016','seed_demo'),
  ('800001000010017','Sebastião Rodrigues Pinto',   'Montes Claros','MG','38991230017','seed_demo'),
  ('800001000010018','Irene Batista dos Santos',    'Montes Claros','MG','38991230018','seed_demo'),
  ('800001000010019','Adilson Gomes Barbosa',       'Montes Claros','MG','38991230019','seed_demo'),
  ('800001000010020','Marlene Sousa Carvalho',      'Montes Claros','MG','38991230020','seed_demo'),
  ('800001000010021','Norma Regina Rezende',        'Montes Claros','MG','38991230021','seed_demo'),
  ('800001000010022','Cláudio Augusto Faria',       'Montes Claros','MG','38991230022','seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── Maracanã II / III / IV (9 pacientes) ────────────────────────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source) VALUES
  ('800001000020001','Débora Cristina Loureiro',    'Montes Claros','MG','38992230001','seed_demo'),
  ('800001000020002','Fábio Alexandre Moura',       'Montes Claros','MG','38992230002','seed_demo'),
  ('800001000020003','Geralda Marcelina Souza',     'Montes Claros','MG','38992230003','seed_demo'),
  ('800001000020004','Henrique Santiago Leite',     'Montes Claros','MG','38992230004','seed_demo'),
  ('800001000020005','Ivone Cardoso Viana',         'Montes Claros','MG','38992230005','seed_demo'),
  ('800001000020006','João Batista Ferreira',       'Montes Claros','MG','38992230006','seed_demo'),
  ('800001000020007','Lúcia Marina Pimentel',       'Montes Claros','MG','38992230007','seed_demo'),
  ('800001000020008','Manoel Ribeiro da Cruz',      'Montes Claros','MG','38992230008','seed_demo'),
  ('800001000020009','Nilda Aparecida Gomes',       'Montes Claros','MG','38992230009','seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── Major Prates I-IV (9 pacientes) ─────────────────────────────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source) VALUES
  ('800001000030001','Osvaldo Cunha Pereira',       'Montes Claros','MG','38993230001','seed_demo'),
  ('800001000030002','Patrícia Lima Teixeira',      'Montes Claros','MG','38993230002','seed_demo'),
  ('800001000030003','Quirino Borges Nascimento',   'Montes Claros','MG','38993230003','seed_demo'),
  ('800001000030004','Raimunda Coelho Prates',      'Montes Claros','MG','38993230004','seed_demo'),
  ('800001000030005','Salomé Andrade Costa',        'Montes Claros','MG','38993230005','seed_demo'),
  ('800001000030006','Tarcísio Almeida Braga',      'Montes Claros','MG','38993230006','seed_demo'),
  ('800001000030007','Umbelina Fonseca Rocha',      'Montes Claros','MG','38993230007','seed_demo'),
  ('800001000030008','Vander Oliveira Pires',       'Montes Claros','MG','38993230008','seed_demo'),
  ('800001000030009','Wanderlei Santos Nunes',      'Montes Claros','MG','38993230009','seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── São José e Lourdes III + Cintra I/II (7 pacientes) ──────────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source) VALUES
  ('800001000040001','Xênia Rocha Valentim',        'Montes Claros','MG','38994230001','seed_demo'),
  ('800001000040002','Yolanda Pereira Cunha',       'Montes Claros','MG','38994230002','seed_demo'),
  ('800001000040003','Zemário Gomes Brandão',       'Montes Claros','MG','38994230003','seed_demo'),
  ('800001000040004','Adelaide Martins Fiuza',      'Montes Claros','MG','38994230004','seed_demo'),
  ('800001000040005','Bernardo Vieira Lacerda',     'Montes Claros','MG','38994230005','seed_demo'),
  ('800001000040006','Carla Rejane Macedo',         'Montes Claros','MG','38994230006','seed_demo'),
  ('800001000040007','Dirceu Faria Monteiro',       'Montes Claros','MG','38994230007','seed_demo')
ON CONFLICT (cns) DO NOTHING;

-- ── Macrorregião (5 pacientes — municípios vizinhos) ────────────────────────
INSERT INTO patients (cns, nome, municipio_residencia, uf_residencia, telefone, data_source) VALUES
  ('800001000050001','Edmar Couto Vilela',          'Bocaiúva',     'MG','38995230001','seed_demo'),
  ('800001000050002','Fátima Regina Barbosa',       'Pirapora',     'MG','38995230002','seed_demo'),
  ('800001000050003','Gildásio Rocha Pinto',        'Janaúba',      'MG','38995230003','seed_demo'),
  ('800001000050004','Hildete Campos Araújo',       'Bocaiúva',     'MG','38995230004','seed_demo'),
  ('800001000050005','Iran Ferreira Mesquita',      'Pirapora',     'MG','38995230005','seed_demo')
ON CONFLICT (cns) DO NOTHING;

COMMIT;

-- Verificação BLOCO B:
SELECT municipio_residencia, count(*) FROM patients WHERE cns LIKE '800001%'
GROUP BY municipio_residencia ORDER BY count(*) DESC;
-- Esperado: Montes Claros ~47, Bocaiúva 2, Pirapora 2, Janaúba 1


-- ════════════════════════════════════════════════════════════
--  BLOCO C — Histórico 30 dias (base dos KPIs de absenteísmo)
--
--  Appointments passados (status: realizado | faltou)
--  Target global ~30% absenteísmo
--  Por hospital:
--    HU Clemente (Independência): 5 realizados + 2 faltou = 28%
--    Aroldo Tourinho: 8 realizados + 5 faltou = 38%
--    Hospital das Clínicas: 7 realizados + 2 faltou = 22%
--    Santa Casa: 4 realizados + 2 faltou = 33%
--    Dilson Godinho: 3 realizados + 1 faltou = 25%
--    OrthoMed: 9 realizados + 1 faltou = 10%
--    ImageMed: 5 realizados + 2 faltou = 29%
--  Total: 41 realizados + 15 faltou = 27% absenteísmo
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  -- UBSs solicitantes
  v_ind2   uuid; v_mar2  uuid; v_mar3  uuid; v_mar4  uuid;
  v_mp1    uuid; v_mp2   uuid; v_mp3   uuid; v_mp4   uuid;
  v_sjl3   uuid; v_cin1  uuid; v_cin2  uuid;
  -- municípios polo (macrorregião)
  v_boc    uuid; v_pir   uuid; v_jan   uuid;
  -- UBSs executantes
  v_aroldo   uuid; v_clinicas uuid; v_santa  uuid;
  v_dilson   uuid; v_clemente uuid; v_ortho  uuid; v_imagemed uuid;
  -- equipment
  v_clemente_manha uuid; v_clemente_tarde uuid;
  v_aroldo_rx1 uuid; v_aroldo_rx2 uuid; v_aroldo_us uuid;
  v_clinicas_rx uuid; v_clinicas_tc uuid; v_clinicas_rm uuid;
  v_santa_orto uuid; v_santa_rx uuid;
  v_dilson_orto uuid;
  v_ortho_cons uuid; v_ortho_rx uuid;
  v_imagemed_rx uuid; v_imagemed_us uuid;
  -- pacientes Independência II
  p01 uuid; p02 uuid; p03 uuid; p04 uuid; p05 uuid;
  p06 uuid; p07 uuid; p08 uuid; p09 uuid; p10 uuid;
  p11 uuid; p12 uuid;
  -- pacientes outras UBSs
  q01 uuid; q02 uuid; q03 uuid; q04 uuid; q05 uuid;
  q06 uuid; q07 uuid; q08 uuid; q09 uuid; q10 uuid;
  q11 uuid; q12 uuid; q13 uuid; q14 uuid; q15 uuid;
  q16 uuid; q17 uuid; q18 uuid; q19 uuid; q20 uuid;
  -- tipos enum
  v_ta queue_entries.tipo_atendimento%TYPE;
  v_tv queue_entries.tipo_vaga%TYPE;
  v_tr queue_entries.tipo_regulacao%TYPE;
  qe   uuid;
BEGIN
  -- Lookups UBSs solicitantes
  SELECT id INTO v_ind2   FROM ubs WHERE nome = 'Independência II'          LIMIT 1;
  SELECT id INTO v_mar2   FROM ubs WHERE nome = 'Maracanã II'               LIMIT 1;
  SELECT id INTO v_mar3   FROM ubs WHERE nome = 'Maracanã III'              LIMIT 1;
  SELECT id INTO v_mar4   FROM ubs WHERE nome = 'Maracanã IV'               LIMIT 1;
  SELECT id INTO v_mp1    FROM ubs WHERE nome = 'Major Prates I'            LIMIT 1;
  SELECT id INTO v_mp2    FROM ubs WHERE nome = 'Major Prates II'           LIMIT 1;
  SELECT id INTO v_mp3    FROM ubs WHERE nome = 'Major Prates III'          LIMIT 1;
  SELECT id INTO v_mp4    FROM ubs WHERE nome = 'Major Prates IV'           LIMIT 1;
  SELECT id INTO v_sjl3   FROM ubs WHERE nome = 'São José e Lourdes III'    LIMIT 1;
  SELECT id INTO v_cin1   FROM ubs WHERE nome = 'Cintra I'                  LIMIT 1;
  SELECT id INTO v_cin2   FROM ubs WHERE nome = 'Cintra II'                 LIMIT 1;
  SELECT id INTO v_boc    FROM ubs WHERE nome = 'UBS Bocaiúva' LIMIT 1;
  SELECT id INTO v_pir    FROM ubs WHERE nome = 'UBS Pirapora' LIMIT 1;
  SELECT id INTO v_jan    FROM ubs WHERE nome = 'UBS Janaúba'  LIMIT 1;

  -- Lookups UBSs executantes
  SELECT id INTO v_aroldo   FROM ubs WHERE nome = 'Hospital Aroldo Tourinho'              LIMIT 1;
  SELECT id INTO v_clinicas  FROM ubs WHERE nome = 'Hospital das Clínicas Dr. Mário Ribeiro' LIMIT 1;
  SELECT id INTO v_santa    FROM ubs WHERE nome = 'Santa Casa de Montes Claros'           LIMIT 1;
  SELECT id INTO v_dilson   FROM ubs WHERE nome = 'Fundação Dilson Godinho'               LIMIT 1;
  SELECT id INTO v_clemente FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia'     LIMIT 1;
  SELECT id INTO v_ortho    FROM ubs WHERE nome = 'OrthoMed Clínica Especializada'        LIMIT 1;
  SELECT id INTO v_imagemed FROM ubs WHERE nome = 'ImageMed Clinica de Imagem'            LIMIT 1;

  IF v_ind2 IS NULL OR v_clemente IS NULL THEN
    RAISE EXCEPTION 'UBSs não encontradas. Execute 202604210001 primeiro.';
  END IF;

  -- Lookups equipment
  SELECT id INTO v_clemente_manha FROM equipment WHERE nome = 'Ortopedia — Consultório Manhã'   LIMIT 1;
  SELECT id INTO v_clemente_tarde FROM equipment WHERE nome = 'Traumatologia — Consultório Tarde' LIMIT 1;
  SELECT id INTO v_aroldo_rx1     FROM equipment WHERE nome = 'RX-01 — Aroldo Tourinho'         LIMIT 1;
  SELECT id INTO v_aroldo_rx2     FROM equipment WHERE nome = 'RX-02 — Aroldo Tourinho'         LIMIT 1;
  SELECT id INTO v_aroldo_us      FROM equipment WHERE nome = 'US-01 — Aroldo Tourinho'         LIMIT 1;
  SELECT id INTO v_clinicas_rx    FROM equipment WHERE nome = 'RX-01 — Das Clínicas'            LIMIT 1;
  SELECT id INTO v_clinicas_tc    FROM equipment WHERE nome = 'TC-01 — Das Clínicas'            LIMIT 1;
  SELECT id INTO v_clinicas_rm    FROM equipment WHERE nome = 'RM-01 — Das Clínicas'            LIMIT 1;
  SELECT id INTO v_santa_orto     FROM equipment WHERE nome = 'Ortopedia — Santa Casa'          LIMIT 1;
  SELECT id INTO v_santa_rx       FROM equipment WHERE nome = 'RX-01 — Santa Casa'              LIMIT 1;
  SELECT id INTO v_dilson_orto    FROM equipment WHERE nome = 'Ortopedia — Dilson Godinho'      LIMIT 1;
  SELECT id INTO v_ortho_cons     FROM equipment WHERE nome = 'Consulta Ortopédica — OrthoMed'  LIMIT 1;
  SELECT id INTO v_ortho_rx       FROM equipment WHERE nome = 'RX-01 — OrthoMed'               LIMIT 1;
  SELECT id INTO v_imagemed_rx    FROM equipment WHERE nome = 'RX-01 — ImageMed'               LIMIT 1;
  SELECT id INTO v_imagemed_us    FROM equipment WHERE nome = 'US-01 — ImageMed'               LIMIT 1;

  IF v_clemente_manha IS NULL THEN
    RAISE EXCEPTION 'Equipment não encontrado. Execute 202604210001 primeiro.';
  END IF;

  -- Tipos ENUM (cópia de registro real)
  SELECT tipo_atendimento, tipo_vaga, tipo_regulacao INTO v_ta, v_tv, v_tr
  FROM queue_entries LIMIT 1;
  IF v_ta IS NULL THEN v_ta := 'consulta';     END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- Lookups pacientes Independência II
  SELECT id INTO p01 FROM patients WHERE cns = '800001000010001';
  SELECT id INTO p02 FROM patients WHERE cns = '800001000010002';
  SELECT id INTO p03 FROM patients WHERE cns = '800001000010003';
  SELECT id INTO p04 FROM patients WHERE cns = '800001000010004';
  SELECT id INTO p05 FROM patients WHERE cns = '800001000010005';
  SELECT id INTO p06 FROM patients WHERE cns = '800001000010006';
  SELECT id INTO p07 FROM patients WHERE cns = '800001000010007';
  SELECT id INTO p08 FROM patients WHERE cns = '800001000010008';
  SELECT id INTO p09 FROM patients WHERE cns = '800001000010009';
  SELECT id INTO p10 FROM patients WHERE cns = '800001000010010';
  SELECT id INTO p11 FROM patients WHERE cns = '800001000010011';
  SELECT id INTO p12 FROM patients WHERE cns = '800001000010012';

  -- Lookups pacientes outras UBSs (Maracanã, Major Prates, etc.)
  SELECT id INTO q01 FROM patients WHERE cns = '800001000020001';
  SELECT id INTO q02 FROM patients WHERE cns = '800001000020002';
  SELECT id INTO q03 FROM patients WHERE cns = '800001000020003';
  SELECT id INTO q04 FROM patients WHERE cns = '800001000020004';
  SELECT id INTO q05 FROM patients WHERE cns = '800001000020005';
  SELECT id INTO q06 FROM patients WHERE cns = '800001000020006';
  SELECT id INTO q07 FROM patients WHERE cns = '800001000020007';
  SELECT id INTO q08 FROM patients WHERE cns = '800001000020008';
  SELECT id INTO q09 FROM patients WHERE cns = '800001000020009';
  SELECT id INTO q10 FROM patients WHERE cns = '800001000030001';
  SELECT id INTO q11 FROM patients WHERE cns = '800001000030002';
  SELECT id INTO q12 FROM patients WHERE cns = '800001000030003';
  SELECT id INTO q13 FROM patients WHERE cns = '800001000030004';
  SELECT id INTO q14 FROM patients WHERE cns = '800001000040001';
  SELECT id INTO q15 FROM patients WHERE cns = '800001000040002';
  SELECT id INTO q16 FROM patients WHERE cns = '800001000050001';
  SELECT id INTO q17 FROM patients WHERE cns = '800001000050002';
  SELECT id INTO q18 FROM patients WHERE cns = '800001000050003';
  SELECT id INTO q19 FROM patients WHERE cns = '800001000030005';
  SELECT id INTO q20 FROM patients WHERE cns = '800001000030006';

  -- ══════════════════════════════════════════════════════════════════════════
  --  HU CLEMENTE DE FARIA — Independência II
  --  5 realizados + 2 faltou = 28%
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p01,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'120 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clemente_manha,now()-'30 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p02,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','realizado',now()-'110 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clemente_tarde,now()-'25 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p03,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Coluna Vertebral','realizado',now()-'105 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clemente_manha,now()-'18 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p05,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Quadril','realizado',now()-'95 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clemente_tarde,now()-'10 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p06,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'88 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clemente_manha,now()-'5 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (2)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p04,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','faltou',now()-'100 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_clemente_tarde,now()-'22 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p07,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','faltou',now()-'92 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_clemente_manha,now()-'12 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'HU Clemente: 5 realizados + 2 faltou';

  -- ══════════════════════════════════════════════════════════════════════════
  --  HOSPITAL AROLDO TOURINHO
  --  8 realizados + 5 faltou = 38% (alto — narrativa: sobrecarga pública)
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q01,v_mar2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Joelho','realizado',now()-'115 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_rx1,now()-'29 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q02,v_mar3,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','realizado',now()-'112 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_rx2,now()-'27 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q03,v_mar4,'Montes Claros','MG',1,v_tr,v_tv,'exame','Ultrassonografia Musculoesquelética','realizado',now()-'108 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_us,now()-'24 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q04,v_mp1,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Quadril','realizado',now()-'103 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_rx1,now()-'21 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q05,v_mp2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Tornozelo','realizado',now()-'98 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_rx2,now()-'17 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q06,v_mp3,'Montes Claros','MG',4,v_tr,v_tv,'exame','Ultrassonografia Musculoesquelética','realizado',now()-'93 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_us,now()-'13 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q07,v_mp4,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Ombro','realizado',now()-'89 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_rx1,now()-'9 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q08,v_sjl3,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Coluna Cervical','realizado',now()-'85 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_aroldo_rx2,now()-'6 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (5)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q09,v_cin1,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Perna','faltou',now()-'107 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_aroldo_rx1,now()-'26 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q10,v_cin2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Ultrassonografia Musculoesquelética','faltou',now()-'102 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_aroldo_us,now()-'20 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q11,v_mar2,'Montes Claros','MG',1,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','faltou',now()-'97 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_aroldo_rx2,now()-'16 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q12,v_mp1,'Montes Claros','MG',4,v_tr,v_tv,'exame','Radiografia de Joelho','faltou',now()-'91 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_aroldo_rx1,now()-'11 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q13,v_mp2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Ultrassonografia Musculoesquelética','faltou',now()-'86 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_aroldo_us,now()-'7 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'Aroldo Tourinho: 8 realizados + 5 faltou';

  -- ══════════════════════════════════════════════════════════════════════════
  --  HOSPITAL DAS CLÍNICAS DR. MÁRIO RIBEIRO
  --  7 realizados + 2 faltou = 22% (alta complexidade, baixo absenteísmo)
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q14,v_sjl3,'Montes Claros','MG',1,v_tr,v_tv,'exame','Tomografia Computadorizada de Joelho','realizado',now()-'118 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_tc,now()-'28 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q15,v_cin1,'Montes Claros','MG',1,v_tr,v_tv,'exame','Ressonância Magnética de Joelho','realizado',now()-'113 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_rm,now()-'23 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q16,v_boc,'Bocaiúva','MG',2,v_tr,v_tv,'exame','Tomografia de Coluna Vertebral','realizado',now()-'109 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_tc,now()-'19 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q17,v_pir,'Pirapora','MG',2,v_tr,v_tv,'exame','Ressonância Magnética de Coluna','realizado',now()-'104 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_rm,now()-'15 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q18,v_jan,'Janaúba','MG',3,v_tr,'retorno','exame','Radiografia de Quadril','realizado',now()-'99 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_rx,now()-'14 days'::interval,'retorno','realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p08,v_ind2,'Montes Claros','MG',1,v_tr,v_tv,'exame','Tomografia Computadorizada de Quadril','realizado',now()-'95 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_tc,now()-'8 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q19,v_sjl3,'Montes Claros','MG',2,v_tr,v_tv,'exame','Ressonância Magnética de Ombro','realizado',now()-'90 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_clinicas_rm,now()-'4 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (2)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q20,v_mp1,'Montes Claros','MG',3,v_tr,v_tv,'exame','Tomografia de Joelho','faltou',now()-'106 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_clinicas_tc,now()-'25 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p09,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Ressonância Magnética de Joelho','faltou',now()-'101 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_clinicas_rm,now()-'18 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'Das Clínicas: 7 realizados + 2 faltou';

  -- ══════════════════════════════════════════════════════════════════════════
  --  ORTHO MED  — 9 realizados + 1 faltou = 10% (parceiro privado eficiente)
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p10,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'116 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_cons,now()-'27 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p11,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Tornozelo','realizado',now()-'111 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_cons,now()-'22 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p12,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','realizado',now()-'107 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_rx,now()-'19 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q01,v_mar2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'102 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_cons,now()-'16 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q02,v_mar3,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Ombro','realizado',now()-'97 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_rx,now()-'12 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q03,v_mar4,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','realizado',now()-'94 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_cons,now()-'9 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q04,v_mp1,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'90 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_cons,now()-'7 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q05,v_mp2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Joelho','realizado',now()-'87 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_rx,now()-'5 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q06,v_mp3,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Quadril','realizado',now()-'84 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_ortho_cons,now()-'3 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (1 — parceiro privado quase sem faltas)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q07,v_mp4,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','faltou',now()-'96 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_ortho_cons,now()-'10 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'OrthoMed: 9 realizados + 1 faltou';

  -- ══════════════════════════════════════════════════════════════════════════
  --  SANTA CASA — 4 realizados + 2 faltou = 33%
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q08,v_sjl3,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'116 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_santa_orto,now()-'26 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q09,v_cin1,'Montes Claros','MG',1,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','realizado',now()-'110 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_santa_rx,now()-'20 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q10,v_cin2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'104 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_santa_orto,now()-'11 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q11,v_mar2,'Montes Claros','MG',4,v_tr,v_tv,'exame','Radiografia de Joelho','realizado',now()-'98 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_santa_rx,now()-'6 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (2)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q12,v_mp1,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Coluna Vertebral','faltou',now()-'113 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_santa_orto,now()-'24 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q13,v_mp2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Quadril','faltou',now()-'106 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_santa_rx,now()-'15 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'Santa Casa: 4 realizados + 2 faltou';

  -- ══════════════════════════════════════════════════════════════════════════
  --  DILSON GODINHO — 3 realizados + 1 faltou = 25%
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q14,v_sjl3,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','realizado',now()-'114 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_dilson_orto,now()-'23 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q15,v_cin1,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','realizado',now()-'108 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_dilson_orto,now()-'13 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q16,v_boc,'Bocaiúva','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','realizado',now()-'102 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_dilson_orto,now()-'8 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (1)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q17,v_pir,'Pirapora','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','faltou',now()-'109 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_dilson_orto,now()-'21 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'Dilson Godinho: 3 realizados + 1 faltou';

  -- ══════════════════════════════════════════════════════════════════════════
  --  IMAGEMED — 5 realizados + 2 faltou = 29%
  -- ══════════════════════════════════════════════════════════════════════════

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q18,v_jan,'Janaúba','MG',3,v_tr,v_tv,'exame','Ultrassonografia Musculoesquelética','realizado',now()-'117 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_imagemed_us,now()-'28 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q19,v_sjl3,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Tornozelo','realizado',now()-'111 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_imagemed_rx,now()-'21 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (q20,v_mp1,'Montes Claros','MG',1,v_tr,v_tv,'exame','Ultrassonografia de Ombro','realizado',now()-'105 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_imagemed_us,now()-'14 days'::interval,v_tv,'realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p01,v_ind2,'Montes Claros','MG',3,v_tr,'retorno','exame','Radiografia de Joelho','realizado',now()-'99 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_imagemed_rx,now()-'9 days'::interval,'retorno','realizado',1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p02,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,'exame','Ultrassonografia de Joelho','realizado',now()-'94 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(qe,v_imagemed_us,now()-'4 days'::interval,v_tv,'realizado',1,'seed_demo');

  -- Faltou (2)
  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p03,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','faltou',now()-'108 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_imagemed_rx,now()-'17 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  INSERT INTO queue_entries (patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES (p04,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Ultrassonografia de Quadril','faltou',now()-'103 days'::interval,'seed_demo')
  RETURNING id INTO qe;
  INSERT INTO appointments(queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,st_falta_registrada,data_source)
  VALUES(qe,v_imagemed_us,now()-'11 days'::interval,v_tv,'faltou',1,1,'seed_demo');

  RAISE NOTICE 'ImageMed: 5 realizados + 2 faltou';
  RAISE NOTICE '✅ BLOCO C — 41 realizados + 15 faltou (~27%% absenteísmo histórico)';
END $$;

COMMIT;

-- Verificação BLOCO C:
SELECT u_exec.nome AS executante,
       count(*) FILTER (WHERE a.status = 'realizado') AS realizados,
       count(*) FILTER (WHERE a.status = 'faltou')    AS faltas,
       round(100.0 * count(*) FILTER (WHERE a.status = 'faltou')
             / NULLIF(count(*),0), 1)                  AS pct_absenteismo
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
JOIN patients p ON p.id = qe.patient_id
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs u_exec ON u_exec.id = eq.ubs_id
WHERE p.cns LIKE '800001%'
  AND a.status IN ('realizado','faltou')
GROUP BY u_exec.nome
ORDER BY pct_absenteismo DESC;
