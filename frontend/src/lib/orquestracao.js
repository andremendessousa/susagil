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
