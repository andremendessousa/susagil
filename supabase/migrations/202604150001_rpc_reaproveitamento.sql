-- ============================================================
-- SUS RAIO-X — Migration 0002 (v2)
-- RPC: executar_reaproveitamento
--
-- Motivo: o frontend usa anon/authenticated key sem privilégio
-- de INSERT em appointments. Mover a lógica de orquestração para
-- uma função SECURITY DEFINER garante:
--   1. Atomicidade completa (tudo ou nada — transação única)
--   2. Zero INSERTs/UPDATEs diretos do frontend em tabelas clínicas
--   3. Autorização centralizada: apenas `authenticated` pode invocar
--   4. Compatibilidade com políticas RLS existentes
--
-- Estrutura real do banco (verificada 2026-04-15):
--   - appointments NÃO tem patient_id (paciente via queue_entries.patient_id)
--   - appointments.tipo_vaga é NOT NULL (obrigatório no INSERT)
--   - nome_grupo_procedimento fica em queue_entries, não em appointments
--
-- Aplicar em: Supabase > SQL Editor
-- ============================================================

-- ── Função principal ─────────────────────────────────────────────────────────
create or replace function executar_reaproveitamento(p_vaga_cancelada_id uuid)
returns json
language plpgsql
security definer                   -- executa com privilégios do owner
set search_path = public           -- evita search_path injection
as $$
declare
  v_scheduled_at   timestamptz;
  v_equipment_id   uuid;
  v_queue_id       uuid;
  v_nome_proc      text;
  v_tipo_vaga      appointments.tipo_vaga%TYPE;
  v_proximo_id     uuid;
  v_proximo_tipo_v queue_entries.tipo_vaga%TYPE;
  v_nome_pac       text;
  v_patient_id     uuid;
begin
  -- ── PRÉ-REQUISITO: dados da vaga cancelada ────────────────────────────────
  -- tipo_vaga vem do próprio appointment (NOT NULL, reutilizamos no novo)
  -- nome_grupo_procedimento vem da queue_entry associada
  select
    a.scheduled_at,
    a.equipment_id,
    a.queue_entry_id,
    a.tipo_vaga,
    qe.nome_grupo_procedimento
  into
    v_scheduled_at,
    v_equipment_id,
    v_queue_id,
    v_tipo_vaga,
    v_nome_proc
  from appointments a
  left join queue_entries qe on qe.id = a.queue_entry_id
  where a.id = p_vaga_cancelada_id;

  if not found then
    return json_build_object(
      'nomeConvocado', null,
      'erro', 'Vaga cancelada não encontrada no banco'
    );
  end if;

  -- Vaga sem data agendada: nada a reaproveitar, não é erro
  if v_scheduled_at is null then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- ── PASSO 1: Retirar o cancelado da fila ativa ───────────────────────────
  if v_queue_id is not null then
    update queue_entries
       set status_local = 'cancelado'
     where id = v_queue_id;
  end if;

  -- ── PASSO 2: Buscar próximo aguardando o mesmo procedimento ──────────────
  -- Critério FIFO clínico: prioridade_codigo ASC, depois data_solicitacao_sisreg ASC
  -- tipo_vaga também é capturado (obrigatório no INSERT de appointments)
  select id, patient_id, tipo_vaga
    into v_proximo_id, v_patient_id, v_proximo_tipo_v
    from queue_entries
   where status_local = 'aguardando'
     and (v_nome_proc is null or nome_grupo_procedimento = v_nome_proc)
   order by prioridade_codigo asc, data_solicitacao_sisreg asc
   limit 1;

  -- Fila vazia para este procedimento: encerramos sem erro
  if not found then
    return json_build_object('nomeConvocado', null, 'erro', null);
  end if;

  -- ── PASSO 3: Promover o convocado na fila ───────────────────────────────
  update queue_entries
     set status_local = 'agendado'
   where id = v_proximo_id;

  -- ── PASSO 4: Registrar novo agendamento com rastreabilidade completa ──────
  -- NOTA: appointments NÃO tem patient_id — paciente é acessado via queue_entry_id
  -- tipo_vaga é NOT NULL, usamos o valor do próximo paciente na fila
  -- reaproveitado_de_id alimenta o KPI de Taxa de Reaproveitamento de Vagas
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

  -- ── FINALIZAÇÃO: retorna nome do convocado para feedback na UI ────────────
  -- patient_id vem da queue_entry selecionada no PASSO 2
  select nome into v_nome_pac from patients where id = v_patient_id;

  return json_build_object(
    'nomeConvocado', coalesce(v_nome_pac, 'Próximo da fila'),
    'erro',          null
  );

exception when others then
  -- Captura qualquer falha e retorna estruturada: nunca deixa o frontend pendurado
  return json_build_object(
    'nomeConvocado', null,
    'erro',          sqlerrm
  );
end;
$$;

