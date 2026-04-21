-- ============================================================
-- SUS RAIO-X — Migration 202604210003
-- Seed: Fila de Espera + Pipeline 3 Boards + Notificações
-- Data: 2026-04-21
-- Referência: Edital CPSI 004/2026
--
-- Execute APÓS 202604210001 e 202604210002.
--
-- BLOCO D: Fila aguardando (~30 entradas, múltiplas UBSs)
-- BLOCO E: Pipeline 3 boards com reaproveitamento FIFO
--   Board 1 — Pendente notificação (st_paciente_avisado IS NULL)
--   Board 2 — Aguardando confirmação (notif enviada, sem resposta)
--   Board 3 — Histórico (confirmou ✅ | cancelou ❌ → FIFO ativado)
-- BLOCO F: Verificação final
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  BLOCO D — Fila de espera aguardando regulação (~30 entradas)
--
--  Distribuição por prioridade e UBS para storytelling:
--    Prioritária 1 (vermelho): 6 casos graves
--    Prioridade 2 (amarelo): 12 casos
--    Prioridade 3 (verde): 8 casos
--    Prioridade 4 (azul/rotina): 4 casos
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  v_ind2  uuid; v_mar2  uuid; v_mar3  uuid; v_mar4  uuid;
  v_mp1   uuid; v_mp2   uuid; v_mp3   uuid; v_mp4   uuid;
  v_sjl3  uuid; v_cin1  uuid; v_cin2  uuid;
  -- municípios polo (macrorregião)
  v_boc   uuid; v_pir   uuid; v_jan   uuid;
  -- 22 pacientes Independência II
  p01 uuid; p02 uuid; p03 uuid; p04 uuid; p05 uuid;
  p06 uuid; p07 uuid; p08 uuid; p09 uuid; p10 uuid;
  p11 uuid; p12 uuid; p13 uuid; p14 uuid; p15 uuid;
  p16 uuid; p17 uuid; p18 uuid; p19 uuid; p20 uuid;
  p21 uuid; p22 uuid;
  -- pacientes outras UBSs
  q01 uuid; q02 uuid; q03 uuid; q04 uuid; q05 uuid;
  q06 uuid; q07 uuid; q08 uuid; q09 uuid; q10 uuid;
  -- tipos
  v_ta queue_entries.tipo_atendimento%TYPE;
  v_tv queue_entries.tipo_vaga%TYPE;
  v_tr queue_entries.tipo_regulacao%TYPE;
BEGIN
  SELECT id INTO v_ind2  FROM ubs WHERE nome = 'Independência II'       LIMIT 1;
  SELECT id INTO v_mar2  FROM ubs WHERE nome = 'Maracanã II'            LIMIT 1;
  SELECT id INTO v_mar3  FROM ubs WHERE nome = 'Maracanã III'           LIMIT 1;
  SELECT id INTO v_mar4  FROM ubs WHERE nome = 'Maracanã IV'            LIMIT 1;
  SELECT id INTO v_mp1   FROM ubs WHERE nome = 'Major Prates I'         LIMIT 1;
  SELECT id INTO v_mp2   FROM ubs WHERE nome = 'Major Prates II'        LIMIT 1;
  SELECT id INTO v_mp3   FROM ubs WHERE nome = 'Major Prates III'       LIMIT 1;
  SELECT id INTO v_mp4   FROM ubs WHERE nome = 'Major Prates IV'        LIMIT 1;
  SELECT id INTO v_sjl3  FROM ubs WHERE nome = 'São José e Lourdes III' LIMIT 1;
  SELECT id INTO v_cin1  FROM ubs WHERE nome = 'Cintra I'               LIMIT 1;
  SELECT id INTO v_cin2  FROM ubs WHERE nome = 'Cintra II'              LIMIT 1;
  SELECT id INTO v_boc    FROM ubs WHERE nome = 'UBS Bocaiúva'          LIMIT 1;
  SELECT id INTO v_pir    FROM ubs WHERE nome = 'UBS Pirapora'          LIMIT 1;
  SELECT id INTO v_jan    FROM ubs WHERE nome = 'UBS Janaúba'           LIMIT 1;

  IF v_ind2 IS NULL THEN
    RAISE EXCEPTION 'UBSs não encontradas. Execute 202604210001 primeiro.';
  END IF;

  SELECT tipo_atendimento, tipo_vaga, tipo_regulacao INTO v_ta, v_tv, v_tr
  FROM queue_entries LIMIT 1;
  IF v_ta IS NULL THEN v_ta := 'consulta';     END IF;
  IF v_tv IS NULL THEN v_tv := 'primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr := 'fila_espera';  END IF;

  -- Pacientes Independência II
  SELECT id INTO p01 FROM patients WHERE cns = '800001000010001';
  SELECT id INTO p02 FROM patients WHERE cns = '800001000010002';
  SELECT id INTO p03 FROM patients WHERE cns = '800001000010003';
  SELECT id INTO p04 FROM patients WHERE cns = '800001000010004';
  SELECT id INTO p05 FROM patients WHERE cns = '800001000010005';
  SELECT id INTO p06 FROM patients WHERE cns = '800001000010006';
  SELECT id INTO p07 FROM patients WHERE cns = '800001000010007';
  SELECT id INTO p09 FROM patients WHERE cns = '800001000010009';
  SELECT id INTO p10 FROM patients WHERE cns = '800001000010010';
  SELECT id INTO p11 FROM patients WHERE cns = '800001000010011';
  SELECT id INTO p12 FROM patients WHERE cns = '800001000010012';
  SELECT id INTO p13 FROM patients WHERE cns = '800001000010013';
  SELECT id INTO p14 FROM patients WHERE cns = '800001000010014';
  SELECT id INTO p15 FROM patients WHERE cns = '800001000010015';
  SELECT id INTO p16 FROM patients WHERE cns = '800001000010016';
  SELECT id INTO p17 FROM patients WHERE cns = '800001000010017';
  SELECT id INTO p18 FROM patients WHERE cns = '800001000010018';
  SELECT id INTO p19 FROM patients WHERE cns = '800001000010019';
  SELECT id INTO p20 FROM patients WHERE cns = '800001000010020';
  SELECT id INTO p21 FROM patients WHERE cns = '800001000010021';
  SELECT id INTO p22 FROM patients WHERE cns = '800001000010022';

  -- Pacientes outras UBSs
  SELECT id INTO q01 FROM patients WHERE cns = '800001000020004';
  SELECT id INTO q02 FROM patients WHERE cns = '800001000020005';
  SELECT id INTO q03 FROM patients WHERE cns = '800001000020006';
  SELECT id INTO q04 FROM patients WHERE cns = '800001000020007';
  SELECT id INTO q05 FROM patients WHERE cns = '800001000020008';
  SELECT id INTO q06 FROM patients WHERE cns = '800001000030007';
  SELECT id INTO q07 FROM patients WHERE cns = '800001000030008';
  SELECT id INTO q08 FROM patients WHERE cns = '800001000030009';
  SELECT id INTO q09 FROM patients WHERE cns = '800001000040003';
  SELECT id INTO q10 FROM patients WHERE cns = '800001000050004';

  -- ── PRIORIDADE 1 — Urgência (vermelho) ──────────────────────────────────

  -- Geraldo Nunes — gonalgia aguda traumática, 65 dias → 1º FIFO Independência
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p09,v_ind2,'Montes Claros','MG',1,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','aguardando',now()-'65 days'::interval,'seed_demo');

  -- Roberto Carlos — fratura (dor persistente), 55 dias → 2º FIFO Independência
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p11,v_ind2,'Montes Claros','MG',1,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','aguardando',now()-'55 days'::interval,'seed_demo');

  -- Débora Cristina — trauma ortopédico, Maracanã II
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q01,v_mar2,'Montes Claros','MG',1,v_tr,v_tv,'exame','Tomografia Computadorizada de Joelho','aguardando',now()-'48 days'::interval,'seed_demo');

  -- Henrique Santiago — fratura consolidada, Major Prates I
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q02,v_mp1,'Montes Claros','MG',1,v_tr,v_tv,'exame','Ressonância Magnética de Joelho','aguardando',now()-'42 days'::interval,'seed_demo');

  -- Ivone — tendinite rompida, Maracanã IV
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q03,v_mar4,'Montes Claros','MG',1,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','aguardando',now()-'38 days'::interval,'seed_demo');

  -- Zemário — politrauma, São José e Lourdes III
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q09,v_sjl3,'Montes Claros','MG',1,v_tr,v_tv,'exame','Tomografia de Coluna Vertebral','aguardando',now()-'35 days'::interval,'seed_demo');

  -- ── PRIORIDADE 2 — Amarelo (12 casos) ───────────────────────────────────

  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p12,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','aguardando',now()-'78 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p10,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Coluna Vertebral','aguardando',now()-'60 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p14,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Quadril','aguardando',now()-'45 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p21,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Joelho','aguardando',now()-'40 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q04,v_mar3,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','aguardando',now()-'72 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q05,v_mp2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Ultrassonografia Musculoesquelética','aguardando',now()-'68 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q06,v_mp3,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Coluna Vertebral','aguardando',now()-'62 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q07,v_cin1,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','aguardando',now()-'55 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q08,v_cin2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','aguardando',now()-'50 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q10,v_boc,'Bocaiúva','MG',2,v_tr,v_tv,'exame','Radiografia de Quadril','aguardando',now()-'44 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p22,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,'exame','Ultrassonografia de Joelho','aguardando',now()-'38 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p05,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','aguardando',now()-'32 days'::interval,'seed_demo');

  -- ── PRIORIDADE 3 — Verde (8 casos) ──────────────────────────────────────

  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p15,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','aguardando',now()-'70 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p16,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','aguardando',now()-'58 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p06,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Ombro','aguardando',now()-'50 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p20,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Tornozelo','aguardando',now()-'43 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p19,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Quadril','aguardando',now()-'36 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p03,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Quadril','aguardando',now()-'30 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p07,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','aguardando',now()-'25 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p02,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,'exame','Ultrassonografia de Tornozelo','aguardando',now()-'20 days'::interval,'seed_demo');

  -- ── PRIORIDADE 4 — Rotina/Azul (4 casos) ────────────────────────────────

  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p17,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Coluna Vertebral','aguardando',now()-'130 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p18,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','aguardando',now()-'110 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p01,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,'exame','Radiografia de Coluna Cervical','aguardando',now()-'95 days'::interval,'seed_demo');
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p04,v_ind2,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Tornozelo','aguardando',now()-'85 days'::interval,'seed_demo');

  RAISE NOTICE '✅ BLOCO D — 30 pacientes na fila (6 urgência + 12 amarelo + 8 verde + 4 azul)';
END $$;

COMMIT;

-- Verificação BLOCO D (FIFO Independência):
SELECT ROW_NUMBER() OVER (ORDER BY prioridade_codigo, data_solicitacao_sisreg) AS pos_fifo,
       p.nome, qe.prioridade_codigo AS prio,
       EXTRACT(DAY FROM now()-qe.data_solicitacao_sisreg)::int AS dias_espera,
       qe.nome_grupo_procedimento, u.nome AS ubs_origem
FROM queue_entries qe
JOIN patients p ON p.id = qe.patient_id
JOIN ubs u ON u.id = qe.ubs_id
WHERE u.nome = 'Independência II' AND qe.status_local = 'aguardando'
ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg;


-- ════════════════════════════════════════════════════════════
--  BLOCO E — Pipeline 3 boards + Reaproveitamento FIFO
--
--  Narrativa completa de notificações:
--
--  Board 1 — "Pendente notificação" (5 pacientes):
--    Irene, Adilson, Marlene, Norma, Cláudio — st_paciente_avisado=NULL
--    Montes Claros: mais 6 = total 11 no board 1
--
--  Board 2 — "Aguardando confirmação" (4 pacientes):
--    Terezinha, Luíza Helena, Roberto C., Valdir — notif enviada, sem resposta
--
--  Board 3 — "Histórico confirmados/cancelados":
--    Conceição: confirmou ✅
--    Sílvio: confirmou ✅
--    Edilson: cancelou ❌ → FIFO liberou vaga para Geraldo Nunes
--    Reaproveitamento: badges visíveis na UI (reaproveitado_de_id NOT NULL)
-- ════════════════════════════════════════════════════════════

BEGIN;

DO $$
DECLARE
  v_ind2    uuid; v_mar2 uuid; v_mar3 uuid; v_mar4 uuid; v_mp1 uuid; v_mp2 uuid; v_mp3 uuid; v_cin1 uuid; v_cin2 uuid;
  v_clemente uuid; v_aroldo uuid; v_clinicas uuid; v_ortho uuid; v_imagemed uuid;
  v_santa uuid; v_dilson uuid;
  -- equipment
  v_eq_clem_m uuid; v_eq_clem_t uuid;
  v_eq_aro_rx1 uuid; v_eq_aro_us uuid;
  v_eq_clin_rx uuid; v_eq_clin_tc uuid;
  v_eq_ortho_c uuid; v_eq_im_rx uuid;
  v_eq_santa_o uuid; v_eq_dilson_o uuid;
  -- pacientes
  p09 uuid; p10 uuid; p13 uuid; p14 uuid; p15 uuid;
  p16 uuid; p18 uuid; p19 uuid; p20 uuid;
  q01 uuid; q02 uuid; q03 uuid; q04 uuid; q05 uuid;
  q06 uuid; q07 uuid; q08 uuid; q09 uuid; q10 uuid;
  -- queue_entries + appointments
  qe1 uuid; qe2 uuid; qe3 uuid;
  ap1 uuid; ap2 uuid; ap_cancelado uuid;
  v_ta queue_entries.tipo_atendimento%TYPE;
  v_tv queue_entries.tipo_vaga%TYPE;
  v_tr queue_entries.tipo_regulacao%TYPE;
BEGIN
  SELECT tipo_atendimento, tipo_vaga, tipo_regulacao INTO v_ta, v_tv, v_tr
  FROM queue_entries LIMIT 1;
  IF v_ta IS NULL THEN v_ta:='consulta'; END IF;
  IF v_tv IS NULL THEN v_tv:='primeira_vez'; END IF;
  IF v_tr IS NULL THEN v_tr:='fila_espera'; END IF;

  -- UBSs
  SELECT id INTO v_ind2    FROM ubs WHERE nome = 'Independência II'                    LIMIT 1;
  SELECT id INTO v_mar2    FROM ubs WHERE nome = 'Maracanã II'                         LIMIT 1;
  SELECT id INTO v_mar3    FROM ubs WHERE nome = 'Maracanã III'                        LIMIT 1;
  SELECT id INTO v_mp1     FROM ubs WHERE nome = 'Major Prates I'                      LIMIT 1;
  SELECT id INTO v_mp2     FROM ubs WHERE nome = 'Major Prates II'                     LIMIT 1;
  SELECT id INTO v_cin1    FROM ubs WHERE nome = 'Cintra I'                            LIMIT 1;
  SELECT id INTO v_mar4    FROM ubs WHERE nome = 'Maracanã IV'                         LIMIT 1;
  SELECT id INTO v_mp3     FROM ubs WHERE nome = 'Major Prates III'                    LIMIT 1;
  SELECT id INTO v_cin2    FROM ubs WHERE nome = 'Cintra II'                           LIMIT 1;
  SELECT id INTO v_clemente FROM ubs WHERE nome = 'HU Clemente de Faria — Ortopedia'  LIMIT 1;
  SELECT id INTO v_aroldo  FROM ubs WHERE nome = 'Hospital Aroldo Tourinho'            LIMIT 1;
  SELECT id INTO v_clinicas FROM ubs WHERE nome = 'Hospital das Clínicas Dr. Mário Ribeiro' LIMIT 1;
  SELECT id INTO v_ortho   FROM ubs WHERE nome = 'OrthoMed Clínica Especializada'     LIMIT 1;
  SELECT id INTO v_imagemed FROM ubs WHERE nome = 'ImageMed Clinica de Imagem'         LIMIT 1;
  SELECT id INTO v_santa   FROM ubs WHERE nome = 'Santa Casa de Montes Claros'        LIMIT 1;
  SELECT id INTO v_dilson  FROM ubs WHERE nome = 'Fundação Dilson Godinho'             LIMIT 1;

  -- Equipment
  SELECT id INTO v_eq_clem_m  FROM equipment WHERE nome = 'Ortopedia — Consultório Manhã'   LIMIT 1;
  SELECT id INTO v_eq_clem_t  FROM equipment WHERE nome = 'Traumatologia — Consultório Tarde' LIMIT 1;
  SELECT id INTO v_eq_aro_rx1 FROM equipment WHERE nome = 'RX-01 — Aroldo Tourinho'         LIMIT 1;
  SELECT id INTO v_eq_aro_us  FROM equipment WHERE nome = 'US-01 — Aroldo Tourinho'         LIMIT 1;
  SELECT id INTO v_eq_clin_rx FROM equipment WHERE nome = 'RX-01 — Das Clínicas'            LIMIT 1;
  SELECT id INTO v_eq_clin_tc FROM equipment WHERE nome = 'TC-01 — Das Clínicas'            LIMIT 1;
  SELECT id INTO v_eq_ortho_c FROM equipment WHERE nome = 'Consulta Ortopédica — OrthoMed'  LIMIT 1;
  SELECT id INTO v_eq_im_rx   FROM equipment WHERE nome = 'RX-01 — ImageMed'               LIMIT 1;
  SELECT id INTO v_eq_santa_o FROM equipment WHERE nome = 'Ortopedia — Santa Casa'          LIMIT 1;
  SELECT id INTO v_eq_dilson_o FROM equipment WHERE nome = 'Ortopedia — Dilson Godinho'     LIMIT 1;

  IF v_ind2 IS NULL OR v_eq_clem_m IS NULL THEN
    RAISE EXCEPTION 'UBSs ou equipment não encontrados. Execute os arquivos anteriores.';
  END IF;

  -- Pacientes Independência II
  SELECT id INTO p09 FROM patients WHERE cns = '800001000010009'; -- Geraldo (1º FIFO)
  SELECT id INTO p10 FROM patients WHERE cns = '800001000010010'; -- Luíza Helena
  SELECT id INTO p13 FROM patients WHERE cns = '800001000010013'; -- Terezinha
  SELECT id INTO p14 FROM patients WHERE cns = '800001000010014'; -- Edilson
  SELECT id INTO p15 FROM patients WHERE cns = '800001000010015'; -- Sílvio
  SELECT id INTO p16 FROM patients WHERE cns = '800001000010016'; -- Conceição
  SELECT id INTO p18 FROM patients WHERE cns = '800001000010018'; -- Irene
  SELECT id INTO p19 FROM patients WHERE cns = '800001000010019'; -- Adilson
  SELECT id INTO p20 FROM patients WHERE cns = '800001000010020'; -- Marlene

  -- Pacientes outras UBSs (para Board MC)
  SELECT id INTO q01 FROM patients WHERE cns = '800001000020001';
  SELECT id INTO q02 FROM patients WHERE cns = '800001000020002';
  SELECT id INTO q03 FROM patients WHERE cns = '800001000020003';
  SELECT id INTO q04 FROM patients WHERE cns = '800001000020009';
  SELECT id INTO q05 FROM patients WHERE cns = '800001000030001';
  SELECT id INTO q06 FROM patients WHERE cns = '800001000030002';
  SELECT id INTO q07 FROM patients WHERE cns = '800001000030003';
  SELECT id INTO q08 FROM patients WHERE cns = '800001000040004';
  SELECT id INTO q09 FROM patients WHERE cns = '800001000040005';
  SELECT id INTO q10 FROM patients WHERE cns = '800001000040006';

  -- ══════════════════════════════════════════════════════════════════════════
  --  BOARD 3 — Confirmados e Cancelado (geram histórico + reaproveitamento)
  -- ══════════════════════════════════════════════════════════════════════════

  -- Conceição — confirmou ✅ (Independência II → HU Clemente)
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p16,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','confirmado',now()-'90 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_clem_m,now()+'2 days'::interval,v_tv,'confirmado',1,'seed_demo')
  RETURNING id INTO ap1;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,resposta_paciente,enviado_at,respondido_at,entregue,data_source)
  VALUES(p16,ap1,'72h','whatsapp','Confirmação de consulta ortopédica amanhã no HU Clemente.','38991230016','confirmou',now()-'3 days'::interval,now()-'2 days'::interval,true,'seed_demo');

  -- Sílvio — confirmou ✅ (Independência II → HU Clemente)
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p15,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','confirmado',now()-'85 days'::interval,'seed_demo')
  RETURNING id INTO qe2;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(gen_random_uuid(),qe2,v_eq_clem_t,now()+'3 days'::interval,v_tv,'confirmado',1,'seed_demo')
  RETURNING id INTO ap2;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,resposta_paciente,enviado_at,respondido_at,entregue,data_source)
  VALUES(p15,ap2,'72h','whatsapp','Confirmação de consulta de traumatologia. Compareça às 14h.','38991230015','confirmou',now()-'4 days'::interval,now()-'3 days'::interval,true,'seed_demo');

  -- Edilson — cancelou ❌ → vaga liberada, FIFO convoca Geraldo Nunes
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p14,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Quadril','cancelado',now()-'88 days'::interval,'seed_demo')
  RETURNING id INTO qe3;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(gen_random_uuid(),qe3,v_eq_clem_m,now()+'1 day'::interval,v_tv,'cancelado',1,'seed_demo')
  RETURNING id INTO ap_cancelado;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,resposta_paciente,enviado_at,respondido_at,entregue,data_source)
  VALUES(p14,ap_cancelado,'72h','whatsapp','Consulta ortopédica agendada. Confirme sua presença.','38991230014','cancelou',now()-'2 days'::interval,now()-'1 day'::interval,true,'seed_demo');

  -- Geraldo — reaproveitado após cancelamento de Edilson (reaproveitado_de_id)
  -- Este é o badge de reaproveitamento FIFO — narrativa central do sistema
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p09,v_ind2,'Montes Claros','MG',1,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','agendado',now()-'65 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,reaproveitado_de_id,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_clem_m,now()+'1 day'::interval,v_tv,'agendado',NULL,ap_cancelado,'seed_demo');

  RAISE NOTICE 'Board 3: Conceição confirmou, Sílvio confirmou, Edilson cancelou → FIFO convocou Geraldo';

  -- ══════════════════════════════════════════════════════════════════════════
  --  BOARD 2 — Aguardando confirmação (notif enviada, sem resposta)
  -- ══════════════════════════════════════════════════════════════════════════

  -- Terezinha — Independência II, aguardando resposta
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p13,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Joelho','agendado',now()-'80 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_clem_t,now()+'4 days'::interval,v_tv,'agendado',1,'seed_demo')
  RETURNING id INTO ap1;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,enviado_at,entregue,data_source)
  VALUES(p13,ap1,'72h','whatsapp','Sua consulta ortopédica está confirmada para daqui a 4 dias.','38991230013',now()-'12 hours'::interval,true,'seed_demo');

  -- Luíza Helena — Independência II, aguardando resposta
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p10,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Coluna Vertebral','agendado',now()-'75 days'::interval,'seed_demo')
  RETURNING id INTO qe2;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(gen_random_uuid(),qe2,v_eq_clem_m,now()+'5 days'::interval,v_tv,'agendado',1,'seed_demo')
  RETURNING id INTO ap2;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,enviado_at,entregue,data_source)
  VALUES(p10,ap2,'72h','whatsapp','Lembrete: consulta de ortopedia coluna. Confirme por aqui.','38991230010',now()-'8 hours'::interval,true,'seed_demo');

  -- Débora (Maracanã II) — aguardando resposta, Das Clínicas
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q01,v_mar2,'Montes Claros','MG',1,v_tr,v_tv,'exame','Tomografia Computadorizada de Joelho','agendado',now()-'55 days'::interval,'seed_demo')
  RETURNING id INTO qe3;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,data_source)
  VALUES(gen_random_uuid(),qe3,v_eq_clin_tc,now()+'3 days'::interval,v_tv,'agendado',1,'seed_demo')
  RETURNING id INTO ap1;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,enviado_at,entregue,data_source)
  VALUES(q01,ap1,'24h','whatsapp','Tomografia de joelho agendada no Hospital das Clínicas.','38992230001',now()-'6 hours'::interval,true,'seed_demo');

  -- Fábio (Maracanã II) — aguardando resposta, OrthoMed — reaproveitado
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q02,v_mar3,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','agendado',now()-'50 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,st_paciente_avisado,reaproveitado_de_id,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_ortho_c,now()+'2 days'::interval,v_tv,'agendado',1,ap_cancelado,'seed_demo')
  RETURNING id INTO ap2;
  INSERT INTO notification_log(patient_id,appointment_id,tipo,canal,mensagem,telefone_destino,enviado_at,entregue,data_source)
  VALUES(q02,ap2,'72h','whatsapp','Consulta ortopédica disponível na OrthoMed. Confirme sua presença.','38992230002',now()-'4 hours'::interval,true,'seed_demo');

  RAISE NOTICE 'Board 2: 4 pacientes aguardando confirmação';

  -- ══════════════════════════════════════════════════════════════════════════
  --  BOARD 1 — Pendente notificação (st_paciente_avisado IS NULL)
  -- ══════════════════════════════════════════════════════════════════════════

  -- Irene — Independência II → HU Clemente, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p18,v_ind2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','agendado',now()-'70 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_clem_m,now()+'1 day'::interval,v_tv,'agendado','seed_demo');

  -- Adilson — Independência II → HU Clemente, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p19,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Tornozelo','agendado',now()-'65 days'::interval,'seed_demo')
  RETURNING id INTO qe2;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe2,v_eq_clem_t,now()+'2 days'::interval,v_tv,'agendado','seed_demo');

  -- Marlene — Independência II → HU Clemente, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(p20,v_ind2,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Quadril','agendado',now()-'60 days'::interval,'seed_demo')
  RETURNING id INTO qe3;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe3,v_eq_clem_m,now()+'3 days'::interval,v_tv,'agendado','seed_demo');

  -- Geralda (Maracanã III) → Aroldo Tourinho RX, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q03,v_mar3,'Montes Claros','MG',2,v_tr,v_tv,'exame','Radiografia de Joelho','agendado',now()-'72 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_aro_rx1,now()+'1 day'::interval,v_tv,'agendado','seed_demo');

  -- Nilda (Maracanã IV) → Aroldo Tourinho US, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q04,v_mar4,'Montes Claros','MG',3,v_tr,v_tv,'exame','Ultrassonografia de Joelho','agendado',now()-'67 days'::interval,'seed_demo')
  RETURNING id INTO qe2;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe2,v_eq_aro_us,now()+'2 days'::interval,v_tv,'agendado','seed_demo');

  -- Osvaldo (Major Prates I) → Das Clínicas RX, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q05,v_mp1,'Montes Claros','MG',1,v_tr,v_tv,'exame','Radiografia de Coluna Lombar','agendado',now()-'60 days'::interval,'seed_demo')
  RETURNING id INTO qe3;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,reaproveitado_de_id,data_source)
  VALUES(gen_random_uuid(),qe3,v_eq_clin_rx,now()+'1 day'::interval,v_tv,'agendado',ap_cancelado,'seed_demo');

  -- Patrícia (Major Prates II) → OrthoMed, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q06,v_mp2,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','agendado',now()-'55 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_ortho_c,now()+'4 days'::interval,v_tv,'agendado','seed_demo');

  -- Quirino (Major Prates III) → Santa Casa, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q07,v_mp3,'Montes Claros','MG',3,v_tr,v_tv,v_ta,'Avaliação Ortopédica — Ombro','agendado',now()-'50 days'::interval,'seed_demo')
  RETURNING id INTO qe2;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe2,v_eq_santa_o,now()+'5 days'::interval,v_tv,'agendado','seed_demo');

  -- Raimunda (Major Prates IV) → Dilson Godinho, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q08,v_cin1,'Montes Claros','MG',2,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','agendado',now()-'45 days'::interval,'seed_demo')
  RETURNING id INTO qe3;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe3,v_eq_dilson_o,now()+'3 days'::interval,v_tv,'agendado','seed_demo');

  -- Adelaide (Cintra I / São José) → ImageMed, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q09,v_cin1,'Montes Claros','MG',3,v_tr,v_tv,'exame','Radiografia de Tornozelo','agendado',now()-'40 days'::interval,'seed_demo')
  RETURNING id INTO qe1;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe1,v_eq_im_rx,now()+'2 days'::interval,v_tv,'agendado','seed_demo');

  -- Bernardo (Cintra II) → OrthoMed, Board 1
  INSERT INTO queue_entries(patient_id,ubs_id,municipio_paciente,uf_paciente,prioridade_codigo,tipo_regulacao,tipo_vaga,tipo_atendimento,nome_grupo_procedimento,status_local,data_solicitacao_sisreg,data_source)
  VALUES(q10,v_cin2,'Montes Claros','MG',4,v_tr,v_tv,v_ta,'Consulta de Ortopedia e Traumatologia','agendado',now()-'35 days'::interval,'seed_demo')
  RETURNING id INTO qe2;
  INSERT INTO appointments(id,queue_entry_id,equipment_id,scheduled_at,tipo_vaga,status,data_source)
  VALUES(gen_random_uuid(),qe2,v_eq_ortho_c,now()+'6 days'::interval,v_tv,'agendado','seed_demo');

  RAISE NOTICE 'Board 1: 10 pacientes pendentes de notificação (3 Independência + 7 MC)';
  RAISE NOTICE '✅ BLOCO E — Pipeline 3 boards concluído (reaproveitamentos: 3 badges)';
END $$;

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO F — Verificação final
-- ════════════════════════════════════════════════════════════

-- 1. Resumo geral dos dados seed
SELECT 'patients'       AS tabela, count(*) AS total FROM patients       WHERE cns LIKE '800001%'
UNION ALL
SELECT 'queue_entries'  AS tabela, count(*) AS total FROM queue_entries   WHERE data_source='seed_demo'
UNION ALL
SELECT 'appointments'   AS tabela, count(*) AS total FROM appointments    WHERE data_source='seed_demo'
UNION ALL
SELECT 'notification_log' AS tabela, count(*) AS total FROM notification_log WHERE data_source='seed_demo'
ORDER BY tabela;

-- 2. Absenteísmo por hospital (confirma target ~30%)
SELECT u.nome AS hospital,
       count(*) FILTER (WHERE a.status='realizado') AS realizados,
       count(*) FILTER (WHERE a.status='faltou')    AS faltas,
       round(100.0*count(*) FILTER (WHERE a.status='faltou')/NULLIF(count(*),0),1) AS pct_absenteismo
FROM appointments a
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs u ON u.id = eq.ubs_id
WHERE a.data_source='seed_demo' AND a.status IN ('realizado','faltou')
GROUP BY u.nome ORDER BY pct_absenteismo DESC;

-- 3. Pipeline WhatsApp (boards)
SELECT
  CASE WHEN nl.id IS NOT NULL AND nl.resposta_paciente IS NOT NULL THEN '3 - Histórico'
       WHEN nl.id IS NOT NULL AND nl.resposta_paciente IS NULL     THEN '2 - Aguard. confirmação'
       WHEN nl.id IS NULL AND a.status IN ('agendado','confirmado') THEN '1 - Pendente notif.'
       ELSE 'outro'
  END AS board,
  count(*) AS qtd
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
LEFT JOIN notification_log nl ON nl.appointment_id = a.id
WHERE a.data_source = 'seed_demo'
  AND a.status IN ('agendado','confirmado','cancelado')
GROUP BY board ORDER BY board;

-- 4. Reaproveitamentos (badges FIFO)
SELECT a.id AS appointment_id,
       p.nome AS paciente,
       u.nome AS hospital,
       a.reaproveitado_de_id IS NOT NULL AS foi_reaproveitado
FROM appointments a
JOIN queue_entries qe ON qe.id = a.queue_entry_id
JOIN patients p ON p.id = qe.patient_id
JOIN equipment eq ON eq.id = a.equipment_id
JOIN ubs u ON u.id = eq.ubs_id
WHERE a.data_source='seed_demo' AND a.reaproveitado_de_id IS NOT NULL;
-- Esperado: 3 linhas (Geraldo, Fábio, Osvaldo)

-- 5. Fila FIFO ordenada — Independência II
SELECT ROW_NUMBER() OVER (ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg) AS posicao,
       p.nome, qe.prioridade_codigo AS prio,
       EXTRACT(DAY FROM now()-qe.data_solicitacao_sisreg)::int AS dias_espera,
       qe.nome_grupo_procedimento
FROM queue_entries qe
JOIN patients p ON p.id = qe.patient_id
JOIN ubs u ON u.id = qe.ubs_id
WHERE u.nome = 'Independência II' AND qe.status_local = 'aguardando'
ORDER BY qe.prioridade_codigo, qe.data_solicitacao_sisreg;
