import { supabase } from './supabase'

/**
 * executarReaproveitamento
 *
 * Busca o próximo paciente da fila para o mesmo procedimento da vaga cancelada
 * e cria um novo agendamento reutilizando a data/equipamento da vaga original.
 *
 * @param {string} vagaCanceladaId  — UUID do appointment que foi cancelado
 * @returns {{ nomeConvocado: string|null, erro: string|null }}
 *   nomeConvocado: nome do paciente convocado (null se fila vazia ou erro)
 *   erro: mensagem de erro técnico (null se ok)
 */
export async function executarReaproveitamento(vagaCanceladaId) {
  if (!vagaCanceladaId) return { nomeConvocado: null, erro: 'ID da vaga não informado' }

  // 1 — Busca detalhes da vaga cancelada (horário + equipamento + procedimento + queue_entry)
  const { data: vaga, error: vagaErr } = await supabase
    .from('appointments')
    .select('scheduled_at, equipment_id, nome_grupo_procedimento, queue_entry_id')
    .eq('id', vagaCanceladaId)
    .single()

  if (vagaErr || !vaga) {
    console.error('[orquestracao] erro ao buscar vaga cancelada:', vagaErr)
    return { nomeConvocado: null, erro: vagaErr?.message ?? 'Vaga não encontrada' }
  }

  if (!vaga.scheduled_at) {
    return { nomeConvocado: null, erro: null } // sem horário definido, nada a reaproveitar
  }

  // 1b — Marca a queue_entry do paciente que cancelou como 'cancelado'
  //      (retira imediatamente da lista de espera ativa, libera a posição na fila)
  if (vaga.queue_entry_id) {
    const { error: cancelErr } = await supabase
      .from('queue_entries')
      .update({ status_local: 'cancelado' })
      .eq('id', vaga.queue_entry_id)
    if (cancelErr) {
      console.warn('[orquestracao] não foi possível marcar queue_entry como cancelado:', cancelErr)
      // não interrompe o fluxo — a vaga será reaproveitada de qualquer forma
    } else {
      console.debug('[orquestracao] queue_entry do cancelado atualizada:', vaga.queue_entry_id)
    }
  }

  // 2 — Busca o próximo paciente da fila para o MESMO procedimento,
  //     ordenado por data de solicitação mais antiga (FIFO clínico)
  let filaQuery = supabase
    .from('queue_entries')
    .select('id, patient_id, nome_grupo_procedimento')
    .eq('status_local', 'aguardando')
    .order('prioridade_codigo', { ascending: true })     // urgência primeiro
    .order('data_solicitacao_sisreg', { ascending: true }) // mais antigo entre iguais
    .limit(1)

  // Filtra pelo mesmo procedimento se a vaga cancelada tiver essa informação
  if (vaga.nome_grupo_procedimento) {
    filaQuery = filaQuery.eq('nome_grupo_procedimento', vaga.nome_grupo_procedimento)
  }

  const { data: proximoArr } = await filaQuery
  const proximo = proximoArr?.[0] ?? null

  if (!proximo) {
    console.debug('[orquestracao] fila vazia para procedimento:', vaga.nome_grupo_procedimento)
    return { nomeConvocado: null, erro: null }
  }

  // 3 — Cria novo agendamento reaproveitando a vaga
  const novoAppt = {
    patient_id:              proximo.patient_id,
    queue_entry_id:          proximo.id,
    scheduled_at:            vaga.scheduled_at,
    ...(vaga.equipment_id ? { equipment_id: vaga.equipment_id } : {}),
    status:                  'agendado',
    data_source:             'csv_import',
    reaproveitado_de_id:     vagaCanceladaId,  // FK que alimenta o KPI de reaproveitamento
  }
  console.log('[orquestracao] novo appointment a criar:', novoAppt)

  const { error: insertErr } = await supabase
    .from('appointments')
    .insert(novoAppt)

  if (insertErr) {
    console.error('[orquestracao] erro ao inserir appointment reaproveitado:', insertErr)
    return { nomeConvocado: null, erro: insertErr.message }
  }

  // 4 — Retira da fila ativa (impede duplo reaproveitamento)
  await supabase
    .from('queue_entries')
    .update({ status_local: 'agendado' })
    .eq('id', proximo.id)

  // 5 — Busca o nome do paciente convocado para o feedback na UI
  const { data: ptData } = await supabase
    .from('patients')
    .select('nome')
    .eq('id', proximo.patient_id)
    .single()

  const nomeConvocado = ptData?.nome ?? 'Próximo da fila'
  console.log('[orquestracao] paciente convocado:', nomeConvocado)

  return { nomeConvocado, erro: null }
}
