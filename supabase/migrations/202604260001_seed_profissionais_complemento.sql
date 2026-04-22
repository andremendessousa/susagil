-- ============================================================
-- SUS RAIO-X — Migration 202604260001
-- Profissionais das UBSs/Postos + Contatos Institucionais Executantes
-- Data: 2026-04-22
-- ============================================================
--
-- OBJETIVO:
--   BLOCO 1 — Profissionais dos Postos de Saúde / UBSs Solicitantes
--     Médicos de família e coordenadores que atendem nas UBSs
--     encaminhadoras. São os profissionais que o sistema pode
--     notificar sobre pacientes encaminhados e fila de espera.
--     UBSs cobertas: Independência II (piloto), Maracanã III/IV,
--                    Major Prates II, Cintra I/II,
--                    + macrorregionais (Bocaiúva, Pirapora, Janaúba)
--
--   BLOCO 2 — Contatos Institucionais das Clínicas/Hospitais Executantes
--     Representam a INSTITUIÇÃO (não um indivíduo), tipo='clinica_parceira'.
--     A clínica/hospital confirma a disponibilidade da sua agenda técnica
--     de equipamentos. Isso permite capturar a agenda real da clínica.
--     Cobre: HU Clemente, Das Clínicas (2 setores), Santa Casa (2 setores),
--            Dilson Godinho, OrthoMed
--
--   BLOCO 3 — equipment.profissional_nome nos 9 equipment restantes
--     Usa nomes dos setores institucionais responsáveis.
--     (Os 6 equipment já cobertos por 202604250003 não são tocados.)
--
-- CONTEXTO:
--   Migration 202604250003 já preencheu profissional_nome em:
--     RX-01/RX-02/US-01 — Aroldo  →  Dr. Carlos Silva / Dra. Fernanda Oliveira
--     RX-01/US-01 — ImageMed      →  Téc. Radiologia Martinez
--     RX-01 — OrthoMed            →  Téc. Radiologia Pereira
--
-- ROLLBACK CIRÚRGICO (seguro):
--   -- 1. Remove todos os profissionais desta migration (sem FK bloqueio)
--   DELETE FROM profissionais WHERE telefone LIKE '(38) 99802-%';
--   -- 2. Limpa os 9 campos de equipment definidos aqui
--   UPDATE equipment SET profissional_nome = NULL
--     WHERE nome IN (
--       'Ortopedia — Consultório Manhã',
--       'Traumatologia — Consultório Tarde',
--       'RX-01 — Das Clínicas',
--       'TC-01 — Das Clínicas',
--       'RM-01 — Das Clínicas',
--       'Ortopedia — Santa Casa',
--       'RX-01 — Santa Casa',
--       'Ortopedia — Dilson Godinho',
--       'Consulta Ortopédica — OrthoMed'
--     );
--
-- SEGURANÇA:
--   • Nenhum DELETE em tabelas com FKs (appointments, queue_entries, etc.)
--   • Guard AND profissional_nome IS NULL em todos os UPDATEs de equipment
--   • Idempotente: DELETE + reinsert dentro de cada bloco DO
--   • Blocos 1 e 2 usam faixas distintas (99802-1xxx / 99802-2xxx)
-- ============================================================

BEGIN;

-- ══════════════════════════════════════════════════════════════
--  BLOCO 1 — Profissionais dos Postos de Saúde / UBSs Solicitantes
--  Médicos de família e coordenadores que atendem nas UBSs
--  encaminhadoras e podem ser notificados pelo sistema.
-- ══════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_ind2  uuid;
  v_mar3  uuid;
  v_mar4  uuid;
  v_mp2   uuid;
  v_cin1  uuid;
  v_cin2  uuid;
  v_boc   uuid;
  v_pir   uuid;
  v_jan   uuid;
BEGIN
  -- UBSs Solicitantes Montes Claros
  SELECT id INTO v_ind2 FROM ubs WHERE nome = 'Independência II'  LIMIT 1;
  SELECT id INTO v_mar3 FROM ubs WHERE nome = 'Maracanã III'      LIMIT 1;
  SELECT id INTO v_mar4 FROM ubs WHERE nome = 'Maracanã IV'       LIMIT 1;
  SELECT id INTO v_mp2  FROM ubs WHERE nome = 'Major Prates II'   LIMIT 1;
  SELECT id INTO v_cin1 FROM ubs WHERE nome = 'Cintra I'          LIMIT 1;
  SELECT id INTO v_cin2 FROM ubs WHERE nome = 'Cintra II'         LIMIT 1;
  -- UBSs Macrorregionais
  SELECT id INTO v_boc  FROM ubs WHERE nome = 'UBS Bocaiúva'      LIMIT 1;
  SELECT id INTO v_pir  FROM ubs WHERE nome = 'UBS Pirapora'      LIMIT 1;
  SELECT id INTO v_jan  FROM ubs WHERE nome = 'UBS Janaúba'       LIMIT 1;

  -- Apenas a UBS piloto é obrigatória; demais são opcionais (NULL tolerado)
  IF v_ind2 IS NULL THEN
    RAISE EXCEPTION 'UBS Independência II não encontrada — checar migration 202604210001';
  END IF;

  -- Idempotente: limpa faixa 99802-1xxx antes de reinserir
  DELETE FROM profissionais WHERE telefone LIKE '(38) 99802-1%';

  INSERT INTO profissionais
    (nome, tipo, especialidade, cargo, telefone, ubs_id, ativo)
  VALUES
    -- ── Regional Independência (piloto CPSI 004/2026) ─────────────────
    ('Dra. Fernanda Carvalho',
     'medico', 'Medicina de Família e Comunidade',
     'Coordenadora Médica Regional', '(38) 99802-1001', v_ind2, true),

    -- ── Maracanã III ──────────────────────────────────────────────────
    ('Dr. Paulo Rezende',
     'medico', 'Medicina de Família e Comunidade',
     'Médico de Família e Comunidade', '(38) 99802-1002', v_mar3, true),

    -- ── Maracanã IV ───────────────────────────────────────────────────
    ('Dra. Carmen Silveira',
     'medico', 'Medicina de Família e Comunidade',
     'Médico de Família e Comunidade', '(38) 99802-1003', v_mar4, true),

    -- ── Major Prates II ───────────────────────────────────────────────
    ('Dr. André Vieira',
     'medico', 'Medicina de Família e Comunidade',
     'Médico de Família e Comunidade', '(38) 99802-1004', v_mp2, true),

    -- ── Cintra I ──────────────────────────────────────────────────────
    ('Enf. Renata Barbosa',
     'tecnico', 'Enfermagem',
     'Coordenadora de Enfermagem', '(38) 99802-1005', v_cin1, true),

    -- ── Cintra II ─────────────────────────────────────────────────────
    ('Dr. Eduardo Castro',
     'medico', 'Medicina de Família e Comunidade',
     'Médico de Família e Comunidade', '(38) 99802-1006', v_cin2, true),

    -- ── Macrorregionais ───────────────────────────────────────────────
    ('Dr. Henrique Martins',
     'medico', 'Medicina Geral',
     'Médico Responsável', '(38) 99802-1007', v_boc, true),

    ('Dra. Vanessa Cunha',
     'medico', 'Medicina Geral',
     'Médico Responsável', '(38) 99802-1008', v_pir, true),

    ('Dr. Rodrigo Lima',
     'medico', 'Medicina Geral',
     'Médico Responsável', '(38) 99802-1009', v_jan, true);

  RAISE NOTICE '✅ BLOCO 1: 9 profissionais de UBSs/postos inseridos (99802-1xxx)';
  RAISE NOTICE '   Independência II  → Dra. Fernanda Carvalho (coord. piloto)';
  RAISE NOTICE '   Maracanã III/IV   → Dr. Paulo Rezende / Dra. Carmen Silveira';
  RAISE NOTICE '   Major Prates II   → Dr. André Vieira';
  RAISE NOTICE '   Cintra I/II       → Enf. Renata Barbosa / Dr. Eduardo Castro';
  RAISE NOTICE '   Bocaiúva/Pirapora/Janaúba → responsáveis macrorregionais';
END $$;

-- ══════════════════════════════════════════════════════════════
--  BLOCO 2 — Contatos Institucionais das Clínicas/Hospitais Executantes
--  tipo = 'clinica_parceira': a INSTITUIÇÃO recebe a notificação,
--  confirmando agenda e disponibilidade dos equipamentos técnicos.
--  Permite capturar a agenda real da clínica executante.
-- ══════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_clemente uuid;
  v_clinicas uuid;
  v_santa    uuid;
  v_dilson   uuid;
  v_ortho    uuid;
BEGIN
  SELECT id INTO v_clemente FROM ubs WHERE nome ILIKE '%Clemente%'   LIMIT 1;
  SELECT id INTO v_clinicas FROM ubs WHERE nome ILIKE '%Clínicas%'   LIMIT 1;
  SELECT id INTO v_santa    FROM ubs WHERE nome ILIKE '%Santa Casa%' LIMIT 1;
  SELECT id INTO v_dilson   FROM ubs WHERE nome ILIKE '%Dilson%'     LIMIT 1;
  SELECT id INTO v_ortho    FROM ubs WHERE nome ILIKE '%OrthoMed%'   LIMIT 1;

  IF v_clemente IS NULL THEN RAISE EXCEPTION 'UBS HU Clemente não encontrada';    END IF;
  IF v_clinicas IS NULL THEN RAISE EXCEPTION 'UBS Das Clínicas não encontrada';   END IF;
  IF v_santa    IS NULL THEN RAISE EXCEPTION 'UBS Santa Casa não encontrada';     END IF;
  IF v_dilson   IS NULL THEN RAISE EXCEPTION 'UBS Dilson Godinho não encontrada'; END IF;
  IF v_ortho    IS NULL THEN RAISE EXCEPTION 'UBS OrthoMed não encontrada';       END IF;

  -- Idempotente: limpa faixa 99802-2xxx antes de reinserir
  DELETE FROM profissionais WHERE telefone LIKE '(38) 99802-2%';

  INSERT INTO profissionais
    (nome, tipo, especialidade, cargo, telefone, ubs_id, ativo)
  VALUES
    -- ── HU Clemente de Faria — cobre Ortopedia + Traumatologia ───────
    ('HU Clemente — Ortopedia e Traumatologia',
     'clinica_parceira', 'Ortopedia e Traumatologia',
     'Setor Responsável', '(38) 99802-2001', v_clemente, true),

    -- ── Hospital das Clínicas — RX-01 e TC-01 (mesmo setor) ──────────
    ('Das Clínicas — Radiologia e Tomografia',
     'clinica_parceira', 'Radiologia e Tomografia',
     'Setor de Imagem', '(38) 99802-2002', v_clinicas, true),

    -- ── Hospital das Clínicas — RM-01 (setor distinto) ───────────────
    ('Das Clínicas — Ressonância Magnética',
     'clinica_parceira', 'Ressonância Magnética',
     'Setor de RM', '(38) 99802-2003', v_clinicas, true),

    -- ── Santa Casa — Ortopedia ────────────────────────────────────────
    ('Santa Casa — Serviço de Ortopedia',
     'clinica_parceira', 'Ortopedia',
     'Setor de Ortopedia', '(38) 99802-2004', v_santa, true),

    -- ── Santa Casa — RX-01 (setor de imagem distinto) ─────────────────
    ('Santa Casa — Serviço de Radiologia',
     'clinica_parceira', 'Radiologia',
     'Setor de Radiologia', '(38) 99802-2005', v_santa, true),

    -- ── Fundação Dilson Godinho ────────────────────────────────────────
    ('Dilson Godinho — Serviço de Ortopedia',
     'clinica_parceira', 'Ortopedia',
     'Setor de Ortopedia', '(38) 99802-2006', v_dilson, true),

    -- ── OrthoMed — Consulta Ortopédica ────────────────────────────────
    ('OrthoMed — Agendamento Ortopédico',
     'clinica_parceira', 'Ortopedia',
     'Recepção / Agendamento', '(38) 99802-2007', v_ortho, true);

  RAISE NOTICE '✅ BLOCO 2: 7 contatos institucionais inseridos (99802-2xxx)';
  RAISE NOTICE '   HU Clemente   → Setor Ortopedia e Traumatologia';
  RAISE NOTICE '   Das Clínicas  → Radiologia/TC + RM (setores distintos)';
  RAISE NOTICE '   Santa Casa    → Ortopedia + Radiologia';
  RAISE NOTICE '   Dilson Godinho → Ortopedia | OrthoMed → Agendamento';
END $$;

-- ══════════════════════════════════════════════════════════════
--  BLOCO 3 — Preencher profissional_nome nos 9 equipment restantes
--  Usa nomes dos setores institucionais (clareza no Board 1).
--  Guard AND profissional_nome IS NULL → idempotente.
-- ══════════════════════════════════════════════════════════════

-- HU Clemente de Faria (2 consultórios → mesmo setor)
UPDATE equipment
  SET profissional_nome = 'HU Clemente — Ortopedia'
  WHERE nome IN ('Ortopedia — Consultório Manhã', 'Traumatologia — Consultório Tarde')
    AND profissional_nome IS NULL;

-- Hospital das Clínicas — RX-01 e TC-01
UPDATE equipment
  SET profissional_nome = 'Das Clínicas — Radiologia'
  WHERE nome IN ('RX-01 — Das Clínicas', 'TC-01 — Das Clínicas')
    AND profissional_nome IS NULL;

-- Hospital das Clínicas — RM-01
UPDATE equipment
  SET profissional_nome = 'Das Clínicas — Ressonância'
  WHERE nome = 'RM-01 — Das Clínicas'
    AND profissional_nome IS NULL;

-- Santa Casa — Ortopedia
UPDATE equipment
  SET profissional_nome = 'Santa Casa — Ortopedia'
  WHERE nome = 'Ortopedia — Santa Casa'
    AND profissional_nome IS NULL;

-- Santa Casa — RX-01
UPDATE equipment
  SET profissional_nome = 'Santa Casa — Radiologia'
  WHERE nome = 'RX-01 — Santa Casa'
    AND profissional_nome IS NULL;

-- Fundação Dilson Godinho
UPDATE equipment
  SET profissional_nome = 'Dilson Godinho — Ortopedia'
  WHERE nome = 'Ortopedia — Dilson Godinho'
    AND profissional_nome IS NULL;

-- OrthoMed — Consulta Ortopédica (RX-01 — OrthoMed já tem Téc. Radiologia Pereira)
UPDATE equipment
  SET profissional_nome = 'OrthoMed — Ortopedia'
  WHERE nome = 'Consulta Ortopédica — OrthoMed'
    AND profissional_nome IS NULL;

COMMIT;

-- ══════════════════════════════════════════════════════════════
--  VERIFICAÇÃO PÓS-EXECUÇÃO
-- ══════════════════════════════════════════════════════════════

-- V1 — Equipment: esperado 0 NULLs, 15 com profissional_nome
SELECT
  COUNT(*) FILTER (WHERE profissional_nome IS NULL)     AS sem_profissional,
  COUNT(*) FILTER (WHERE profissional_nome IS NOT NULL) AS com_profissional,
  COUNT(*)                                               AS total
FROM equipment
WHERE status = 'ativo';

-- V2 — Profissionais novos: 9 de postos (99802-1xxx) + 7 institucionais (99802-2xxx)
SELECT tipo, COUNT(*) AS qtd
FROM profissionais
WHERE telefone LIKE '(38) 99802-%'
GROUP BY tipo ORDER BY tipo;

-- V3 — UBSs solicitantes com profissional vinculado (confirma cobertura dos postos)
SELECT u.nome AS ubs, p.nome AS profissional, p.cargo
FROM profissionais p
JOIN ubs u ON u.id = p.ubs_id
WHERE u.tipo = 'S' AND p.telefone LIKE '(38) 99802-%'
ORDER BY u.nome;
