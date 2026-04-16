-- ============================================================
-- SUS RAIO-X — Fix RPC executar_reaproveitamento
-- Execute este arquivo no Supabase SQL Editor
--
-- Correção: appointments não tem patient_id.
-- O vínculo paciente→agendamento é:
--   appointments.queue_entry_id → queue_entries.patient_id
-- ============================================================

create or replace function executar_reaproveitamento(p_vaga_cancelada_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scheduled_at   timestamptz;
  v_equipment_id   uuid;
  v_queue_id       uuid;
  v_nome_proc      text;
  v_proximo_id     uuid;
  v_proximo_tipo_v queue_entries.tipo_vaga%TYPE;
  v_patient_id     uuid;
  v_nome_pac       text;
begin
  -- PRÉ-REQUISITO: dados da vaga cancelada
  -- nome_grupo_procedimento vem da queue_entry (não existe em appointments)
  -- tipo_vaga será lido do próximo da fila (NOT NULL em appointments)
  select
    a.scheduled_at,
    a.equipment_id,
    a.queue_entry_id,
    qe.nome_grupo_procedimento
  into
    v_scheduled_at,
    v_equipment_id,
    v_queue_id,
    v_nome_proc
  from appointments a
  left join queue_entries qe on qe.id = a.queue_entry_id
  where a.id = p_vaga_cancelada_id;

  if not found then
    return json_build_object('nomeConvocado', null, 'erro', 'Vaga cancelada não encontrada');
  end if;

  if v_scheduled_at is null then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- PASSO 1: Retirar cancelado da fila ativa
  if v_queue_id is not null then
    update queue_entries set status_local = 'cancelado' where id = v_queue_id;
  end if;

  -- PASSO 2: Buscar próximo (FIFO clínico)
  select id, patient_id, tipo_vaga
    into v_proximo_id, v_patient_id, v_proximo_tipo_v
    from queue_entries
   where status_local = 'aguardando'
     and (v_nome_proc is null or nome_grupo_procedimento = v_nome_proc)
   order by prioridade_codigo asc, data_solicitacao_sisreg asc
   limit 1;

  if not found then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- PASSO 3: Promover convocado
  update queue_entries set status_local = 'agendado' where id = v_proximo_id;

  -- PASSO 4: Criar novo agendamento
  -- SEM patient_id (coluna não existe em appointments)
  -- COM tipo_vaga (NOT NULL, vem do queue_entry do convocado)
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

  -- Busca nome do convocado para feedback
  select nome into v_nome_pac from patients where id = v_patient_id;

  return json_build_object(
    'nomeConvocado', coalesce(v_nome_pac, 'Próximo da fila'),
    'erro', null
  );

exception when others then
  return json_build_object('nomeConvocado', null, 'erro', sqlerrm);
end;
$$;

revoke execute on function executar_reaproveitamento(uuid) from public;
revoke execute on function executar_reaproveitamento(uuid) from anon;
grant  execute on function executar_reaproveitamento(uuid) to authenticated;
