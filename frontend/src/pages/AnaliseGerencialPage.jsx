import { useState, useEffect } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, ReferenceLine,
  PieChart, Pie,
  ResponsiveContainer, Tooltip, Legend, Cell,
} from 'recharts'
import { BarChart2, Clock, PieChart as PieChartIcon, RotateCcw } from 'lucide-react'
import { useDashboardCharts } from '../hooks/useDashboardCharts'
import { useKpiConfigs } from '../hooks/useKpiConfigs'
import { supabase } from '../lib/supabase'

const PERIODOS = [
  { label: '7 dias',  value: 7  },
  { label: '30 dias', value: 30 },
  { label: '90 dias', value: 90 },
]

// Identidade visual fixa por prioridade clínica (não são metas, são cores semânticas do sistema)
const RISCO_COLORS = {
  azul:     '#2563eb',
  vermelho: '#dc2626',
  amarelo:  '#ca8a04',
  verde:    '#16a34a',
}

const RISCO_LABELS = {
  azul:     'Urgente (azul)',
  vermelho: 'Prioritário (vermelho)',
  amarelo:  'Intermediário (amarelo)',
  verde:    'Eletivo (verde)',
}

const STATUS_BADGE = {
  ok:      { label: 'Dentro da meta', className: 'bg-green-100 text-green-700' },
  atencao: { label: 'Atenção',        className: 'bg-amber-100 text-amber-700' },
  critico: { label: 'Crítico',        className: 'bg-red-100 text-red-700'     },
}

function esperaStatus(espera, meta) {
  if (!meta) return 'ok'
  if (espera > meta * 1.5) return 'critico'
  if (espera > meta) return 'atencao'
  return 'ok'
}

function PanelCard({ icon: Icon, titulo, subtitulo, loading, vazio, children }) {
  return (
    <div className="card p-5">
      <div className="flex items-start gap-2 mb-4">
        <Icon size={15} className="text-blue-700 mt-0.5 flex-shrink-0" />
        <div>
          <h2 className="text-sm font-semibold text-gray-900">{titulo}</h2>
          <p className="text-xs text-gray-400 mt-0.5">{subtitulo}</p>
        </div>
      </div>
      {loading ? (
        <div className="animate-pulse">
          <div className="h-52 bg-gray-100 rounded-lg" />
        </div>
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

export default function AnaliseGerencialPage() {
  const [horizonte, setHorizonte] = useState(30)
  const { charts, loading: loadingCharts } = useDashboardCharts({ horizonte })
  const { configs } = useKpiConfigs()

  // ─── Painel 3: Distribuição de prioridade na fila ─────────────────────────
  const [filaDist, setFilaDist] = useState([])
  const [loadingFila, setLoadingFila] = useState(true)

  useEffect(() => {
    let mounted = true
    async function fetchFila() {
      setLoadingFila(true)
      try {
        const { data } = await supabase
          .from('queue_entries')
          .select('cor_risco')
          .eq('status_local', 'aguardando')

        if (!mounted) return

        const grouped = { azul: 0, vermelho: 0, amarelo: 0, verde: 0 }
        for (const row of data ?? []) {
          const key = row.cor_risco?.toLowerCase()
          if (key in grouped) grouped[key]++
        }

        setFilaDist(
          Object.entries(grouped)
            .filter(([, v]) => v > 0)
            .map(([cor, value]) => ({
              name:  RISCO_LABELS[cor] ?? cor,
              value,
              fill:  RISCO_COLORS[cor] ?? '#6b7280',
            }))
        )
      } finally {
        if (mounted) setLoadingFila(false)
      }
    }
    fetchFila()
    return () => { mounted = false }
  }, [])

  // ─── Painel 4: Reaproveitamento de vagas ─────────────────────────────────
  const [reaprovData, setReaprovData] = useState({ faltas: 0, reaproveitados: 0 })
  const [loadingReaprov, setLoadingReaprov] = useState(true)

  useEffect(() => {
    let mounted = true
    async function fetchReaprov() {
      setLoadingReaprov(true)
      try {
        const dataLimite = new Date(Date.now() - horizonte * 24 * 60 * 60 * 1000).toISOString()

        const [faltasRes, reaprovRes] = await Promise.all([
          supabase
            .from('appointments')
            .select('id', { count: 'exact', head: true })
            .eq('status', 'faltou')
            .gte('scheduled_at', dataLimite),
          supabase
            .from('appointments')
            .select('id', { count: 'exact', head: true })
            .not('reaproveitado_de_id', 'is', null)
            .gte('scheduled_at', dataLimite),
        ])

        if (!mounted) return
        setReaprovData({
          faltas:         faltasRes.count ?? 0,
          reaproveitados: reaprovRes.count ?? 0,
        })
      } finally {
        if (mounted) setLoadingReaprov(false)
      }
    }
    fetchReaprov()
    return () => { mounted = false }
  }, [horizonte])

  const taxaReaprov = reaprovData.faltas > 0
    ? ((reaprovData.reaproveitados / reaprovData.faltas) * 100).toFixed(1)
    : '0.0'
  const taxaReaprovNum = parseFloat(taxaReaprov)
  const metaReaprov    = configs?.reaproveitamento_taxa?.valor_meta ?? 70

  const reaprovBarColor =
    taxaReaprovNum >= metaReaprov            ? '#16a34a' :
    taxaReaprovNum >= metaReaprov * 0.7      ? '#ca8a04' :
                                               '#dc2626'

  // Dados painel 2: ordenar por espera_media_dias DESC
  const ubsOrdenada = [...charts.ubs_menor_espera]
    .sort((a, b) => b.espera_media_dias - a.espera_media_dias)

  return (
    <div className="space-y-6">

      {/* ── Header ────────────────────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Análise Gerencial</h1>
          <p className="text-sm text-gray-500 mt-0.5">Identifique causas e tome ação</p>
        </div>
        <div className="flex rounded-lg overflow-hidden border border-gray-200 bg-white">
          {PERIODOS.map(p => (
            <button
              key={p.value}
              onClick={() => setHorizonte(p.value)}
              className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                horizonte === p.value
                  ? 'bg-blue-700 text-white'
                  : 'text-gray-600 hover:bg-gray-50'
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Grid 2×2 ──────────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">

        {/* ── Painel 1: Absenteísmo por executante ────────────────────────── */}
        <PanelCard
          icon={BarChart2}
          titulo="Absenteísmo por unidade executante"
          subtitulo="Qual hospital/clínica tem maior taxa de falta?"
          loading={loadingCharts}
          vazio={charts.absenteismo_executante.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <BarChart
              layout="vertical"
              data={charts.absenteismo_executante}
              margin={{ left: 0, right: 50, top: 4, bottom: 4 }}
            >
              <XAxis
                type="number"
                domain={[0, 100]}
                unit="%"
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
              />
              <Tooltip
                content={({ active, payload }) => {
                  if (!active || !payload?.length) return null
                  const d = payload[0]?.payload
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{d?.equipamento_nome}</p>
                      <p className="text-gray-700">
                        <strong>{Number(d?.taxa_absenteismo).toLocaleString('pt-BR')}%</strong> de absenteísmo
                      </p>
                      <p className="text-gray-500 mt-0.5">
                        {Number(d?.total_finalizados).toLocaleString('pt-BR')} finalizados
                      </p>
                    </div>
                  )
                }}
              />
              {charts.absenteismo_executante[0]?.meta_absenteismo != null && (
                <ReferenceLine
                  x={charts.absenteismo_executante[0].meta_absenteismo}
                  stroke="#16a34a"
                  strokeDasharray="4 3"
                  label={{
                    value: `Meta ${charts.absenteismo_executante[0].meta_absenteismo}%`,
                    position: 'top',
                    fontSize: 10,
                    fill: '#16a34a',
                  }}
                />
              )}
              <Bar dataKey="taxa_absenteismo" radius={[0, 3, 3, 0]}>
                {charts.absenteismo_executante.map((entry, i) => {
                  const taxa = Number(entry.taxa_absenteismo)
                  const meta = Number(entry.meta_absenteismo)
                  const color = taxa > meta * 2 ? '#dc2626' : taxa > meta ? '#ca8a04' : '#16a34a'
                  return <Cell key={i} fill={color} />
                })}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </PanelCard>

        {/* ── Painel 2: Espera por UBS encaminhadora (tabela) ─────────────── */}
        <PanelCard
          icon={Clock}
          titulo="Tempo de espera por UBS encaminhadora"
          subtitulo="De onde vêm os pacientes que mais esperam?"
          loading={loadingCharts}
          vazio={charts.ubs_menor_espera.length === 0}
        >
          <div className="overflow-auto max-h-72">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 text-gray-500 uppercase tracking-wide sticky top-0">
                <tr>
                  <th className="px-3 py-2 text-left">UBS</th>
                  <th className="px-3 py-2 text-left">Município</th>
                  <th className="px-3 py-2 text-right">Encaminhamentos</th>
                  <th className="px-3 py-2 text-right">Espera média</th>
                  <th className="px-3 py-2 text-right">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {ubsOrdenada.map((row, i) => {
                  const st    = esperaStatus(row.espera_media_dias, row.meta_espera_dias)
                  const badge = STATUS_BADGE[st]
                  return (
                    <tr key={i} className="hover:bg-gray-50 transition-colors">
                      <td className="px-3 py-2 font-medium text-gray-900">{row.ubs_nome}</td>
                      <td className="px-3 py-2 text-gray-500">{row.municipio}</td>
                      <td className="px-3 py-2 text-right text-gray-700">
                        {Number(row.total_encaminhamentos).toLocaleString('pt-BR')}
                      </td>
                      <td className="px-3 py-2 text-right font-semibold text-gray-700">
                        {Number(row.espera_media_dias).toLocaleString('pt-BR')}d
                      </td>
                      <td className="px-3 py-2 text-right">
                        <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${badge.className}`}>
                          {badge.label}
                        </span>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </PanelCard>

        {/* ── Painel 3: Distribuição de prioridade na fila (donut) ────────── */}
        <PanelCard
          icon={PieChartIcon}
          titulo="Prioridade na fila atual"
          subtitulo="Temos urgências represadas?"
          loading={loadingFila}
          vazio={filaDist.length === 0}
        >
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={filaDist}
                dataKey="value"
                nameKey="name"
                innerRadius={70}
                outerRadius={110}
                paddingAngle={2}
              >
                {filaDist.map((entry, i) => (
                  <Cell key={i} fill={entry.fill} />
                ))}
              </Pie>
              <Tooltip
                content={({ active, payload }) => {
                  if (!active || !payload?.length) return null
                  const p = payload[0]
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold mb-1" style={{ color: p.payload.fill }}>{p.name}</p>
                      <p className="text-gray-700">
                        <strong>{Number(p.value).toLocaleString('pt-BR')}</strong> pacientes
                      </p>
                    </div>
                  )
                }}
              />
              <Legend
                iconType="circle"
                iconSize={8}
                wrapperStyle={{ fontSize: '11px' }}
              />
            </PieChart>
          </ResponsiveContainer>
        </PanelCard>

        {/* ── Painel 4: Reaproveitamento de vagas ─────────────────────────── */}
        <PanelCard
          icon={RotateCcw}
          titulo="Reaproveitamento de vagas"
          subtitulo="Estamos recuperando vagas perdidas?"
          loading={loadingReaprov}
          vazio={false}
        >
          <div className="flex flex-col items-center justify-center h-52 gap-5">
            <div className="text-center">
              <p
                className="text-5xl font-bold leading-none"
                style={{ color: reaprovBarColor }}
              >
                {taxaReaprov}%
              </p>
              <p className="text-sm text-gray-500 mt-2">
                {Number(reaprovData.reaproveitados).toLocaleString('pt-BR')} vagas recuperadas
                {' '}de{' '}
                {Number(reaprovData.faltas).toLocaleString('pt-BR')} faltas
              </p>
            </div>
            <div className="w-full max-w-xs">
              <div className="flex justify-between text-xs text-gray-500 mb-1.5">
                <span>Taxa de reaproveitamento</span>
                <span className="font-medium">Meta ≥{metaReaprov}%</span>
              </div>
              <div className="h-3 bg-gray-100 rounded-full overflow-hidden">
                <div
                  className="h-full rounded-full transition-all duration-500"
                  style={{
                    width: `${Math.min(taxaReaprovNum, 100)}%`,
                    backgroundColor: reaprovBarColor,
                  }}
                />
              </div>
            </div>
          </div>
        </PanelCard>

      </div>
    </div>
  )
}
