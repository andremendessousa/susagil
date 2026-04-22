-- ══════════════════════════════════════════════════════════════════════════════
-- MÓDULO: Comunicação com Profissionais e Clínicas Prestadoras
-- Referência: ETP CPSI 004/2026 — "ausências não comunicadas, equipamentos
-- inoperantes e cancelamentos de última hora"
-- Alinhamento SISREG API v2.1: status "AGENDAMENTO / PENDENTE CONFIRMAÇÃO /
--   EXECUTANTE" e "AGENDAMENTO / CONFIRMADO / EXECUTANTE" (manual seção 4.3)
--
-- ESTRATÉGIA: tabelas NOVAS, ZERO mudanças em tabelas existentes.
--   notification_log permanece idêntica (patient_id NOT NULL, sem colunas novas).
--   Todas as RPCs, KPIs, hooks e queries existentes continuam funcionando.
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── BLOCO 1: Tabela profissionais ─────────────────────────────────────────────
-- Gestão de contatos dos profissionais: alinha com campos
-- nome_profissional_executante / cpf_profissional_executante do SISREG,
-- adicionando telefone e tipo para o fluxo de comunicação WhatsApp.
CREATE TABLE IF NOT EXISTS profissionais (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  nome          text        NOT NULL,
  tipo          text        NOT NULL CHECK (tipo IN ('medico', 'tecnico', 'clinica_parceira')),
  especialidade text,
  cargo         text,
  telefone      text,
  ubs_id        uuid        REFERENCES ubs(id),
  ativo         boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ── BLOCO 2: Tabela professional_confirmations ────────────────────────────────
-- Rastreia o fluxo de confirmação de disponibilidade de agenda por
-- profissionais e clínicas executantes.
-- Data_source usa text (não ENUM) para simplicidade e evitar erros de cast.
CREATE TABLE IF NOT EXISTS professional_confirmations (
  id                       uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profissional_id          uuid        REFERENCES profissionais(id),
  appointment_id           uuid        REFERENCES appointments(id),
  tipo                     text        NOT NULL DEFAULT 'lembrete_manual',
  mensagem                 text        NOT NULL DEFAULT '',
  telefone_destino         text        NOT NULL DEFAULT '',
  status_resposta          text        CHECK (status_resposta IN (
                                         'confirmou_disponibilidade',
                                         'reportou_indisponibilidade'
                                       )),
  motivo_indisponibilidade text,
  enviado_at               timestamptz NOT NULL DEFAULT now(),
  respondido_at            timestamptz,
  data_source              text        NOT NULL DEFAULT 'manual',
  created_at               timestamptz NOT NULL DEFAULT now()
);

-- ── BLOCO 3: Seed mínimo de profissionais (demo CPSI 004/2026) ───────────────
DO $$
DECLARE
  v_aroldo   uuid;
  v_univ     uuid;
  v_imagemed uuid;
  v_ortho    uuid;
  v_amb      uuid;
BEGIN
  SELECT id INTO v_aroldo   FROM ubs WHERE nome ILIKE '%Aroldo%'           LIMIT 1;
  SELECT id INTO v_univ     FROM ubs WHERE nome ILIKE '%Universitário%'    LIMIT 1;
  SELECT id INTO v_imagemed FROM ubs WHERE nome ILIKE '%ImageMed%'         LIMIT 1;
  SELECT id INTO v_ortho    FROM ubs WHERE nome ILIKE '%OrthoMed%'         LIMIT 1;
  SELECT id INTO v_amb      FROM ubs
    WHERE nome ILIKE '%Ambulatório%' OR nome ILIKE '%Especialidades%'
    LIMIT 1;

  -- Idempotente: remove seed anterior antes de reinserir
  DELETE FROM profissionais WHERE telefone LIKE '(38) 99801-%';

  INSERT INTO profissionais (nome, tipo, especialidade, cargo, telefone, ubs_id) VALUES
    ('Dr. Carlos Silva',              'medico',           'Ortopedia',       'Ortopedista',           '(38) 99801-0001', v_aroldo),
    ('Dra. Fernanda Oliveira',        'medico',           'Cardiologia',     'Cardiologista',         '(38) 99801-0002', v_aroldo),
    ('Dra. Lúcia Santos',             'medico',           'Ginecologia',     'Ginecologista',         '(38) 99801-0003', v_univ),
    ('Téc. Radiologia Martinez',      'tecnico',          'Radiologia',      'Técnico de Radiologia', '(38) 99801-0004', v_imagemed),
    ('Téc. Radiologia Pereira',       'tecnico',          'Radiologia',      'Técnico de Radiologia', '(38) 99801-0005', v_aroldo),
    ('ImageMed Clínica',              'clinica_parceira', 'Diagnóstico',     'Contato Institucional', '(38) 99801-0006', v_imagemed),
    ('Ambulatório de Especialidades', 'clinica_parceira', 'Especialidades',  'Contato Institucional', '(38) 99801-0007', v_amb);
END $$;

COMMIT;
