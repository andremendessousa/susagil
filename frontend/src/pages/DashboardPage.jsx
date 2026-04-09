import { Clock, Users, CheckCircle, AlertTriangle, Loader } from 'lucide-react'
import { useKpis } from '../hooks/useKpis'
import { useQueue } from '../hooks/useQueue'

const statusStyle = {
  confirmado: 'bg-green-100 text-green-800',
  aguardando: 'bg-gray-100 text-gray-700',
  agendado:   'bg-blue-100 text-blue-800',
  realizado:  'bg-blue-100 text-blue-800',
  faltou:     'bg-red-100 text-red-800',
  cancelado:  'bg-red-100 text-red-800',
}

export default function DashboardPage() {
  const { kpis, loading: loadingKpis } = useKpis()
  const { entries, loading: loadingQueue } = useQueue()
  const ultimos = entries.slice(0, 5)

  const cards = [
    { label: 'Na fila',           value: loadingKpis ? '...' : (kpis?.total_aguardando ?? 0), sub: `+ ${kpis?.total_outros_municipios ?? 0} outros municípios`, icon: Users,         color: 'text-blue-700',  bg: 'bg-blue-50'  },
    { label: 'Tempo médio',       value: loadingKpis ? '...' : `${kpis?.media_dias_espera ?? 0}d`, sub: 'Meta: 15 dias',                                       icon: Clock,         color: 'text-amber-700', bg: 'bg-amber-50' },
    { label: 'Agendados',         value: loadingKpis ? '...' : (kpis?.total_agendado ?? 0),  sub: `${kpis?.total_confirmado ?? 0} confirmados`,               icon: CheckCircle,   color: 'text-green-700', bg: 'bg-green-50' },
    { label: 'Outros municípios', value: loadingKpis ? '...' : (kpis?.total_outros_municipios ?? 0), sub: 'polo macrorregional',                              icon: AlertTriangle, color: 'text-red-700',   bg: 'bg-red-50'   },
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-gray-900">Dashboard</h1>
        <p className="text-sm text-gray-500 mt-0.5">Visão geral da fila de raio-x — Montes Claros</p>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        {cards.map(({ label, value, sub, icon: Icon, color, bg }) => (
          <div key={label} className="card p-5">
            <div className={`inline-flex p-2 rounded-lg ${bg} mb-3`}><Icon size={20} className={color} /></div>
            <p className="text-2xl font-semibold text-gray-900">{value}</p>
            <p className="text-sm font-medium text-gray-700 mt-0.5">{label}</p>
            <p className="text-xs text-gray-400 mt-1">{sub}</p>
          </div>
        ))}
      </div>

      <div className="card">
        <div className="px-5 py-4 border-b border-gray-100 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-gray-900">Últimos na fila</h2>
          {loadingQueue && <Loader size={14} className="animate-spin text-gray-400" />}
        </div>
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-xs text-gray-500 uppercase tracking-wide">
            <tr>
              <th className="px-5 py-3 text-left">Paciente</th>
              <th className="px-5 py-3 text-left">UBS origem</th>
              <th className="px-5 py-3 text-left">Município</th>
              <th className="px-5 py-3 text-left">Status</th>
              <th className="px-5 py-3 text-left">Dias na fila</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {ultimos.map((r) => (
              <tr key={r.id} className="hover:bg-gray-50 transition-colors">
                <td className="px-5 py-3 font-medium text-gray-900">{r.paciente_nome}</td>
                <td className="px-5 py-3 text-gray-500">{r.ubs_origem}</td>
                <td className="px-5 py-3 text-gray-500">{r.municipio_paciente}</td>
                <td className="px-5 py-3">
                  <span className={`badge ${statusStyle[r.status_local] || 'bg-gray-100 text-gray-700'}`}>{r.status_local}</span>
                </td>
                <td className="px-5 py-3">
                  <span className={r.dias_na_fila > 30 ? 'text-red-600 font-semibold' : 'text-gray-500'}>{r.dias_na_fila}d</span>
                </td>
              </tr>
            ))}
            {!loadingQueue && ultimos.length === 0 && (
              <tr><td colSpan={5} className="px-5 py-8 text-center text-gray-400 text-sm">Nenhum registro encontrado</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
