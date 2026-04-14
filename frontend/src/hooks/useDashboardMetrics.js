import { useState, useEffect, useCallback } from 'react'
import { supabase } from '../lib/supabase'
import { useKpiConfigs } from './useKpiConfigs'
import { calcularStatus } from './lib/calcularStatus'

export function useDashboardMetrics({ horizonte = 30, tipoAtendimento = null } = {}) {
  const { configs } = useKpiConfigs()
  const [metrics, setMetrics] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  const fetch = useCallback(async () => {
    if (!configs) return
    setLoading(true)
    setError(null)

    // Parâmetros derivados de configs — sem hardcode
    const janelaHoras  = configs.reaproveitamento_janela_horas?.valor_meta ?? 48
    const diasLimite   = configs.espera_media_dias?.valor_meta ?? 120

    try {
      const [
        absenteismo,
        espera,
        confirmacao,
        reaproveitamento,
        satisfacao,
        demandaReprimida,
        ocupacaoPassada,
        ocupacaoFutura,
      ] = await Promise.all([
        supabase.rpc('calcular_absenteismo',            { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('calcular_tempo_medio_espera',     { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('calcular_taxa_confirmacao_ativa', { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('calcular_taxa_reaproveitamento',  { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento, p_janela_horas: janelaHoras }),
        supabase.rpc('calcular_indice_satisfacao',      { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('calcular_demanda_reprimida',      { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento, p_dias_limite: diasLimite }),
        supabase.rpc('fn_ocupacao_passada',             { p_dias_atras: horizonte,    p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('fn_ocupacao_futura',              { p_dias_a_frente: 7,         p_tipo_atendimento: tipoAtendimento }),
      ])

      const anyError = [absenteismo, espera, confirmacao, reaproveitamento, satisfacao, demandaReprimida, ocupacaoPassada, ocupacaoFutura].find(r => r.error)
      if (anyError?.error) throw anyError.error

      const absValue    = absenteismo.data?.taxa_absenteismo     ?? 0
      const esperaValue = espera.data?.espera_atual_dias         ?? 0
      const confValue   = confirmacao.data?.taxa_confirmacao     ?? 0
      const reapValue   = reaproveitamento.data?.taxa_reaproveitamento ?? 0
      const satValue    = satisfacao.data?.nota_media            ?? 0
      const demandaValue= demandaReprimida.data?.total_reprimida ?? 0

      // Capacidade: aproveitamento histórico via fn_ocupacao_passada
      const ocupRowsPassados = ocupacaoPassada.data || []
      const capTotal  = ocupRowsPassados.reduce((s, r) => s + Number(r.capacidade_total),  0)
      const realizados= ocupRowsPassados.reduce((s, r) => s + Number(r.exames_realizados), 0)
      const capValue  = capTotal > 0 ? Math.round((realizados / capTotal) * 100) : 0
      const ociosos   = ocupRowsPassados.filter(r => Number(r.pct_ocupacao) < 30).length

      // Ocupação futura: próximos 7 dias (widget prospectivo separado)
      const ocupRowsFuturos = ocupacaoFutura.data || []
      const futCapTotal = ocupRowsFuturos.reduce((s, r) => s + Number(r.capacidade_total),    0)
      const futComprom  = ocupRowsFuturos.reduce((s, r) => s + Number(r.vagas_comprometidas), 0)
      const futValue    = futCapTotal > 0 ? Math.round((futComprom / futCapTotal) * 100) : 0

      setMetrics({
        absenteismo:          { valor: absValue,     status: calcularStatus(absValue,     configs.absenteismo_taxa)          },
        espera:               { valor: esperaValue,  status: calcularStatus(esperaValue,  configs.espera_media_dias)         },
        capacidade:           { valor: capValue,     status: calcularStatus(capValue,     configs.capacidade_aproveitamento) },
        ocupacao_futura:      { valor: futValue,     status: calcularStatus(futValue,     configs.capacidade_aproveitamento) },
        demanda_reprimida:    { valor: demandaValue, status: calcularStatus(demandaValue, configs.demanda_reprimida_dias)    },
        confirmacao_ativa:    { valor: confValue,    status: calcularStatus(confValue,    configs.confirmacao_ativa_taxa)    },
        reaproveitamento:     { valor: reapValue,    status: calcularStatus(reapValue,    configs.reaproveitamento_taxa)     },
        satisfacao:           { valor: satValue,     status: calcularStatus(satValue,     configs.satisfacao_meta)           },
        vagas_em_risco:       { valor: 0,            status: 'ok' },
        equipamentos_ociosos: { valor: ociosos,      status: ociosos > 0 ? 'atencao' : 'ok' },
      })
    } catch (err) {
      setError(err.message || String(err))
      setMetrics(null)
    } finally {
      setLoading(false)
    }
  }, [horizonte, tipoAtendimento, configs])

  useEffect(() => { fetch() }, [fetch])

  return { metrics, loading, error, refresh: fetch }
}
