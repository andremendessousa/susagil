import { useState } from 'react'
import {
  BarChart, Bar, XAxis, YAxis, ReferenceLine,
  ResponsiveContainer, Tooltip, Cell,
} from 'recharts'
import { Activity } from 'lucide-react'
import { useEquipment } from '../hooks/useEquipment'
import { useKpiConfigs } from '../hooks/useKpiConfigs'

const PERIODOS = [
  { label: '7 dias',  value: 7  },
  { label: '30 dias', value: 30 },
  { label: '90 dias', value: 90 },
]

function barColor(pct) {
  if (pct >= 85) return '#16a34a'
  if (pct >= 50) return '#ca8a04'
  return '#dc2626'
}

function badgeInfo(pct) {
  if (pct >= 85) return { label: 'Sobrecarregado', className: 'bg-green-100 text-green-700' }
  if (pct >= 50) return { label: 'Normal',         className: 'bg-amber-100 text-amber-700' }
  return           { label: 'Ocioso',              className: 'bg-red-100 text-red-700'    }
}

function ChartSkeleton() {
  return (
    <div className="animate-pulse">
      <div className="h-64 bg-gray-100 rounded-lg" />
    </div>
  )
}

export default function MaquinasPage() {
  const [horizonte, setHorizonte] = useState(30)
  const { equipment, loading } = useEquipment({ horizonte })
  const { configs } = useKpiConfigs()

  const metaCapacidade = configs?.capacidade_aproveitamento?.valor_meta ?? 85

  const chartData = equipment.map(e => ({
    nome:       String(e.equipamento_nome ?? '').slice(0, 25),
    pct:        Number(e.pct_ocupacao) || 0,
    realizados: Number(e.exames_realizados) || 0,
    capacidade: Number(e.capacidade_total) || 0,
  }))

  return (
    <div className="space-y-6">

      {/* ── Header ────────────────────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Equipamentos</h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Ocupação dos aparelhos nos últimos {horizonte} dias
          </p>
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

      {/* ── ZONA 1: Gráfico consolidado ───────────────────────────────────── */}
      <div className="card p-5">
        <div className="flex items-start gap-2 mb-4">
          <Activity size={15} className="text-blue-700 mt-0.5" />
          <div>
            <h2 className="text-sm font-semibold text-gray-900">
              Ocupação dos equipamentos nos últimos {horizonte} dias
            </h2>
            <p className="text-xs text-gray-400 mt-0.5">
              Quais aparelhos estão sendo melhor aproveitados?
            </p>
          </div>
        </div>
        {loading ? (
          <ChartSkeleton />
        ) : equipment.length === 0 ? (
          <div className="h-52 flex items-center justify-center text-sm text-gray-400">
            Nenhum dado no período selecionado
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={Math.max(250, equipment.length * 44)}>
            <BarChart
              layout="vertical"
              data={chartData}
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
                dataKey="nome"
                width={180}
                tick={{ fontSize: 11 }}
                tickLine={false}
              />
              <Tooltip
                content={({ active, payload }) => {
                  if (!active || !payload?.length) return null
                  const d = payload[0]?.payload
                  return (
                    <div className="bg-white border border-gray-200 rounded-lg shadow-md px-3 py-2 text-xs">
                      <p className="font-semibold text-gray-700 mb-1">{d?.nome}</p>
                      <p className="text-gray-700">
                        <strong>{d?.pct}%</strong> de ocupação
                      </p>
                      <p className="text-gray-500 mt-0.5">
                        {Number(d?.realizados).toLocaleString('pt-BR')} realizados
                        {' '}de{' '}
                        {Number(d?.capacidade).toLocaleString('pt-BR')} capacidade
                      </p>
                    </div>
                  )
                }}
              />
              <ReferenceLine
                x={metaCapacidade}
                stroke="#16a34a"
                strokeDasharray="4 3"
                label={{
                  value: `Meta ${metaCapacidade}%`,
                  position: 'top',
                  fontSize: 10,
                  fill: '#16a34a',
                }}
              />
              <Bar dataKey="pct" radius={[0, 3, 3, 0]}>
                {chartData.map((entry, i) => (
                  <Cell key={i} fill={barColor(entry.pct)} />
                ))}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* ── ZONA 2: Cards individuais ─────────────────────────────────────── */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {loading
          ? Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="card p-5 animate-pulse">
                <div className="h-4 w-40 bg-gray-200 rounded mb-2" />
                <div className="h-3 w-24 bg-gray-100 rounded mb-4" />
                <div className="h-2 bg-gray-100 rounded-full mb-2" />
                <div className="h-3 w-32 bg-gray-100 rounded" />
              </div>
            ))
          : equipment.map((eq) => {
              const pct   = Number(eq.pct_ocupacao) || 0
              const badge = badgeInfo(pct)
              return (
                <div key={`${eq.equipamento_nome}-${eq.unidade_nome}`} className="card p-5">
                  <div className="flex items-start justify-between mb-4">
                    <div>
                      <h3 className="font-semibold text-gray-900">{eq.equipamento_nome}</h3>
                      <p className="text-sm text-gray-500 mt-0.5">{eq.unidade_nome}</p>
                    </div>
                    <span className={`text-xs px-2 py-1 rounded-full font-medium ${badge.className}`}>
                      {badge.label}
                    </span>
                  </div>

                  <div className="mb-3">
                    <div className="flex justify-between text-xs text-gray-500 mb-1.5">
                      <span>Ocupação nos últimos {horizonte} dias</span>
                      <span className="font-medium text-gray-700">{pct}%</span>
                    </div>
                    <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                      <div
                        className="h-full rounded-full transition-all"
                        style={{ width: `${pct}%`, backgroundColor: barColor(pct) }}
                      />
                    </div>
                  </div>

                  <p className="text-xs text-gray-400">
                    {Number(eq.exames_realizados).toLocaleString('pt-BR')} realizados
                    {' '}/ {Number(eq.capacidade_total).toLocaleString('pt-BR')} capacidade total
                  </p>
                </div>
              )
            })}

        {!loading && equipment.length === 0 && (
          <div className="col-span-2 py-12 text-center text-gray-400 text-sm">
            Nenhum dado no período selecionado
          </div>
        )}
      </div>
    </div>
  )
}
