-- ============================================================
-- SUS RAIO-X — Migration 0004
-- RPC: executar_reaproveitamento (v4 — fallback gracioso para proc nulo)
--
-- Problema identificado no v3:
--   Quando nome_grupo_procedimento é NULL na queue_entry do appointment
--   cancelado, o v3 abortava silenciosamente ("não é seguro convocar
--   alguém genérico"). Isso impedia o avanço da fila em dados de teste
--   onde o campo ainda não foi populado via importação SISREG.
--
-- Solução v4 — Lógica em cascata (2 tentativas):
--   1. STRICT (padrão produção):
--        UBS + tipo_atendimento + nome_grupo_procedimento (quando não nulo)
--   2. FALLBACK-UBS (dados de teste / proc nulo):
--        UBS + tipo_atendimento (sem filtro de procedimento)
--
-- DECISÃO ARQUITETURAL: cross-UBS (fallback geral) foi rejeitado pelo CTO.
-- Sem base clínica para determinar qual UBS é "mais próxima" a uma paciente.
-- Se nenhum dos 2 níveis encontrar candidato → retorna fila vazia (correto).
--
-- 'nivel_fallback' no JSON: 0=strict, 1=sem proc, -1=fila vazia.
--
-- Filtros mantidos em TODAS as tentativas:
--   • status_local = 'aguardando'
--   • Exclui o paciente cancelado (por queue_entry_id E patient_id)
--   • FIFO clínico: prioridade_codigo ASC, data_solicitacao_sisreg ASC
--
-- Execute no Supabase SQL Editor (ou via supabase db push)
-- ============================================================

create or replace function executar_reaproveitamento(p_vaga_cancelada_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scheduled_at     timestamptz;
  v_equipment_id     uuid;
  v_queue_id         uuid;
  v_nome_proc        text;
  v_ubs_id           uuid;
  v_tipo_atendimento queue_entries.tipo_atendimento%TYPE;
  v_cancelled_pat_id uuid;

  v_proximo_id       uuid;
  v_proximo_tipo_v   queue_entries.tipo_vaga%TYPE;
  v_patient_id       uuid;
  v_nome_pac         text;

  -- Indica qual nível de fallback foi usado (0 = strict, 1 = sem proc, -1 = fila vazia)
  v_nivel_fallback   int := 0;
begin
  -- ── PRÉ-REQUISITO ────────────────────────────────────────────────────────
  select
    a.scheduled_at,
    a.equipment_id,
    a.queue_entry_id,
    qe.nome_grupo_procedimento,
    qe.tipo_atendimento,
    qe.ubs_id,
    qe.patient_id
  into
    v_scheduled_at,
    v_equipment_id,
    v_queue_id,
    v_nome_proc,
    v_tipo_atendimento,
    v_ubs_id,
    v_cancelled_pat_id
  from appointments a
  left join queue_entries qe on qe.id = a.queue_entry_id
  where a.id = p_vaga_cancelada_id;

  if not found then
    return json_build_object(
      'nomeConvocado', null,
      'erro', 'Vaga cancelada não encontrada no banco'
    );
  end if;

  if v_scheduled_at is null then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- ── PASSO 1: Retirar o cancelado da fila ─────────────────────────────────
  if v_queue_id is not null then
    update queue_entries
       set status_local = 'cancelado'
     where id = v_queue_id;
  end if;

  -- ── PASSO 2A: Tentativa STRICT (v3 — padrão produção) ────────────────────
  -- Só executa quando todos os filtros clínicos estão disponíveis
  if v_nome_proc is not null and v_ubs_id is not null and v_tipo_atendimento is not null then
    select id, patient_id, tipo_vaga
      into v_proximo_id, v_patient_id, v_proximo_tipo_v
      from queue_entries
     where status_local   = 'aguardando'
       and ubs_id          = v_ubs_id
       and tipo_atendimento = v_tipo_atendimento
       and nome_grupo_procedimento = v_nome_proc
       and id         is distinct from v_queue_id
       and patient_id is distinct from v_cancelled_pat_id
     order by prioridade_codigo asc, data_solicitacao_sisreg asc
     limit 1;

    v_nivel_fallback := 0;
  end if;

  -- ── PASSO 2B: Fallback UBS+Tipo (proc nulo ou sem resultado strict) ───────
  -- Garante que o sistema avança mesmo quando nome_grupo_procedimento não foi
  -- populado (dados de teste, importações parciais do SISREG etc.)
  if v_proximo_id is null and v_ubs_id is not null and v_tipo_atendimento is not null then
    select id, patient_id, tipo_vaga
      into v_proximo_id, v_patient_id, v_proximo_tipo_v
      from queue_entries
     where status_local   = 'aguardando'
       and ubs_id          = v_ubs_id
       and tipo_atendimento = v_tipo_atendimento
       and id         is distinct from v_queue_id
       and patient_id is distinct from v_cancelled_pat_id
     order by prioridade_codigo asc, data_solicitacao_sisreg asc
     limit 1;

    if found then v_nivel_fallback := 1; end if;
  end if;

  -- Fila realmente vazia (sem cross-UBS — decisão arquitetural)
  if v_proximo_id is null then
    return json_build_object(
      'nomeConvocado', null,
      'erro', null,
      'nivel_fallback', -1,
      'diagnostico', json_build_object(
        'ubs_id',           v_ubs_id,
        'tipo_atendimento', v_tipo_atendimento,
        'nome_proc',        v_nome_proc
      )
    );
  end if;

  -- ── PASSO 3: Promover o convocado ────────────────────────────────────────
  update queue_entries
     set status_local = 'agendado'
   where id = v_proximo_id;

  -- ── PASSO 4: Registrar novo agendamento ───────────────────────────────────
  insert into appointments (
    queue_entry_id,
    scheduled_at,
    equipment_id,
    tipo_vaga,
    status,
    data_source,
    reaproveitado_de_id
  ) values (
    v_proximo_id,
    v_scheduled_at,
    v_equipment_id,
    v_proximo_tipo_v,
    'agendado',
    'manual',
    p_vaga_cancelada_id
  );

  -- ── FINALIZAÇÃO ──────────────────────────────────────────────────────────
  select nome into v_nome_pac from patients where id = v_patient_id;

  return json_build_object(
    'nomeConvocado', coalesce(v_nome_pac, 'Próximo da fila'),
    'erro',          null,
    'nivel_fallback', v_nivel_fallback
  );

exception when others then
  return json_build_object('nomeConvocado', null, 'erro', sqlerrm);
end;
$$;

revoke execute on function executar_reaproveitamento(uuid) from public;
revoke execute on function executar_reaproveitamento(uuid) from anon;
grant  execute on function executar_reaproveitamento(uuid) to authenticated;

comment on function executar_reaproveitamento(uuid) is
  'v4 final — Cascata: STRICT (UBS+tipo+proc) → FALLBACK-UBS (UBS+tipo, proc nulo). '
  'Cross-UBS rejeitado (sem base clínica). nivel_fallback: 0=strict, 1=sem proc, -1=fila vazia. '
  'SECURITY DEFINER, transação atômica, appointments sem patient_id.';
