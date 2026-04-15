import { supabase } from './supabase'

/**
 * executarReaproveitamento
 *
 * Orquestra a substituição de um paciente cancelado pelo próximo da fila,
 * garantindo que ambas as tabelas (queue_entries + appointments) reflitam
 * o estado correto para atualização via Realtime no Dashboard e na Fila.
 *
 * Sequência garantida:
 *   1. Limpeza   — queue_entry do cancelado → status_local = 'cancelado'
 *   2. Seleção   — próximo da fila com mesmo procedimento (FIFO clínico)
 *   3. Promoção  — queue_entry do convocado  → status_local = 'agendado'
 *   4. Registro  — INSERT em appointments    → reaproveitado_de_id preenchido
 *
 * @param {string} vagaCanceladaId  UUID do appointment que foi cancelado
 * @returns {{ nomeConvocado: string|null, erro: string|null }}
 */
export async function executarReaproveitamento(vagaCanceladaId) {
  const TAG = '[orquestracao]'

  if (!vagaCanceladaId) {
    console.error(TAG, 'vagaCanceladaId não informado')
    return { nomeConvocado: null, erro: 'ID da vaga não informado' }
  }

  try {
    // ── PRÉ-REQUISITO: Buscar dados da vaga cancelada ─────────────────────────
    console.debug(TAG, 'buscando vaga cancelada:', vagaCanceladaId)

    const { data: vaga, error: vagaErr } = await supabase
      .from('appointments')
      .select('scheduled_at, equipment_id, nome_grupo_procedimento, queue_entry_id')
      .eq('id', vagaCanceladaId)
      .single()

    if (vagaErr) throw new Error(`Pré-req falhou ao buscar vaga: ${vagaErr.message} (${vagaErr.code})`)
    if (!vaga)   throw new Error('Vaga cancelada não encontrada no banco')
    if (!vaga.scheduled_at) {
      console.warn(TAG, 'vaga sem scheduled_at — nada a reaproveitar')
      return { nomeConvocado: null, erro: null }
    }

    console.debug(TAG, 'vaga encontrada:', {
      scheduled_at:            vaga.scheduled_at,
      nome_grupo_procedimento: vaga.nome_grupo_procedimento,
      queue_entry_id:          vaga.queue_entry_id,
    })

    // ── PASSO 1: Limpeza — retira o paciente cancelado da fila ativa ──────────
    // Essencial para que a página Fila reflita a saída imediatamente via Realtime
    if (vaga.queue_entry_id) {
      console.debug(TAG, 'PASSO 1 — marcando queue_entry do cancelado:', vaga.queue_entry_id)

      const { error: p1Err } = await supabase
        .from('queue_entries')
        .update({ status_local: 'cancelado' })
        .eq('id', vaga.queue_entry_id)

      if (p1Err) {
        // Não crítico: loga e continua para não bloquear o reaproveitamento
        console.warn(TAG, 'PASSO 1 falhou (não crítico):', p1Err.message, p1Err.code)
      } else {
        console.debug(TAG, 'PASSO 1 OK — queue_entry do cancelado atualizada')
      }
    } else {
      console.warn(TAG, 'PASSO 1 ignorado — vaga sem queue_entry_id vinculado')
    }

    // ── PASSO 2: Seleção — próximo da fila para o mesmo procedimento ──────────
    // Ordenação: prioridade_codigo ASC (urgência) depois data_solicitacao_sisreg ASC (FIFO)
    console.debug(TAG, 'PASSO 2 — buscando próximo da fila para:', vaga.nome_grupo_procedimento)

    let filaQuery = supabase
      .from('queue_entries')
      .select('id, patient_id, nome_grupo_procedimento')
      .eq('status_local', 'aguardando')
      .order('prioridade_codigo',       { ascending: true })
      .order('data_solicitacao_sisreg', { ascending: true })
      .limit(1)

    if (vaga.nome_grupo_procedimento) {
      filaQuery = filaQuery.eq('nome_grupo_procedimento', vaga.nome_grupo_procedimento)
    }

    const { data: proximoArr, error: p2Err } = await filaQuery

    if (p2Err) throw new Error(`PASSO 2 falhou ao buscar fila: ${p2Err.message} (${p2Err.code})`)

    const proximo = proximoArr?.[0] ?? null

    if (!proximo) {
      console.debug(TAG, 'PASSO 2 — fila vazia para este procedimento. Encerrando sem reaproveitamento.')
      return { nomeConvocado: null, erro: null }
    }

    console.debug(TAG, 'PASSO 2 OK — próximo encontrado:', proximo.id, '| patient_id:', proximo.patient_id)

    // ── PASSO 3: Promoção — muda status do convocado na fila ─────────────────
    // Realtime propagará esta mudança para FilaPage imediatamente
    console.debug(TAG, 'PASSO 3 — promovendo queue_entry:', proximo.id)

    const { error: p3Err } = await supabase
      .from('queue_entries')
      .update({ status_local: 'agendado' })
      .eq('id', proximo.id)

    if (p3Err) throw new Error(`PASSO 3 falhou ao promover na fila: ${p3Err.message} (${p3Err.code})`)

    console.debug(TAG, 'PASSO 3 OK — paciente promovido para status agendado na fila')

    // ── PASSO 4: Registro — cria o novo agendamento com rastreabilidade ───────
    // reaproveitado_de_id é a FK que alimenta o KPI de reaproveitamento no Dashboard
    const novoAppt = {
      patient_id:          proximo.patient_id,
      queue_entry_id:      proximo.id,
      scheduled_at:        vaga.scheduled_at,
      ...(vaga.equipment_id ? { equipment_id: vaga.equipment_id } : {}),
      status:              'agendado',
      data_source:         'csv_import',
      reaproveitado_de_id: vagaCanceladaId,  // ← KPI de Taxa de Reaproveitamento
    }

    console.debug(TAG, 'PASSO 4 — criando appointment reaproveitado:', novoAppt)

    const { error: p4Err } = await supabase
      .from('appointments')
      .insert(novoAppt)

    if (p4Err) throw new Error(`PASSO 4 falhou ao criar appointment: ${p4Err.message} (${p4Err.code})`)

    console.debug(TAG, 'PASSO 4 OK — appointment criado com reaproveitado_de_id:', vagaCanceladaId)

    // ── FINALIZAÇÃO: busca nome do convocado para feedback na UI ──────────────
    const { data: ptData } = await supabase
      .from('patients')
      .select('nome')
      .eq('id', proximo.patient_id)
      .single()

    const nomeConvocado = ptData?.nome ?? 'Próximo da fila'

    console.log(TAG, `✓ Reaproveitamento concluído — paciente convocado: "${nomeConvocado}"`)
    console.log(TAG, `  vaga cancelada: ${vagaCanceladaId} | nova queue_entry: ${proximo.id}`)

    return { nomeConvocado, erro: null }

  } catch (err) {
    console.error(TAG, 'ERRO CRÍTICO no reaproveitamento:', err.message)
    console.error(TAG, 'vagaCanceladaId:', vagaCanceladaId)
    return { nomeConvocado: null, erro: err.message }
  }
}

