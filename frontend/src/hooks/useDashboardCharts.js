import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'

/**
 * Busca dados para os gráficos do Dashboard e da AnaliseGerencialPage.
 *
 * @param {{ horizonte?: number, tipoAtendimento?: string|null }} params
 * @returns {{ charts, loading, error, refresh }}
 *
 * charts = {
 *   tendencia:              Array<{ dia, total, faltas, taxa, taxa_media_movel }>
 *   por_local:              Array<{ equipamento_nome, unidade_nome, realizados, faltas, taxa_absenteismo }>
 *   por_municipio:          Array<{ municipio, uf, total_encaminhamentos, ... }>
 *   ocupacao_passada:       Array<{ equipamento_nome, unidade_nome, pct_ocupacao, ... }>
 *   absenteismo_executante: Array<{ equipamento_nome, unidade_nome, taxa_absenteismo, meta_absenteismo, ... }>
 *   ubs_menor_espera:       Array<{ ubs_nome, municipio, espera_media_dias, meta_espera_dias, ... }>
 * }
 */
export function useDashboardCharts({ horizonte = 30, tipoAtendimento = null } = {}) {
  const [charts, setCharts] = useState({
    tendencia:              [],
    por_local:              [],
    por_municipio:          [],
    ocupacao_passada:       [],
    absenteismo_executante: [],
    ubs_menor_espera:       [],
  })
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState(null)

  const fetch = useCallback(async () => {
    setLoading(true)
    setError(null)

    const results = await Promise.allSettled([
      supabase.rpc('get_tendencia_absenteismo', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
        p_media_movel_dias: 7,
      }),
      supabase.rpc('get_exames_por_local', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('get_demanda_por_municipio', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('fn_ocupacao_passada', {
        p_dias_atras:       horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('get_absenteismo_por_executante', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
      supabase.rpc('get_ubs_menor_espera', {
        p_horizonte_dias:   horizonte,
        p_tipo_atendimento: tipoAtendimento,
      }),
    ])

    // Extrai dado ou array vazio por posição — erro em uma RPC não derruba as outras
    function safeData(result) {
      if (result.status === 'rejected') return []
      if (result.value?.error) return []
      return result.value?.data ?? []
    }

    const [tendencia, porLocal, porMunicipio, ocupPassada, absExec, ubsEspera] = results

    // Coleta erros não-fatais para expor ao caller
    const erros = results
      .filter(r => r.status === 'rejected' || r.value?.error)
      .map(r => r.reason?.message ?? r.value?.error?.message ?? 'RPC error')

    setCharts({
      tendencia:              safeData(tendencia),
      por_local:              safeData(porLocal),
      por_municipio:          safeData(porMunicipio),
      ocupacao_passada:       safeData(ocupPassada),
      absenteismo_executante: safeData(absExec),
      ubs_menor_espera:       safeData(ubsEspera),
    })

    setError(erros.length > 0 ? erros.join(' | ') : null)
    setLoading(false)
  }, [horizonte, tipoAtendimento])

  useEffect(() => { fetch() }, [fetch])

  // Ref estável apontando sempre para a função fetch mais recente.
  // Permite criar o canal Realtime uma única vez, mesmo com múltiplas instâncias do hook.
  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  // Nome único por instância evita conflito quando o hook é usado 2+ vezes na mesma página
  // (ex: DashboardPage instancia useDashboardCharts duas vezes).
  const channelName = useRef(`dashboard-charts-rt-${Math.random().toString(36).slice(2, 8)}`).current

  // Realtime: qualquer alteração em appointments ou queue_entries reconstrói os gráficos.
  // Deps vazios: canal criado uma vez, nunca re-subscrito desnecessariamente.
  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },  () => fetchRef.current?.())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_entries' }, () => fetchRef.current?.())
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { charts, loading, error, refresh: fetch }
}
