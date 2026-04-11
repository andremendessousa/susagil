import { useState } from 'react'
import { supabase } from '../lib/supabase'

export function useKpiConfigsMutation() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)

  async function update(chave, { valor_meta, valor_atencao, valor_critico }) {
    setLoading(true)
    setError(null)

    const { data: { user } } = await supabase.auth.getUser()

    const { error: err } = await supabase
      .from('kpi_configs')
      .update({
        valor_meta:    Number(valor_meta),
        valor_atencao: Number(valor_atencao),
        valor_critico: Number(valor_critico),
        atualizado_por: user?.id ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('chave', chave)

    if (err) {
      setError(err.message)
      setLoading(false)
      return false
    }

    setLoading(false)
    return true
  }

  return { update, loading, error }
}
