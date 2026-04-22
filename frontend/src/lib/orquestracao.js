import { supabase } from './supabase'

/**
 * executarReaproveitamento
 *
 * Delega toda a lógica de orquestração para a função RPC `executar_reaproveitamento`
 * no banco (SECURITY DEFINER). Isso garante:
 *   - Atomicidade: os 4 passos são executados em uma única transação
 *   - Segurança: o frontend não precisa de INSERT/UPDATE direto em tabelas clínicas
 *   - Autorização: apenas usuários authenticated podem invocar o RPC
 *
 * @param {string} vagaCanceladaId  UUID do appointment que foi cancelado
 * @returns {{ nomeConvocado: string|null, erro: string|null, nivelFallback: number }}
 *   nivelFallback: 0=strict (prod), 1=sem proc, 2=cross-UBS, -1=fila vazia
 */
export async function executarReaproveitamento(vagaCanceladaId) {
  const TAG = '[orquestracao]'

  if (!vagaCanceladaId) {
    console.error(TAG, 'vagaCanceladaId não informado')
    return { nomeConvocado: null, erro: 'ID da vaga não informado', nivelFallback: -1 }
  }

  try {
    console.debug(TAG, 'chamando RPC executar_reaproveitamento:', vagaCanceladaId)

    const { data, error } = await supabase
      .rpc('executar_reaproveitamento', { p_vaga_cancelada_id: vagaCanceladaId })

    if (error) {
      console.error(TAG, 'RPC retornou erro HTTP:', error.message, error.code)
      return { nomeConvocado: null, erro: error.message, nivelFallback: -1 }
    }

    const result = data ?? {}

    if (result.erro) {
      console.error(TAG, 'Reaproveitamento retornou erro lógico:', result.erro)
      return { nomeConvocado: null, erro: result.erro, nivelFallback: -1 }
    }

    const nivelFallback = result.nivel_fallback ?? 0

    if (result.nomeConvocado) {
      const labels = ['critérios FIFO clínico completo', 'fallback UBS+tipo (proc ausente)', 'fallback geral (cross-UBS)']
      console.log(TAG, `✓ Reaproveitamento nível ${nivelFallback} (${labels[nivelFallback] ?? '?'}) — convocado: "${result.nomeConvocado}"`)
      if (nivelFallback > 0) {
        console.warn(TAG, 'ATENÇÃO: convocação por fallback. Dados de qualidade garantem critérios clínicos completos.', result.diagnostico ?? {})
      }
    } else {
      console.debug(TAG, 'Fila vazia — diagnóstico:', result.diagnostico ?? {})
    }

    return { nomeConvocado: result.nomeConvocado ?? null, erro: null, nivelFallback }

  } catch (err) {
    console.error(TAG, 'ERRO inesperado:', err.message)
    return { nomeConvocado: null, erro: err.message, nivelFallback: -1 }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * executarRiscoCancelamento
 *
 * Acionado quando um profissional reporta indisponibilidade. Localiza todos os
 * pacientes agendados no mesmo equipment+dia e envia um aviso preventivo via
 * notification_log — evitando deslocamentos desnecessários.
 *
 * Restrição de schema: notification_log.patient_id é NOT NULL em produção.
 * A função navega appointments → queue_entries → patients para obter patient_id
 * real; appointments sem patient_id vinculado são ignorados silenciosamente.
 *
 * @param {string} appointmentOrigemId  UUID do appointment da professional_confirmation
 * @param {{ profNome?: string, equipmentNome?: string, ubsNome?: string, motivo?: string }} opts
 * @returns {{ totalAvisados: number, erro: string|null }}
 */
export async function executarRiscoCancelamento(appointmentOrigemId, {
  profNome      = null,
  equipmentNome = null,
  ubsNome       = null,
  motivo        = null,
} = {}) {
  const TAG = '[orquestracao:risco]'

  if (!appointmentOrigemId) {
    console.error(TAG, 'appointmentOrigemId não informado')
    return { totalAvisados: 0, erro: 'ID do appointment não informado' }
  }

  try {
    // ── 1. Dados do slot afetado ──────────────────────────────────────────────
    const { data: origem, error: errOrigem } = await supabase
      .from('appointments')
      .select('equipment_id, scheduled_at')
      .eq('id', appointmentOrigemId)
      .single()

    if (errOrigem || !origem) {
      console.error(TAG, 'Appointment de origem não encontrado:', errOrigem?.message)
      return { totalAvisados: 0, erro: errOrigem?.message ?? 'Appointment de origem não encontrado' }
    }

    const equipmentId = origem.equipment_id
    const slotDay     = new Date(origem.scheduled_at).toISOString().slice(0, 10) // YYYY-MM-DD

    // ── 2. Todos os appointments no mesmo slot com pacientes vinculados ────────
    // Filtra por equipment_id + dia + status ativo; e descarta rows sem patient_id.
    const { data: vizinhos, error: errViz } = await supabase
      .from('appointments')
      .select(`
        id, scheduled_at,
        queue_entries (
          patient_id,
          patients ( id, telefone )
        )
      `)
      .eq('equipment_id', equipmentId)
      .gte('scheduled_at', `${slotDay}T00:00:00.000Z`)
      .lte('scheduled_at', `${slotDay}T23:59:59.999Z`)
      .in('status', ['aguardando', 'agendado', 'confirmado'])

    if (errViz) {
      console.error(TAG, 'Erro ao buscar appointments do slot:', errViz.message)
      return { totalAvisados: 0, erro: errViz.message }
    }

    const afetados = (vizinhos || []).filter(a => a.queue_entries?.patient_id)

    if (afetados.length === 0) {
      console.debug(TAG, `Nenhum paciente elegível no slot ${equipmentId} ${slotDay}`)
      return { totalAvisados: 0, erro: null }
    }

    // ── 3. Mensagem de aviso preventivo ───────────────────────────────────────
    const dt          = new Date(origem.scheduled_at)
    const dataExtenso = new Intl.DateTimeFormat('pt-BR', {
      weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric',
    }).format(dt)
    const horario = new Intl.DateTimeFormat('pt-BR', {
      hour: '2-digit', minute: '2-digit',
    }).format(dt)

    const mensagem = [
      '[Secretaria Municipal de Saúde — Montes Claros/MG]',
      '⚠️ *Aviso Preventivo — Seu Agendamento*',
      '',
      'Prezado(a) paciente,',
      '',
      'Identificamos uma possível indisponibilidade no serviço em que você tem um atendimento marcado:',
      '',
      `📅 *Data:* ${dataExtenso}`,
      `⏰ *Horário:* ${horario}`,
      ...(ubsNome       ? [`🏥 *Unidade:* ${ubsNome}`]       : []),
      ...(equipmentNome ? [`🔬 *Serviço:* ${equipmentNome}`]  : []),
      ...(motivo        ? ['', `⚠️ *Motivo informado:* ${motivo}`] : []),
      '',
      '*Não se desloque até receber a confirmação de reagendamento.*',
      'Nossa equipe tomará as providências e você será avisado em breve.',
      '',
      'Em caso de dúvidas, procure sua Unidade Básica de Saúde.',
      '',
      '_Sistema de Regulação SUS Raio-X_',
      '_Secretaria Municipal de Saúde · Montes Claros/MG · CPSI 004/2026_',
    ].join('\n')

    // ── 4. Insere notification_log para cada paciente afetado ─────────────────
    const agora   = new Date().toISOString()
    const inserts = afetados.map(a => ({
      patient_id:       a.queue_entries.patient_id,
      appointment_id:   a.id,
      tipo:             'lembrete_manual',
      canal:            'whatsapp',
      mensagem,
      telefone_destino: a.queue_entries.patients?.telefone ?? '',
      enviado_at:       agora,
      entregue:         false,
      data_source:      'manual',
    }))

    const { error: errInsert } = await supabase
      .from('notification_log')
      .insert(inserts)

    if (errInsert) {
      console.error(TAG, 'Erro ao inserir notification_log:', errInsert.message)
      return { totalAvisados: 0, erro: errInsert.message }
    }

    console.log(TAG, `✓ ${inserts.length} paciente(s) notificados preventivamente — slot ${equipmentId} ${slotDay}`)
    return { totalAvisados: inserts.length, erro: null }

  } catch (err) {
    console.error(TAG, 'ERRO inesperado:', err.message)
    return { totalAvisados: 0, erro: err.message }
  }
}
