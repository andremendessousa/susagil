-- ============================================================
-- LIMPEZA DE PACIENTES DUPLICADOS NO SEED DE DEMONSTRAÇÃO
-- Data: 2026-04-17
--
-- INSTRUÇÕES — execute NO SUPABASE SQL EDITOR em 3 passos:
--
--   BLOCO A  →  cole e rode: mostra os duplicados (diagnóstico)
--   BLOCO B  →  revise o resultado do A, depois cole e rode: executa a limpeza
--   BLOCO C  →  cole e rode: confirma que não há mais duplicatas
--
-- Cada bloco é independente e autocontido. Não há nada para descomentar.
-- ============================================================


-- ════════════════════════════════════════════════════════════
--  BLOCO A — DIAGNÓSTICO (rode primeiro, não modifica nada)
-- ════════════════════════════════════════════════════════════

WITH canonical_map AS (
  SELECT
    id AS dupe_id,
    FIRST_VALUE(id) OVER (
      PARTITION BY nome
      ORDER BY created_at ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS canonical_id
  FROM patients
),
real_dupes AS (
  SELECT dupe_id, canonical_id
  FROM canonical_map
  WHERE dupe_id <> canonical_id
)
SELECT
  p.nome,
  p.id           AS dupe_id,
  rd.canonical_id,
  p.created_at
FROM real_dupes rd
JOIN patients p ON p.id = rd.dupe_id
ORDER BY p.nome, p.created_at;

-- Esperado: uma linha por duplicata.
-- Se retornar 0 linhas, não há duplicatas — não é necessário rodar os blocos B e C.


-- ════════════════════════════════════════════════════════════
--  BLOCO B — MIGRAÇÃO (rode somente após revisar o Bloco A)
--  Redireciona FKs para o registro canônico e remove duplicatas.
--  Operação atômica: qualquer erro faz ROLLBACK automático.
-- ════════════════════════════════════════════════════════════

BEGIN;

-- 1 de 3: Redireciona notification_log para o patient canônico
WITH canonical_map AS (
  SELECT
    id AS dupe_id,
    FIRST_VALUE(id) OVER (
      PARTITION BY nome
      ORDER BY created_at ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS canonical_id
  FROM patients
),
real_dupes AS (
  SELECT dupe_id, canonical_id
  FROM canonical_map
  WHERE dupe_id <> canonical_id
)
UPDATE notification_log nl
   SET patient_id = rd.canonical_id
  FROM real_dupes rd
 WHERE nl.patient_id = rd.dupe_id;

-- 2 de 3: Redireciona queue_entries para o patient canônico
WITH canonical_map AS (
  SELECT
    id AS dupe_id,
    FIRST_VALUE(id) OVER (
      PARTITION BY nome
      ORDER BY created_at ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS canonical_id
  FROM patients
),
real_dupes AS (
  SELECT dupe_id, canonical_id
  FROM canonical_map
  WHERE dupe_id <> canonical_id
)
UPDATE queue_entries qe
   SET patient_id = rd.canonical_id
  FROM real_dupes rd
 WHERE qe.patient_id = rd.dupe_id;

-- 2b de 3: Redireciona satisfaction_surveys para o patient canônico
WITH canonical_map AS (
  SELECT
    id AS dupe_id,
    FIRST_VALUE(id) OVER (
      PARTITION BY nome
      ORDER BY created_at ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS canonical_id
  FROM patients
),
real_dupes AS (
  SELECT dupe_id, canonical_id
  FROM canonical_map
  WHERE dupe_id <> canonical_id
)
UPDATE satisfaction_surveys ss
   SET patient_id = rd.canonical_id
  FROM real_dupes rd
 WHERE ss.patient_id = rd.dupe_id;

-- 3 de 3: Remove os registros duplicados (FKs já redirecionadas acima)
WITH canonical_map AS (
  SELECT
    id AS dupe_id,
    FIRST_VALUE(id) OVER (
      PARTITION BY nome
      ORDER BY created_at ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS canonical_id
  FROM patients
)
DELETE FROM patients
 WHERE id IN (
   SELECT dupe_id FROM canonical_map WHERE dupe_id <> canonical_id
 );

COMMIT;


-- ════════════════════════════════════════════════════════════
--  BLOCO C — VERIFICAÇÃO (rode após o Bloco B)
-- ════════════════════════════════════════════════════════════

SELECT nome, COUNT(*) AS ocorrencias
  FROM patients
 GROUP BY nome
HAVING COUNT(*) > 1
 ORDER BY nome;

-- Esperado: 0 linhas (tabela vazia = sem duplicatas).
-- Se retornar linhas, algum nome ainda tem duplicata — revisar o Bloco B.
