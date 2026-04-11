import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function useKpiConfigs() {
  const [configs, setConfigs] = useState({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    async function fetch() {
      setLoading(true)
      const { data, error } = await supabase
        .from('v_kpi_status')
        .select('*')
        .order('ordem_exibicao')

      if (error) {
        setError(error.message)
      } else {
        // Indexar por chave para acesso O(1)
        const indexed = (data || []).reduce((acc, item) => {
          acc[item.chave] = {
            label: item.label,
            valor_meta: item.valor_meta,
            valor_critico: item.valor_critico,
            valor_atencao: item.valor_atencao,
            direcao: item.direcao,
            unidade: item.unidade,
          }
          return acc
        }, {})
        setConfigs(indexed)
      }
      setLoading(false)
    }

    fetch()
    // Sem realtime — configs mudam raramente; recarregar apenas na montagem
  }, [])

  return { configs, loading, error }
}
