-- ============================================================
-- SUS RAIO-X — Migration 0003
-- RPC: executar_reaproveitamento (v3 — critérios FIFO corretos)
--
-- Correções aplicadas:
--   1. BUG CRÍTICO: excluir explicitamente o paciente cancelado
--      do PASSO 2, mesmo que PASSO 1 não tenha disparado.
--      Antes: a mesma pessoa podia ser re-selecionada como "próximo".
--
--   2. Filtro por ubs_id: só convoca paciente da mesma UBS.
--      Evita chamar paciente de unidade diferente.
--
--   3. Filtro por tipo_atendimento: consulta não substitui exame
--      e vice-versa, mesmo que nome_grupo_procedimento coincida.
--
--   4. Guarda de segurança: se nome_grupo_procedimento for nulo
--      no appointment cancelado, a função encerra sem reaproveitamento
--      (não é seguro convocar alguém sem saber qual procedimento).
--
-- Critérios de FIFO clínico (ordem de prioridade):
--   1. Mesma UBS (ubs_id)
--   2. Mesmo tipo de atendimento (tipo_atendimento)
--   3. Mesmo procedimento (nome_grupo_procedimento)
--   4. Maior prioridade clínica (prioridade_codigo ASC — menor = maior urgência)
--   5. Mais antigo na fila (data_solicitacao_sisreg ASC)
--
-- Execute no Supabase SQL Editor
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
  v_queue_id         uuid;          -- queue_entry do paciente cancelado
  v_nome_proc        text;          -- procedimento da vaga cancelada
  v_ubs_id           uuid;          -- UBS da vaga (para restringir busca)
  v_tipo_atendimento queue_entries.tipo_atendimento%TYPE;  -- consulta vs exame
  v_cancelled_pat_id uuid;          -- patient_id do cancelado (para exclusão explícita)

  v_proximo_id       uuid;
  v_proximo_tipo_v   queue_entries.tipo_vaga%TYPE;
  v_patient_id       uuid;
  v_nome_pac         text;
begin
  -- ── PRÉ-REQUISITO ─────────────────────────────────────────────────────────
  -- Captura todos os dados necessários para o FIFO clínico correto.
  -- nome_grupo_procedimento, tipo_atendimento, ubs_id e patient_id
  -- vêm da queue_entry (não existem em appointments).
  select
    a.scheduled_at,
    a.equipment_id,
    a.queue_entry_id,
    qe.nome_grupo_procedimento,
    qe.tipo_atendimento,
    qe.ubs_id,
    qe.patient_id          -- para exclusão explícita no PASSO 2
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

  -- Sem data agendada: nada a reaproveitar
  if v_scheduled_at is null then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- Sem procedimento identificado: não é seguro convocar alguém genérico
  if v_nome_proc is null then
    return json_build_object(
      'nomeConvocado', null,
      'erro', null   -- não é erro — simplesmente não há como identificar o procedimento
    );
  end if;

  -- ── PASSO 1: Retirar o cancelado da fila ativa ───────────────────────────
  -- Garante que PASSO 2 não o encontre, mesmo como fallback.
  if v_queue_id is not null then
    update queue_entries
       set status_local = 'cancelado'
     where id = v_queue_id;
  end if;

  -- ── PASSO 2: Buscar próximo na fila (FIFO clínico) ───────────────────────
  -- Filtros obrigatórios:
  --   • status_local = 'aguardando'
  --   • mesma UBS (v_ubs_id)
  --   • mesmo tipo de atendimento (consulta ≠ exame)
  --   • mesmo grupo de procedimento
  --   • excluir EXPLICITAMENTE o paciente cancelado (safety net duplo:
  --     cobre casos em que queue_entry_id é nulo ou PASSO 1 falhou)
  select id, patient_id, tipo_vaga
    into v_proximo_id, v_patient_id, v_proximo_tipo_v
    from queue_entries
   where status_local = 'aguardando'
     and ubs_id = v_ubs_id
     and tipo_atendimento = v_tipo_atendimento
     and nome_grupo_procedimento = v_nome_proc
     -- Exclusão explícita do cancelado (por queue_entry_id e por patient_id)
     and id        is distinct from v_queue_id
     and patient_id is distinct from v_cancelled_pat_id
   order by prioridade_codigo asc, data_solicitacao_sisreg asc
   limit 1;

  -- Fila vazia para este procedimento/UBS: correto, não é erro
  if not found then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- ── PASSO 3: Promover o convocado ────────────────────────────────────────
  update queue_entries
     set status_local = 'agendado'
   where id = v_proximo_id;

  -- ── PASSO 4: Registrar novo agendamento com rastreabilidade ──────────────
  -- appointments NÃO tem patient_id (acesso via queue_entry_id → patient_id)
  -- tipo_vaga é NOT NULL: vem do queue_entry do convocado
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

  -- ── FINALIZAÇÃO: nome do convocado para feedback na UI ───────────────────
  select nome into v_nome_pac from patients where id = v_patient_id;

  return json_build_object(
    'nomeConvocado', coalesce(v_nome_pac, 'Próximo da fila'),
    'erro',          null
  );

exception when others then
  return json_build_object('nomeConvocado', null, 'erro', sqlerrm);
end;
$$;

revoke execute on function executar_reaproveitamento(uuid) from public;
revoke execute on function executar_reaproveitamento(uuid) from anon;
grant  execute on function executar_reaproveitamento(uuid) to authenticated;

comment on function executar_reaproveitamento(uuid) is
  'v3 — FIFO clínico: filtra por UBS + tipo_atendimento + nome_grupo_procedimento. '
  'Exclui explicitamente o paciente cancelado do PASSO 2 por queue_entry_id E patient_id. '
  'Transação atômica SECURITY DEFINER. appointments não tem patient_id.';
