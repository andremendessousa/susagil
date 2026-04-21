-- ============================================================
-- SUS RAIO-X — Migration 202604240006
-- Adiciona valor 'seed_final_demo' ao enum data_source
-- EXECUTE ANTES dos seeds 202604240002-005
-- ============================================================

ALTER TYPE data_source ADD VALUE IF NOT EXISTS 'seed_final_demo';
