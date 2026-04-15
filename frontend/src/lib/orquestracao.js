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
 * @returns {{ nomeConvocado: string|null, erro: string|null }}
 */
export async function executarReaproveitamento(vagaCanceladaId) {
  const TAG = '[orquestracao]'

  if (!vagaCanceladaId) {
    console.error(TAG, 'vagaCanceladaId não informado')
    return { nomeConvocado: null, erro: 'ID da vaga não informado' }
  }

  try {
    console.debug(TAG, 'chamando RPC executar_reaproveitamento:', vagaCanceladaId)

    const { data, error } = await supabase
      .rpc('executar_reaproveitamento', { p_vaga_cancelada_id: vagaCanceladaId })

    if (error) {
      console.error(TAG, 'RPC retornou erro HTTP:', error.message, error.code)
      return { nomeConvocado: null, erro: error.message }
    }

    const result = data ?? {}

    if (result.erro) {
      console.error(TAG, 'Reaproveitamento retornou erro lógico:', result.erro)
      return { nomeConvocado: null, erro: result.erro }
    }

    if (result.nomeConvocado) {
      console.log(TAG, `✓ Reaproveitamento concluído — convocado: "${result.nomeConvocado}"`)
    } else {
      console.debug(TAG, 'Reaproveitamento concluído — fila vazia para este procedimento')
    }

    return { nomeConvocado: result.nomeConvocado ?? null, erro: null }

  } catch (err) {
    console.error(TAG, 'ERRO inesperado:', err.message)
    return { nomeConvocado: null, erro: err.message }
  }
}
