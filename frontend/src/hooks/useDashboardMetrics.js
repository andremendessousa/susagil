import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { useKpiConfigs } from './useKpiConfigs'

/**
 * Determina o status de um KPI comparando o valor real com as metas do banco.
 * @param {number} valorReal
 * @param {{ direcao: string, valor_meta: number, valor_critico: number, valor_atencao: number }} config
 * @returns {'ok' | 'atencao' | 'critico'}
 */
export function calcularStatus(valorReal, config) {
  if (!config || valorReal == null) return 'ok'
  const { direcao, valor_meta, valor_critico, valor_atencao } = config

  if (direcao === 'menor_melhor') {
    if (valorReal >= valor_critico) return 'critico'
    if (valorReal > valor_meta) return 'atencao'
    return 'ok'
  }

  // maior_melhor
  if (valorReal <= valor_critico) return 'critico'
  if (valorReal < valor_meta) return 'atencao'
  return 'ok'
}

export function useDashboardMetrics() {
  const { configs, loading: loadingConfigs, error: errorConfigs } = useKpiConfigs()
  const [metrics, setMetrics] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetchMetrics = useCallback(async () => {
    if (loadingConfigs) return
    if (errorConfigs) {
      setError(errorConfigs)
      setLoading(false)
      return
    }

    setLoading(true)
    setError(null)

    try {
      const limiarDemanda = configs?.demanda_reprimida_dias?.valor_meta ?? 120
      const limiarRiscoHoras = configs?.vagas_risco_horas?.valor_meta ?? 48

      const [
        resAbsenteismo,
        resEspera,
        resCapacidade,
        resDemanda,
        resRisco,
      ] = await Promise.all([
        // Query A — absenteísmo real (últimos 30 dias)
        supabase.rpc('calcular_absenteismo_30d'),

        // Query B — tempo médio de espera (via v_kpis)
        supabase
          .from('v_kpis')
          .select('media_dias_espera, total_aguardando, total_agendado, total_confirmado, total_outros_municipios')
          .single(),

        // Query C — aproveitamento de capacidade
        supabase
          .from('v_ocupacao_equipamentos')
          .select('pct_ocupacao, status')
          .eq('status', 'ativo'),

        // Query D — demanda reprimida (limiar vem do banco)
        supabase.rpc('calcular_demanda_reprimida', { p_limiar_dias: limiarDemanda }),

        // Query E — vagas em risco (limiar vem do banco)
        supabase.rpc('calcular_vagas_em_risco', { p_horas: limiarRiscoHoras }),
      ])

      // Erros individuais
      const erros = [resAbsenteismo, resEspera, resCapacidade, resDemanda, resRisco]
        .filter((r) => r.error)
        .map((r) => r.error.message)

      if (erros.length > 0) {
        setError(erros.join(' | '))
        setLoading(false)
        return
      }

      // --- Absenteísmo ---
      const taxaAbsenteismo = resAbsenteismo.data?.taxa_absenteismo ?? 0

      // --- Espera ---
      const mediaEspera = resEspera.data?.media_dias_espera ?? 0
      const totalAguardando = resEspera.data?.total_aguardando ?? 0
      const totalOutrosMunicipios = resEspera.data?.total_outros_municipios ?? 0

      // --- Capacidade ---
      const equipamentos = resCapacidade.data || []
      const totalEquipamentos = equipamentos.length
      const equipamentosOciosos = equipamentos.filter((e) => e.pct_ocupacao < 30).length
      const mediaOcupacao =
        totalEquipamentos > 0
          ? Math.round(
              (equipamentos.reduce((sum, e) => sum + (e.pct_ocupacao ?? 0), 0) / totalEquipamentos) * 10
            ) / 10
          : 0

      // --- Demanda reprimida ---
      const totalReprimida = resDemanda.data?.total_reprimida ?? 0

      // --- Vagas em risco ---
      const vagasEmRisco = resRisco.data?.vagas_em_risco ?? 0

      setMetrics({
        absenteismo: {
          valor: taxaAbsenteismo,
          status: calcularStatus(taxaAbsenteismo, configs?.absenteismo_taxa),
        },
        espera: {
          valor: mediaEspera,
          status: calcularStatus(mediaEspera, configs?.espera_media_dias),
        },
        capacidade: {
          valor: mediaOcupacao,
          status: calcularStatus(mediaOcupacao, configs?.capacidade_aproveitamento),
        },
        demanda_reprimida: {
          valor: totalReprimida,
          status: calcularStatus(totalReprimida, configs?.demanda_reprimida_dias),
        },
        vagas_em_risco: {
          valor: vagasEmRisco,
          status: calcularStatus(vagasEmRisco, configs?.vagas_risco_horas),
        },
        equipamentos_ociosos: {
          valor: equipamentosOciosos,
          status: equipamentosOciosos === 0 ? 'ok' : equipamentosOciosos === 1 ? 'atencao' : 'critico',
        },
        total_aguardando: totalAguardando,
        total_outros_municipios: totalOutrosMunicipios,
      })
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [configs, loadingConfigs, errorConfigs])

  useEffect(() => {
    fetchMetrics()
  }, [fetchMetrics])

  return { metrics, loading, error, refresh: fetchMetrics }
}
