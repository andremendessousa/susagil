import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '../lib/supabase'
import { useKpiConfigs } from './useKpiConfigs'
import { calcularStatus } from './lib/calcularStatus'

export function useDashboardMetrics({ horizonte = 30, tipoAtendimento = null, municipios = null, executanteNomes = null, ubsReguladoraNomes = null } = {}) {
  const { configs } = useKpiConfigs()
  const [metrics, setMetrics] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  // Skeleton apenas na primeira carga ou quando parâmetros mudam.
  // Refetches do Realtime são silenciosos — evita flicker.
  const showSkeletonRef = useRef(true)

  const fetch = useCallback(async () => {
    if (!configs) return
    if (showSkeletonRef.current) setLoading(true)
    showSkeletonRef.current = false
    setError(null)

    // Parâmetros derivados de configs — sem hardcode
    // p_dias_limite: protocolo SUS — pacientes aguardando >30 dias são "demanda reprimida".
    // Não usa configs.espera_media_dias (que é o limite de espera média = 120d),
    // pois 120d zero-out toda a demanda reprimida demo com seed de 54d máximo.
    const janelaHoras     = configs.reaproveitamento_janela_horas?.valor_meta ?? 48
    const diasLimite      = configs.demanda_reprimida_limite_dias?.valor_meta  ?? 30
    const vagasRiscoHoras = configs.vagas_risco_horas?.valor_meta ?? 48

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
        vagasRisco,
      ] = await Promise.all([
        supabase.rpc('calcular_absenteismo',            { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento, p_municipios: municipios, p_executante_nomes: executanteNomes }),
        supabase.rpc('calcular_tempo_medio_espera',     { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento, p_municipios: municipios, p_ubs_reguladora_nomes: ubsReguladoraNomes }),
        supabase.rpc('calcular_taxa_confirmacao_ativa', { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('calcular_taxa_reaproveitamento',  { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento, p_janela_horas: janelaHoras }),
        supabase.rpc('calcular_indice_satisfacao',      { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento }),
        supabase.rpc('calcular_demanda_reprimida',      { p_horizonte_dias: horizonte, p_tipo_atendimento: tipoAtendimento, p_dias_limite: diasLimite, p_municipios: municipios, p_ubs_reguladora_nomes: ubsReguladoraNomes }),
        supabase.rpc('fn_ocupacao_passada',             { p_dias_atras: horizonte,    p_tipo_atendimento: tipoAtendimento, p_municipios: municipios, p_executante_nomes: executanteNomes }),
        supabase.rpc('fn_ocupacao_futura',              { p_dias_a_frente: 7,         p_tipo_atendimento: tipoAtendimento }),
        // Vagas em risco: futuros na janela configurada que ainda não foram confirmados
        supabase
          .from('appointments')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'agendado')
          .gte('scheduled_at', new Date().toISOString())
          .lte('scheduled_at', new Date(Date.now() + vagasRiscoHoras * 3_600_000).toISOString()),
      ])

      // Erros fatais: apenas nas 5 RPCs de negócio principal.
      // satisfacao, demandaReprimida, ocupacaoFutura → degradação graceful (card mostra '—' ou some)
      const anyError = [absenteismo, espera, confirmacao, reaproveitamento, ocupacaoPassada].find(r => r.error)
      if (anyError?.error) throw anyError.error

      const absValue    = absenteismo.data?.taxa_absenteismo     ?? 0
      const esperaValue = espera.data?.espera_atual_dias         ?? 0
      const confValue   = confirmacao.data?.taxa_confirmacao     ?? 0
      const reapValue   = reaproveitamento.data?.taxa_reaproveitamento ?? 0
      // Valores não-críticos: null quando RPC falha → calcularStatus retorna 'sem_dados' → card mostra '—'
      const satValue     = satisfacao.error      ? null : (satisfacao.data?.nota_media             ?? null)
      const demandaValue = demandaReprimida.error ? null : (demandaReprimida.data?.total_reprimida  ?? null)

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

      // Vagas em risco: agendamentos 'agendado' dentro da janela configurável
      const riscoCount = vagasRisco.error ? 0 : (vagasRisco.count ?? 0)

      setMetrics({
        absenteismo:          { valor: absValue,     status: calcularStatus(absValue,     configs.absenteismo_taxa)          },
        espera:               { valor: esperaValue,  status: calcularStatus(esperaValue,  configs.espera_media_dias)         },
        capacidade:           { valor: capValue,     status: calcularStatus(capValue,     configs.capacidade_aproveitamento) },
        // Se fn_ocupacao_futura falhar, null suprime o widget (DashboardPage tem guard '!= null')
        ocupacao_futura:      ocupacaoFutura.error ? null : { valor: futValue, status: calcularStatus(futValue, configs.capacidade_aproveitamento) },
        demanda_reprimida:    { valor: demandaValue, status: calcularStatus(demandaValue, configs.demanda_reprimida_dias)    },
        confirmacao_ativa:    { valor: confValue,    status: calcularStatus(confValue,    configs.confirmacao_ativa_taxa)    },
        reaproveitamento:     { valor: reapValue,    status: calcularStatus(reapValue,    configs.reaproveitamento_taxa)     },
        satisfacao:           { valor: satValue,     status: calcularStatus(satValue,     configs.satisfacao_meta)           },
        vagas_em_risco:       { valor: riscoCount,   status: riscoCount === 0 ? 'ok' : riscoCount <= 3 ? 'atencao' : 'critico' },
        equipamentos_ociosos: { valor: ociosos,      status: ociosos > 0 ? 'atencao' : 'ok' },
      })
    } catch (err) {
      setError(err.message || String(err))
      setMetrics(null)
    } finally {
      setLoading(false)
    }
  }, [horizonte, tipoAtendimento, municipios, executanteNomes, ubsReguladoraNomes, configs])

  // Restaura skeleton quando os parâmetros mudam
  useEffect(() => {
    showSkeletonRef.current = true
    fetch()
  }, [fetch])

  // Ref estável apontando sempre para a função fetch mais recente.
  // Permite criar o canal Realtime uma única vez (sem re-subscrição a cada mudança de deps).
  const fetchRef = useRef(null)
  useEffect(() => { fetchRef.current = fetch }, [fetch])

  // Nome único por instância evita conflito se o hook for usado em múltiplas páginas.
  const channelName = useRef(`dashboard-metrics-rt-${Math.random().toString(36).slice(2, 8)}`).current

  // Realtime: qualquer alteração em appointments ou queue_entries recarrega as métricas.
  // Deps vazios: canal criado uma vez, nunca re-subscrito desnecessariamente.
  useEffect(() => {
    const channel = supabase
      .channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' },  () => fetchRef.current?.())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'queue_entries' }, () => fetchRef.current?.())
      .subscribe()

    return () => { supabase.removeChannel(channel) }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  return { metrics, loading, error, refresh: fetch }
}
