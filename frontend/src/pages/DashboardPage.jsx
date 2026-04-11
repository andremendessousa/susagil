import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  PieChart, Pie, Cell, Tooltip, Legend, Label,
  BarChart, Bar, XAxis, YAxis,
  AreaChart, Area, ReferenceLine,
  ResponsiveContainer,
} from 'recharts'
import {
  AlertTriangle, Clock, Activity, Users, Zap, Loader, MapPin,
  BarChart2, PieChart as PieChartIcon, TrendingDown, Bell,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useKpiConfigs } from '../hooks/useKpiConfigs'
import { useDashboardMetrics } from '../hooks/useDashboardMetrics'
import { useDashboardCharts } from '../hooks/useDashboardCharts'

// ─── Paleta dos gráficos ──────────────────────────────────────────────────────
const PIE_COLORS = ['#1d4ed8', '#059669', '#d97706', '#7c3aed', '#db2777', '#0891b2', '#65a30d']

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

// ─── DashboardPage ────────────────────────────────────────────────────────────

export default function DashboardPage() {
  const navigate = useNavigate()
  const { configs } = useKpiConfigs()
  const { metrics, loading, error, refresh } = useDashboardMetrics()
  const { charts, loading: loadingCharts, periodo, setPeriodo } = useDashboardCharts()

  // Relógio atualizado a cada minuto
  const [agora, setAgora] = useState(new Date())
  useEffect(() => {
    const t = setInterval(() => setAgora(new Date()), 60000)
    return () => clearInterval(t)
  }, [])

  // Polo macrorregional (estado atual da fila, sem filtro de período)
  const [municipios, setMunicipios] = useState([])
  const [loadingMunicipios, setLoadingMunicipios] = useState(true)

  useEffect(() => {
    async function fetchMunicipios() {
      setLoadingMunicipios(true)
      const { data } = await supabase
        .from('v_dashboard_fila')
        .select('municipio_paciente, status_local')

      const map = {}
      for (const row of data || []) {
        const m = row.municipio_paciente || 'Desconhecido'
        if (!map[m]) map[m] = { municipio_paciente: m, aguardando: 0, agendado: 0, total: 0 }
        map[m].total++
        if (row.status_local === 'aguardando') map[m].aguardando++
        if (row.status_local === 'agendado') map[m].agendado++
      }

      setMunicipios(
        Object.values(map)
          .sort((a, b) => b.total - a.total)
          .slice(0, 8)
      )
      setLoadingMunicipios(false)
    }
    fetchMunicipios()
  }, [])

  const totalMun = municipios.reduce((s, r) => s + r.total, 0)
  const totalExamesA = charts.A.reduce((s, r) => s + r.total, 0)
  const metaAbsenteismo = configs?.absenteismo_taxa?.valor_meta ?? 15

  // ─── Cards de KPI ────────────────────────────────────────────────────────────
  const kpiCards = [
    { chave: 'absenteismo_taxa',          metricKey: 'absenteismo',       icon: Activity },
    { chave: 'espera_media_dias',         metricKey: 'espera',            icon: Clock    },
    { chave: 'capacidade_aproveitamento', metricKey: 'capacidade',        icon: Zap      },
    { chave: 'demanda_reprimida_dias',    metricKey: 'demanda_reprimida', icon: Users    },
  ]

  // ─── Alertas ──────────────────────────────────────────────────────────────────
  const vagasEmRisco = metrics?.vagas_em_risco?.valor ?? 0
  const qtdOciosos   = metrics?.equipamentos_ociosos?.valor ?? 0
  const horasRisco   = configs?.vagas_risco_horas?.valor_meta ?? 48
  const temAlertas   = vagasEmRisco > 0 || qtdOciosos > 0

  const PERIODOS = [
    { label: '7 dias',  value: 7  },
    { label: '30 dias', value: 30 },
    { label: '90 dias', value: 90 },
  ]

  const dataAgora = agora.toLocaleDateString('pt-BR', {
    weekday: 'long', day: '2-digit', month: 'long', year: 'numeric',
  })
  const horaAgora = agora.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })

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
            {PERIODOS.map(p => (
              <button
                key={p.value}
                onClick={() => setPeriodo(p.value)}
                className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                  periodo === p.value
                    ? 'bg-blue-700 text-white'
                    : 'text-gray-600 hover:bg-gray-50'
                }`}
              >
                {p.label}
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

      {/* ── ZONA 2: Gráficos 2×2 ──────────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* Card A — Exames por local (Donut) */}
        <ChartCard
          icon={PieChartIcon}
          titulo="Exames por local"
          pergunta="Onde estão sendo realizados os exames?"
          loading={loadingCharts}
          vazio={charts.A.length === 0}
        >
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie
                data={charts.A}
                dataKey="total"
                nameKey="nome"
                innerRadius={60}
                outerRadius={90}
                paddingAngle={2}
              >
                {charts.A.map((_, i) => (
                  <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                ))}
                <Label
                  content={({ viewBox }) => {
                    const { cx, cy } = viewBox
                    return (
                      <text x={cx} y={cy} textAnchor="middle" dominantBaseline="middle">
                        <tspan
                          x={cx} dy="-0.35em"
                          style={{ fontSize: '1.5rem', fontWeight: '700', fill: '#111827' }}
                        >
                          {totalExamesA.toLocaleString('pt-BR')}
                        </tspan>
                        <tspan
                          x={cx} dy="1.5em"
                          style={{ fontSize: '0.65rem', fill: '#9ca3af' }}
                        >
                          exames
                        </tspan>
                      </text>
                    )
                  }}
                  position="center"
                />
              </Pie>
              <Tooltip content={(props) => <TooltipBR {...props} />} />
              <Legend
                iconType="circle"
                iconSize={8}
                wrapperStyle={{ fontSize: '11px' }}
              />
            </PieChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card B — Demanda por município (barras horizontais) */}
        <ChartCard
          icon={MapPin}
          titulo="Demanda por município"
          pergunta="De onde vêm os pacientes?"
          loading={loadingCharts}
          vazio={charts.B.length === 0}
        >
          <ResponsiveContainer width="100%" height={260}>
            <BarChart layout="vertical" data={charts.B} margin={{ left: 0, right: 12, top: 4, bottom: 4 }}>
              <XAxis type="number" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
              <YAxis type="category" dataKey="municipio" width={100} tick={{ fontSize: 11 }} tickLine={false} />
              <Tooltip content={(props) => <TooltipBR {...props} />} />
              <Bar dataKey="urgentes" stackId="a" fill="#dc2626" name="Urgentes" radius={0} />
              <Bar dataKey="rotina"   stackId="a" fill="#1d4ed8" name="Rotina"   radius={[0, 3, 3, 0]} />
              <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: '11px' }} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card C — UBS com mais encaminhamentos (barras horizontais) */}
        <ChartCard
          icon={BarChart2}
          titulo="UBS com mais encaminhamentos"
          pergunta="Quais UBS geram mais demanda?"
          loading={loadingCharts}
          vazio={charts.C.length === 0}
        >
          <ResponsiveContainer width="100%" height={260}>
            <BarChart layout="vertical" data={charts.C} margin={{ left: 0, right: 12, top: 4, bottom: 4 }}>
              <XAxis type="number" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
              <YAxis type="category" dataKey="ubs" width={140} tick={{ fontSize: 11 }} tickLine={false} />
              <Tooltip content={(props) => <TooltipBR {...props} />} />
              <Bar dataKey="rotina"   stackId="a" fill="#bfdbfe" name="Rotina"   radius={0} />
              <Bar dataKey="urgentes" stackId="a" fill="#dc2626" name="Urgentes" radius={[0, 3, 3, 0]} />
              <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: '11px' }} />
            </BarChart>
          </ResponsiveContainer>
        </ChartCard>

        {/* Card D — Tendência de absenteísmo (área + linha de meta) */}
        <ChartCard
          icon={TrendingDown}
          titulo="Tendência de absenteísmo"
          pergunta="O absenteísmo está melhorando?"
          loading={loadingCharts}
          vazio={charts.D.length === 0}
        >
          <ResponsiveContainer width="100%" height={260}>
            <AreaChart data={charts.D} margin={{ top: 8, right: 12, bottom: 4, left: 0 }}>
              <defs>
                <linearGradient id="gradAbsenteismo" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%"  stopColor="#1d4ed8" stopOpacity={0.15} />
                  <stop offset="95%" stopColor="#1d4ed8" stopOpacity={0}    />
                </linearGradient>
              </defs>
              <XAxis dataKey="semana" tick={{ fontSize: 11 }} tickLine={false} />
              <YAxis unit="%" tick={{ fontSize: 11 }} tickLine={false} axisLine={false} />
              <Tooltip content={(props) => <TooltipBR {...props} suffix="%" />} />
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
              <Area
                type="monotone"
                dataKey="taxa"
                stroke="#1d4ed8"
                strokeWidth={2}
                fill="url(#gradAbsenteismo)"
                dot={{ r: 3, fill: '#1d4ed8' }}
                name="Taxa (%)"
              />
            </AreaChart>
          </ResponsiveContainer>
        </ChartCard>

      </div>

      {/* ── ZONA 3: Alertas operacionais ─────────────────────────────────── */}
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
            {vagasEmRisco > 0 && (
              <li className="flex items-start gap-3 text-sm">
                <span className="mt-0.5 h-2 w-2 flex-shrink-0 rounded-full bg-red-500" />
                <span className="text-gray-700">
                  <span className="font-semibold text-red-700">
                    {vagasEmRisco} vaga{vagasEmRisco > 1 ? 's' : ''}
                  </span>
                  {' '}sem confirmação nas próximas{' '}
                  <span className="font-medium">{horasRisco}h</span>
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
                  {' '}ativo{qtdOciosos > 1 ? 's' : ''} com ocupação abaixo de 30%
                </span>
              </li>
            )}
          </ul>
        </div>
      )}

      {/* ── ZONA 4: Polo macrorregional ───────────────────────────────────── */}
      <div className="card">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <MapPin size={15} className="text-blue-700" />
            <h2 className="text-sm font-semibold text-gray-900">Polo macrorregional</h2>
          </div>
          {loadingMunicipios && <Loader size={14} className="animate-spin text-gray-400" />}
        </div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-xs text-gray-500 uppercase tracking-wide">
            <tr>
              <th className="px-5 py-3 text-left">Município</th>
              <th className="px-5 py-3 text-right">Aguardando</th>
              <th className="px-5 py-3 text-right">Agendado</th>
              <th className="px-5 py-3 text-right">Total</th>
              <th className="px-5 py-3 text-right">% do total</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {municipios.map((row) => {
              const isOutro = row.municipio_paciente !== 'Montes Claros'
              const pctTotal = totalMun > 0
                ? ((row.total / totalMun) * 100).toFixed(1)
                : '0.0'
              return (
                <tr key={row.municipio_paciente} className="hover:bg-gray-50 transition-colors">
                  <td className={`px-5 py-3 font-medium ${isOutro ? 'text-blue-700' : 'text-gray-900'}`}>
                    {row.municipio_paciente}
                  </td>
                  <td className="px-5 py-3 text-right text-gray-500">{row.aguardando}</td>
                  <td className="px-5 py-3 text-right text-gray-500">{row.agendado}</td>
                  <td className="px-5 py-3 text-right font-semibold text-gray-700">{row.total}</td>
                  <td className="px-5 py-3 text-right text-gray-400">{pctTotal}%</td>
                </tr>
              )
            })}
            {!loadingMunicipios && municipios.length === 0 && (
              <tr>
                <td colSpan={5} className="px-5 py-8 text-center text-gray-400 text-sm">
                  Nenhum dado disponível
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
