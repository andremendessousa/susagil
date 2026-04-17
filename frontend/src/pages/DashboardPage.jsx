import { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  BarChart, Bar, XAxis, YAxis,
  LineChart, Line, ReferenceLine,
  ResponsiveContainer, Tooltip, Legend, Cell,
} from 'recharts'
import {
  AlertTriangle, Clock, Activity, Users, Zap, Loader, MapPin,
  BarChart2, TrendingDown, Bell, Calendar, Award,
} from 'lucide-react'
import { useKpiConfigs } from '../hooks/useKpiConfigs'
import { useDashboardMetrics } from '../hooks/useDashboardMetrics'
import { useDashboardCharts } from '../hooks/useDashboardCharts'
import { useDashboardChartsV2 } from '../hooks/useDashboardChartsV2'
import { useEscopo } from '../contexts/EscopoContext'
import { MUNICIPIOS_MACRORREGIAO, MUNICIPIO_SEDE } from '../constants/macrorregiao'

// ─── Tooltip customizado pt-BR ────────────────────────────────────────────────
function TooltipBR({ active, payload, label, suffix = '' }) {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
      {label && <p className="font-semibold text-gray-700 mb-1">{label}</p>}
      {payload.map((p, i) => (
        <p key={i} style={{ color: p.color ?? p.fill }}>
          {p.name}: <strong>{Number(p.value).toLocaleString('pt-BR')}{suffix}</strong>
        </p>
      ))}
    </div>
  )
}

// ─── Skeleton de gráfico ──────────────────────────────────────────────────────
function ChartSkeleton() {
  return (
    <div className="animate-pulse space-y-2 pt-2">
      <div className="h-52 bg-gray-100 rounded-lg" />
      <div className="flex gap-2 justify-center">
        <div className="h-3 w-16 bg-gray-100 rounded" />
        <div className="h-3 w-16 bg-gray-100 rounded" />
      </div>
    </div>
  )
}

// ─── ChartCard ────────────────────────────────────────────────────────────────
function ChartCard({ icon: Icon, titulo, pergunta, loading, vazio, children }) {
  return (
    <div className="card p-5">
      <div className="flex items-start gap-2 mb-4">
        <Icon size={15} className="text-blue-700 mt-0.5 flex-shrink-0" />
        <div>
          <h2 className="text-sm font-semibold text-gray-900">{titulo}</h2>
          <p className="text-xs text-gray-400 mt-0.5">{pergunta}</p>
        </div>
      </div>
      {loading ? (
        <ChartSkeleton />
      ) : vazio ? (
        <div className="h-52 flex items-center justify-center text-sm text-gray-400">
          Nenhum dado no período selecionado
        </div>
      ) : (
        children
      )}
    </div>
  )
}

// ─── Estilos por status KPI ───────────────────────────────────────────────────
const STATUS_STYLES = {
  ok:      { border: 'border-l-4 border-green-600', icon: 'text-green-600', bar: 'bg-green-600' },
  atencao: { border: 'border-l-4 border-amber-500', icon: 'text-amber-600', bar: 'bg-amber-500' },
  critico: { border: 'border-l-4 border-red-600',   icon: 'text-red-600',   bar: 'bg-red-600'   },
}

// Calcula largura da barra de progresso — mínimo 2% para ser visível
function calcularBarraPct(valor, config) {
  if (!config || valor == null) return 2
  if (config.direcao === 'menor_melhor') {
    const max = (config.valor_critico ?? config.valor_meta * 2) * 1.2
    return Math.max(Math.min((valor / max) * 100, 100), 2)
  }
  return Math.max(Math.min(valor, 100), 2)
}

// ─── KpiCard ──────────────────────────────────────────────────────────────────

function KpiCard({ config, valor, status, icon: Icon }) {
  const style = STATUS_STYLES[status] || STATUS_STYLES.ok
  const barraPct = calcularBarraPct(valor, config)
  const simboloMeta = config?.direcao === 'maior_melhor' ? '≥' : '≤'
  const valorFormatado = valor != null ? `${valor}${config?.unidade ?? ''}` : '—'

  return (
    <div className={`card p-5 ${style.border}`}>
      <div className="mb-3">
        <Icon
          size={20}
          className={`${style.icon} ${status === 'critico' ? 'animate-pulse' : ''}`}
        />
      </div>
      <p className="text-2xl font-bold text-gray-900 leading-none">{valorFormatado}</p>
      <p className="text-sm font-medium text-gray-700 mt-1">{config?.label ?? '—'}</p>
      <p className="text-xs text-gray-400 mt-0.5">
        Meta: {simboloMeta}{config?.valor_meta ?? '—'}{config?.unidade ?? ''}
      </p>
      <div className="mt-3 h-1.5 w-full bg-gray-100 rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full transition-all duration-500 ${style.bar}`}
          style={{ width: `${barraPct}%` }}
        />
      </div>
    </div>
  )
}

const PERIODOS = [
  { label: '7 dias',  value: 7  },
  { label: '30 dias', value: 30 },
  { label: '90 dias', value: 90 },
]

// ─── DashboardPage ────────────────────────────────────────────────────────────

export default function DashboardPage() {
  const navigate = useNavigate()
  const [horizonte, setHorizonte] = useState(30)
  const [tipoTendencia, setTipoTendencia] = useState(null) // null = todos
  const { isMunicipal, isMacrorregiao } = useEscopo()
  const { configs } = useKpiConfigs()
  const { metrics, loading, error, refresh } = useDashboardMetrics({ horizonte })
  const { charts, loading: loadingCharts } = useDashboardCharts({ horizonte })
  // Hook secundário só para o widget de tendência (filtrável por tipo)
  const { charts: chartsExtra, loading: loadingTendencia } = useDashboardCharts({
    horizonte,
    tipoAtendimento: tipoTendencia,
  })
  const { charts2, loading2: loadingCharts2 } = useDashboardChartsV2({ horizonte })

  const [agora, setAgora] = useState(new Date())
  useEffect(() => {
    const t = setInterval(() => setAgora(new Date()), 60000)
    return () => clearInterval(t)
  }, [])

  const dataAgora = agora.toLocaleDateString('pt-BR', {
    weekday: 'long', day: '2-digit', month: 'long', year: 'numeric',
  })
  const horaAgora = agora.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })

  // ─── Cards de KPI ────────────────────────────────────────────────────────────
  const kpiCards = [
    { chave: 'absenteismo_taxa',          metricKey: 'absenteismo',       icon: Activity },
    { chave: 'espera_media_dias',         metricKey: 'espera',            icon: Clock    },
    { chave: 'capacidade_aproveitamento', metricKey: 'capacidade',        icon: Zap      },
    { chave: 'demanda_reprimida_dias',    metricKey: 'demanda_reprimida', icon: Users    },
  ]

  // Normaliza campos das RPCs para nomes canônicos
  const porLocalData = charts.por_local.map(r => ({
    nome:  r.nome ?? r.equipamento_nome ?? '',
    total: r.total ?? r.realizados ?? 0,
  }))

  // Filtros client-side por escopo geográfico — declarados ANTES de qualquer uso
  const porMunicipioFiltrado = useMemo(() => {
    if (!charts.por_municipio?.length) return []
    const base = isMunicipal
      ? charts.por_municipio.filter(d => d.municipio === MUNICIPIO_SEDE)
      : charts.por_municipio.filter(d => MUNICIPIOS_MACRORREGIAO.includes(d.municipio))
    return base
      .map(r => ({
        municipio: r.municipio,
        urgentes:  r.urgentes  ?? 0,
        rotina:    r.rotina    ?? 0,
        total:     r.total     ?? r.total_encaminhamentos ?? 0,
        uf:        r.uf,
      }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 10)
  }, [charts.por_municipio, isMunicipal])

  // Alias para uso nos gráficos
  const porMunicipioData = porMunicipioFiltrado

  // UBS espera: filtrar por escopo, ordenar por espera DESC
  const ubsEspera = useMemo(() => {
    if (!charts.ubs_menor_espera?.length) return []
    const base = [...charts.ubs_menor_espera]
      .sort((a, b) => b.espera_media_dias - a.espera_media_dias)
      .slice(0, 8)
    if (isMunicipal)
      return base.filter(
        d => d.municipio === MUNICIPIO_SEDE || d.municipio === 'Montes Claros'
      )
    return base
  }, [charts.ubs_menor_espera, isMunicipal])

  // Polo macrorregional — derivado do filtro já aplicado
  const municipiosPolo = useMemo(() =>
    porMunicipioFiltrado
      .map(r => ({ municipio: r.municipio, uf: r.uf, total: r.total }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 8)
  , [porMunicipioFiltrado])
  const totalMunPolo = municipiosPolo.reduce((s, r) => s + r.total, 0)

  // Alertas operacionais
  const absenteismoCritico = metrics?.absenteismo?.status === 'critico'
  const qtdOciosos = (charts.ocupacao_passada ?? []).filter(r => Number(r.pct_ocupacao) < 30).length
  const temAlertas = absenteismoCritico || qtdOciosos > 0

  // Meta de absenteísmo para linha de referência
  const metaAbsenteismo = configs?.absenteismo_taxa?.valor_meta ?? 15

  // ─── Render ───────────────────────────────────────────────────────────────────
  return (
    <div className="space-y-6">

      {/* ── ZONA 0: Header ────────────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">
            Sala de Situação — Regulação de Imagem
          </h1>
          <p className="text-sm text-gray-400 mt-0.5 capitalize">{dataAgora} · {horaAgora}</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <div className="flex rounded-lg overflow-hidden border border-gray-200 bg-white">
            {[
              { dias: 7,  label: '7 dias',  title: 'Visão operacional curta — ideal para gestão diária e alertas imediatos' },
              { dias: 30, label: '30 dias', title: 'Gestão mensal padrão — referência para relatórios e metas mensais (padrão CQH/MS)' },
              { dias: 90, label: '90 dias', title: 'Avaliação trimestral — ciclo de revisão de contratos e metas do edital CPSI' },
            ].map(({ dias, label, title }) => (
              <button
                key={dias}
                title={title}
                onClick={() => setHorizonte(dias)}
                className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                  horizonte === dias
                    ? 'bg-blue-700 text-white'
                    : 'text-gray-600 hover:bg-gray-50'
                }`}
              >
                {label}
              </button>
            ))}
          </div>
          {!loading && (
            <button onClick={refresh} className="btn-ghost text-xs flex items-center gap-1.5">
              <Activity size={14} />
              Atualizar
            </button>
          )}
        </div>
      </div>

      {/* ── ZONA 1: KPI Cards ─────────────────────────────────────────────── */}
      {error ? (
        <div className="card p-5 border-l-4 border-red-600">
          <p className="text-sm text-red-700 font-medium">Erro ao carregar métricas</p>
          <p className="text-xs text-red-500 mt-1">{error}</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {loading
            ? Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className="card p-5 border-l-4 border-gray-200 animate-pulse">
                  <div className="h-4 w-4 bg-gray-200 rounded mb-3" />
                  <div className="h-7 w-20 bg-gray-200 rounded mb-2" />
                  <div className="h-3 w-32 bg-gray-100 rounded mb-1" />
                  <div className="h-2.5 w-24 bg-gray-100 rounded mt-3" />
                </div>
              ))
            : kpiCards.map(({ chave, metricKey, icon }) => (
                <KpiCard
                  key={chave}
                  config={configs?.[chave]}
                  valor={metrics?.[metricKey]?.valor}
                  status={metrics?.[metricKey]?.status ?? 'ok'}
                  icon={icon}
                />
              ))}
        </div>
      )}

      {/* ── Card prospectivo: Ocupação prevista (próximos 7 dias) ─────────── */}
      {!loading && metrics?.ocupacao_futura != null && (
        <div className="rounded-lg border border-blue-200 bg-blue-50 p-4">
          <div className="flex items-center gap-2 text-blue-600 mb-1">
            <Calendar size={16} />
            <span className="text-xs font-medium uppercase tracking-wide">Próximos 7 dias</span>
          </div>
          <div className="text-3xl font-bold text-blue-700">
            {metrics.ocupacao_futura.valor ?? '—'}%
          </div>
          <div className="text-sm text-blue-600">Ocupação prevista</div>
          <div className="text-xs text-blue-400 mt-1">
            Agendamentos confirmados sobre capacidade disponível
          </div>
        </div>
      )}

      {/* ── ZONA 2: Exames por local | Demanda por município ─────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* Card A — Exames por local (BarChart vertical) */}
        <ChartCard
          icon={BarChart2}
          titulo="Exames por local"
          pergunta="Onde estão sendo realizados os exames?"
          loading={loadingCharts}
          vazio={porLocalData.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={porLocalData} margin={{ top: 4, right: 12, bottom: 60, left: 0 }}>
              <XAxis
                dataKey="nome"
                tick={{ fontSize: 11 }}
                tickLine={false}
                angle={-35}
                textAnchor="end"
                interval={0}
                tickFormatter={v => String(v ?? '').slice(0, 20)}
              />
              <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{label}</p>
                      <p className="text-blue-700">
                        <strong>{Number(payload[0]?.value).toLocaleString('pt-BR')}</strong> exames realizados
                      </p>
                    </div>
                  )
                }}
              />
              <Bar dataKey="total" fill="#1d4ed8" name="Exames" radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card B — Demanda por município (macrorregião) | Ocupação (municipal) */}
        {isMacrorregiao ? (
          <ChartCard
            icon={MapPin}
            titulo="Demanda por município"
            pergunta="De onde vêm os pacientes?"
            loading={loadingCharts}
            vazio={porMunicipioData.length === 0}
          >
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={porMunicipioData} margin={{ top: 4, right: 12, bottom: 60, left: 0 }}>
                <XAxis
                  dataKey="municipio"
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                  angle={-35}
                  textAnchor="end"
                  interval={0}
                />
                <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                <Tooltip
                  content={({ active, payload, label }) => {
                    if (!active || !payload?.length) return null
                    const d = payload[0]?.payload ?? {}
                    return (
                      <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                        <p className="font-semibold text-gray-700 mb-1">{label}</p>
                        <p className="text-red-600">Urgente: <strong>{Number(d.urgentes ?? 0).toLocaleString('pt-BR')}</strong></p>
                        <p className="text-blue-600">Rotina: <strong>{Number(d.rotina ?? 0).toLocaleString('pt-BR')}</strong></p>
                        <p className="text-gray-700 mt-1">Total: <strong>{Number(d.total ?? 0).toLocaleString('pt-BR')}</strong></p>
                      </div>
                    )
                  }}
                />
                <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} />
                <Bar dataKey="urgentes" stackId="a" fill="#dc2626" name="Urgente" />
                <Bar dataKey="rotina"   stackId="a" fill="#1d4ed8" name="Rotina" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
        ) : (
          <ChartCard
            icon={BarChart2}
            titulo="Ocupação por equipamento"
            pergunta="Qual equipamento está sendo mais utilizado?"
            loading={loadingCharts}
            vazio={charts.ocupacao_passada.length === 0}
          >
            <ResponsiveContainer width="100%" height={300}>
              <BarChart layout="vertical" data={charts.ocupacao_passada} margin={{ left: 0, right: 50, top: 4, bottom: 4 }}>
                <XAxis type="number" unit="%" domain={[0, 100]} tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                <YAxis type="category" dataKey="equipamento_nome" width={140} tick={{ fontSize: 11 }} tickLine={false} />
                <Tooltip content={(props) => <TooltipBR {...props} suffix="%" />} />
                <ReferenceLine
                  x={85}
                  stroke="#16a34a"
                  strokeDasharray="4 3"
                  label={{ value: 'Meta 85%', position: 'top', fontSize: 10, fill: '#16a34a' }}
                />
                <Bar dataKey="pct_ocupacao" name="Ocupação (%)" radius={[0, 3, 3, 0]}>
                  {charts.ocupacao_passada.map((entry, i) => {
                    const p = Number(entry.pct_ocupacao)
                    return <Cell key={i} fill={p >= 85 ? '#16a34a' : p >= 50 ? '#d97706' : '#dc2626'} />
                  })}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>
        )}
      </div>

      {/* ── ZONA 3: UBS espera média | Tendência absenteísmo ──────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* Card C — Espera média por UBS encaminhadora */}
        <ChartCard
          icon={Clock}
          titulo="Espera média por UBS encaminhadora"
          pergunta="Quais UBS têm maior fila de espera?"
          loading={loadingCharts}
          vazio={charts.ubs_menor_espera.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart layout="vertical" data={ubsEspera} margin={{ left: 0, right: 50, top: 4, bottom: 4 }}>
              <XAxis type="number" unit=" d" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
              <YAxis type="category" dataKey="ubs_nome" width={140} tick={{ fontSize: 11 }} tickLine={false} />
              <Tooltip content={(props) => <TooltipBR {...props} suffix=" dias" />} />
              {ubsEspera[0]?.meta_espera_dias != null && (
                <ReferenceLine
                  x={ubsEspera[0].meta_espera_dias}
                  stroke="#16a34a"
                  strokeDasharray="4 3"
                  label={{
                    value: `Meta ${ubsEspera[0].meta_espera_dias}d`,
                    position: 'top',
                    fontSize: 10,
                    fill: '#16a34a',
                  }}
                />
              )}
              <Bar dataKey="espera_media_dias" fill="#1d4ed8" name="Espera média (dias)" radius={[0, 3, 3, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card D — Tendência de absenteísmo (LineChart dupla + seletor tipo) */}
        <div className="card p-5">
          <div className="flex items-start justify-between gap-2 mb-4">
            <div className="flex items-start gap-2">
              <TrendingDown size={15} className="text-blue-700 mt-0.5 flex-shrink-0" />
              <div>
                <h2 className="text-sm font-semibold text-gray-900">Tendência de absenteísmo</h2>
                <p className="text-xs text-gray-400 mt-0.5">O absenteísmo está melhorando?</p>
              </div>
            </div>
            {/* Seletor de tipo — só no widget de tendência */}
            <div className="flex gap-1 text-xs flex-shrink-0">
              {[
                { value: null,       label: 'Todos'     },
                { value: 'exame',    label: 'Exames'    },
                { value: 'consulta', label: 'Consultas' },
              ].map(({ value, label }) => (
                <button
                  key={label}
                  onClick={() => setTipoTendencia(value)}
                  className={`px-2 py-0.5 rounded ${
                    tipoTendencia === value
                      ? 'bg-blue-600 text-white'
                      : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          </div>
          {loadingTendencia ? (
            <ChartSkeleton />
          ) : chartsExtra.tendencia.length === 0 ? (
            <div className="h-52 flex items-center justify-center text-sm text-gray-400">
              Nenhum dado no período selecionado
            </div>
          ) : (
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={chartsExtra.tendencia} margin={{ top: 8, right: 60, bottom: 4, left: 0 }}>
                <XAxis
                  dataKey="dia"
                  tickFormatter={d => d ? new Date(d).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) : ''}
                  tick={{ fontSize: 11 }}
                  tickLine={false}
                />
                <YAxis domain={[0, 60]} unit="%" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
                <Tooltip content={(props) => <TooltipBR {...props} suffix="%" />} />
                <Legend wrapperStyle={{ fontSize: 11 }} />
                <ReferenceLine
                  y={metaAbsenteismo}
                  stroke="#16a34a"
                  strokeDasharray="4 3"
                  label={{
                    value: `Meta ${metaAbsenteismo}%`,
                    position: 'insideTopRight',
                    fontSize: 10,
                    fill: '#16a34a',
                  }}
                />
                <ReferenceLine
                  y={22}
                  stroke="#9ca3af"
                  strokeDasharray="4 2"
                  label={{
                    value: 'Média SUS 22%',
                    position: 'insideBottomRight',
                    fontSize: 10,
                    fill: '#9ca3af',
                  }}
                />
                <Line
                  type="monotone"
                  dataKey="taxa"
                  stroke="#93c5fd"
                  strokeWidth={1}
                  strokeDasharray="4 3"
                  dot={false}
                  name="Taxa diária (%)"
                  connectNulls={false}
                />
                <Line
                  type="monotone"
                  dataKey="taxa_media_movel"
                  stroke="#1d4ed8"
                  strokeWidth={2.5}
                  dot={false}
                  name="Média móvel 7d (%)"
                  connectNulls={false}
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>
      </div>

      {/* ── ZONA 4: Alerta operacional ───────────────────────────────────── */}
      {!loading && temAlertas && (
        <div className="card p-5">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <AlertTriangle size={16} className="text-red-500" />
              <h2 className="text-sm font-semibold text-gray-900">Requer atenção agora</h2>
            </div>
            <button
              onClick={() => navigate('/notificacoes')}
              className="btn-ghost text-xs flex items-center gap-1.5"
            >
              <Bell size={13} />
              Ver notificações
            </button>
          </div>
          <ul className="space-y-3">
            {absenteismoCritico && (
              <li className="flex items-start gap-3 text-sm">
                <span className="mt-0.5 h-2 w-2 flex-shrink-0 rounded-full bg-red-500" />
                <span className="text-gray-700">
                  <span className="font-semibold text-red-700">Taxa de absenteísmo</span>
                  {' '}acima do limite crítico
                </span>
              </li>
            )}
            {qtdOciosos > 0 && (
              <li className="flex items-start gap-3 text-sm">
                <span className="mt-0.5 h-2 w-2 flex-shrink-0 rounded-full bg-amber-400" />
                <span className="text-gray-700">
                  <span className="font-semibold text-amber-700">
                    {qtdOciosos} equipamento{qtdOciosos > 1 ? 's' : ''}
                  </span>
                  {' '}com capacidade ociosa
                </span>
              </li>
            )}
          </ul>
        </div>
      )}

      {/* ── ZONA 6: Análise de Fila e Desempenho (AssistenteIA Fase 2) ──────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* Card E — Fila ativa por UBS encaminhadora */}
        <ChartCard
          icon={Users}
          titulo="Volume de fila por UBS"
          pergunta="Quais UBSs têm mais pacientes aguardando?"
          loading={loadingCharts2}
          vazio={charts2.fila_por_ubs.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart
              layout="vertical"
              data={charts2.fila_por_ubs.slice(0, 10)}
              margin={{ left: 0, right: 50, top: 4, bottom: 4 }}
            >
              <XAxis
                type="number"
                tick={{ fontSize: 11 }}
                tickLine={false}
                axisLine={false}
              />
              <YAxis
                type="category"
                dataKey="ubs_nome"
                width={150}
                tick={{ fontSize: 11 }}
                tickLine={false}
                tickFormatter={v => String(v ?? '').slice(0, 22)}
              />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null
                  const d = payload[0]?.payload ?? {}
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{label}</p>
                      <p className="text-blue-700">Aguardando: <strong>{Number(d.total_aguardando ?? 0).toLocaleString('pt-BR')}</strong></p>
                      <p className="text-gray-500">{d.pct_do_total ?? 0}% do total · Espera média: {d.espera_media_dias ?? 0}d</p>
                    </div>
                  )
                }}
              />
              <Bar dataKey="total_aguardando" name="Pacientes" fill="#1d4ed8" radius={[0, 3, 3, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card F — Agenda comprometida por clínica/equipamento */}
        <ChartCard
          icon={Activity}
          titulo="Carga de agenda por equipamento"
          pergunta="Qual clínica está mais sobrecarregada?"
          loading={loadingCharts2}
          vazio={charts2.fila_por_clinica.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart
              layout="vertical"
              data={charts2.fila_por_clinica.slice(0, 10)}
              margin={{ left: 0, right: 50, top: 4, bottom: 4 }}
            >
              <XAxis
                type="number"
                unit="%"
                domain={[0, 100]}
                tick={{ fontSize: 11 }}
                tickLine={false}
                axisLine={false}
              />
              <YAxis
                type="category"
                dataKey="equipamento_nome"
                width={150}
                tick={{ fontSize: 11 }}
                tickLine={false}
                tickFormatter={v => String(v ?? '').slice(0, 22)}
              />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null
                  const d = payload[0]?.payload ?? {}
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{label}</p>
                      <p className="text-gray-500 mb-1">{d.unidade_nome} · {d.municipio}</p>
                      <p className="text-blue-700">
                        <strong>{Number(d.vagas_comprometidas ?? 0).toLocaleString('pt-BR')}</strong> vagas/{Number(d.capacidade_periodo ?? 0).toLocaleString('pt-BR')} cap.
                      </p>
                      <p className="text-gray-600">Carga: <strong>{d.pct_carga_fila ?? 0}%</strong></p>
                    </div>
                  )
                }}
              />
              <ReferenceLine
                x={85}
                stroke="#16a34a"
                strokeDasharray="4 3"
                label={{ value: 'Meta 85%', position: 'top', fontSize: 10, fill: '#16a34a' }}
              />
              <Bar dataKey="pct_carga_fila" name="Carga (%)" radius={[0, 3, 3, 0]}>
                {charts2.fila_por_clinica.slice(0, 10).map((entry, i) => {
                  const p = Number(entry.pct_carga_fila)
                  return <Cell key={i} fill={p >= 85 ? '#16a34a' : p >= 50 ? '#d97706' : '#dc2626'} />
                })}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* Card G — Score de desempenho por UBS */}
        <ChartCard
          icon={Award}
          titulo="Ranking de desempenho por UBS"
          pergunta="Qual UBS combina menos faltas e menor espera?"
          loading={loadingCharts2}
          vazio={charts2.desempenho_ubs.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart
              layout="vertical"
              data={charts2.desempenho_ubs.slice(0, 10)}
              margin={{ left: 0, right: 50, top: 4, bottom: 4 }}
            >
              <XAxis
                type="number"
                domain={[0, 100]}
                tick={{ fontSize: 11 }}
                tickLine={false}
                axisLine={false}
              />
              <YAxis
                type="category"
                dataKey="ubs_nome"
                width={150}
                tick={{ fontSize: 11 }}
                tickLine={false}
                tickFormatter={v => String(v ?? '').slice(0, 22)}
              />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null
                  const d = payload[0]?.payload ?? {}
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{label}</p>
                      <p className="text-blue-700">Score: <strong>{d.score_composto ?? 0}</strong>/100</p>
                      <p className="text-gray-500">Absenteísmo: {d.absenteismo_pct ?? 0}% · Espera: {d.espera_media_dias ?? 0}d</p>
                      <p className="text-gray-500">{Number(d.total_atendidos ?? 0).toLocaleString('pt-BR')} atendidos</p>
                    </div>
                  )
                }}
              />
              <Bar dataKey="score_composto" name="Score" radius={[0, 3, 3, 0]}>
                {charts2.desempenho_ubs.slice(0, 10).map((entry, i) => {
                  const s = Number(entry.score_composto)
                  return <Cell key={i} fill={s >= 80 ? '#16a34a' : s >= 60 ? '#d97706' : '#dc2626'} />
                })}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card H — Tipos de exame mais solicitados */}
        <ChartCard
          icon={BarChart2}
          titulo="Procedimentos mais solicitados"
          pergunta="Quais exames têm maior demanda na fila?"
          loading={loadingCharts2}
          vazio={charts2.tipos_exame.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart
              data={charts2.tipos_exame.slice(0, 10)}
              margin={{ top: 4, right: 12, bottom: 60, left: 0 }}
            >
              <XAxis
                dataKey="tipo_exame"
                tick={{ fontSize: 10 }}
                tickLine={false}
                angle={-35}
                textAnchor="end"
                interval={0}
                tickFormatter={v => String(v ?? '').slice(0, 18)}
              />
              <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
              <Tooltip
                content={({ active, payload, label }) => {
                  if (!active || !payload?.length) return null
                  const d = payload[0]?.payload ?? {}
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{label}</p>
                      <p className="text-blue-700">
                        <strong>{Number(d.total_solicitacoes ?? 0).toLocaleString('pt-BR')}</strong> solicitações ({d.pct_do_total ?? 0}%)
                      </p>
                      <p className="text-gray-500">Espera média: {d.espera_media_dias ?? 0} dias</p>
                    </div>
                  )
                }}
              />
              <Bar dataKey="total_solicitacoes" fill="#1d4ed8" name="Solicitações" radius={[3, 3, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>
      </div>

      {/* Card I — Espera média e absenteísmo por município */}
      <ChartCard
        icon={Clock}
        titulo="Espera e absenteísmo por município"
        pergunta="Qual município tem maior tempo de espera?"
        loading={loadingCharts2}
        vazio={charts2.espera_municipio.length === 0}
      >
        <ResponsiveContainer width="100%" height={320}>
          <BarChart
            data={charts2.espera_municipio.slice(0, 15)}
            margin={{ top: 4, right: 12, bottom: 60, left: 0 }}
          >
            <XAxis
              dataKey="municipio"
              tick={{ fontSize: 11 }}
              tickLine={false}
              angle={-35}
              textAnchor="end"
              interval={0}
            />
            <YAxis tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
            <Tooltip
              content={({ active, payload, label }) => {
                if (!active || !payload?.length) return null
                const d = payload[0]?.payload ?? {}
                return (
                  <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                    <p className="font-semibold text-gray-700 mb-1">{label}</p>
                    <p className="text-blue-700">Espera média: <strong>{d.espera_media_dias ?? 0} dias</strong></p>
                    <p className="text-gray-500">Absenteísmo: {d.pct_absenteismo ?? 0}%</p>
                    <p className="text-gray-500">{Number(d.total_pacientes ?? 0).toLocaleString('pt-BR')} pacientes</p>
                  </div>
                )
              }}
            />
            <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} />
            <Bar dataKey="espera_media_dias" fill="#1d4ed8" name="Espera média (dias)" radius={[3, 3, 0, 0]} />
            <Bar dataKey="pct_absenteismo" fill="#dc2626" name="Absenteísmo (%)" radius={[3, 3, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </ChartCard>
      {/* ── ZONA 5: Polo macrorregional (apenas modo macrorregião) ─────────── */}
      {isMacrorregiao && (
      <div className="card">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <MapPin size={15} className="text-blue-700" />
            <h2 className="text-sm font-semibold text-gray-900">Polo macrorregional</h2>
          </div>
          {loadingCharts && <Loader size={14} className="animate-spin text-gray-400" />}
        </div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-xs text-gray-500 uppercase tracking-wide">
            <tr>
              <th className="px-5 py-3 text-left">Município</th>
              <th className="px-5 py-3 text-right">UF</th>
              <th className="px-5 py-3 text-right">Encaminhamentos</th>
              <th className="px-5 py-3 text-right">% do total</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {municipiosPolo.map((row) => {
              const pct = totalMunPolo > 0 ? ((row.total / totalMunPolo) * 100).toFixed(1) : '0.0'
              return (
                <tr key={row.municipio} className="hover:bg-gray-50 transition-colors">
                  <td className="px-5 py-3 font-medium text-gray-900">{row.municipio}</td>
                  <td className="px-5 py-3 text-right text-gray-400">{row.uf ?? '—'}</td>
                  <td className="px-5 py-3 text-right font-semibold text-gray-700">
                    {Number(row.total).toLocaleString('pt-BR')}
                  </td>
                  <td className="px-5 py-3 text-right text-gray-400">{pct}%</td>
                </tr>
              )
            })}
            {!loadingCharts && municipiosPolo.length === 0 && (
              <tr>
                <td colSpan={4} className="px-5 py-8 text-center text-gray-400 text-sm">
                  Nenhum dado no período selecionado
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      )}
    </div>
  )
}
