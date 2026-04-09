import { Search, Filter, Loader } from 'lucide-react'
import { useState } from 'react'
import { useQueue } from '../hooks/useQueue'

const prioStyle = {
  1: 'bg-red-100 text-red-800',
  2: 'bg-amber-100 text-amber-800',
  3: 'bg-green-100 text-green-800',
  4: 'bg-gray-100 text-gray-700',
}

const corLabel = { vermelho: 'Emergência', amarelo: 'Urgência', verde: 'Prioridade', azul: 'Rotina' }

export default function FilaPage() {
  const { entries, loading } = useQueue()
  const [busca, setBusca] = useState('')

  const filtrados = entries.filter(e =>
    !busca || e.paciente_nome?.toLowerCase().includes(busca.toLowerCase()) ||
    e.ubs_origem?.toLowerCase().includes(busca.toLowerCase()) ||
    e.paciente_cns?.includes(busca)
  )

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Fila de Exames</h1>
          <p className="text-sm text-gray-500 mt-0.5">
            {loading ? 'Carregando...' : `${entries.length} pacientes · Raio-X convencional`}
          </p>
        </div>
        <button className="btn-primary">+ Novo encaminhamento</button>
      </div>

      <div className="flex gap-3">
        <div className="relative flex-1">
          <Search size={16} className="absolute left-3 top-2.5 text-gray-400" />
          <input
            value={busca}
            onChange={e => setBusca(e.target.value)}
            placeholder="Buscar paciente, CNS ou UBS..."
            className="w-full pl-9 pr-4 py-2 text-sm border border-gray-200 rounded-lg
                       focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
          />
        </div>
        <button className="btn-ghost flex items-center gap-2">
          <Filter size={16} /> Filtros
        </button>
      </div>

      <div className="card">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-xs text-gray-500 uppercase tracking-wide">
            <tr>
              <th className="px-5 py-3 text-left">Paciente</th>
              <th className="px-5 py-3 text-left">UBS origem</th>
              <th className="px-5 py-3 text-left">Município</th>
              <th className="px-5 py-3 text-left">Dias na fila</th>
              <th className="px-5 py-3 text-left">Prioridade</th>
              <th className="px-5 py-3 text-left">Status</th>
              <th className="px-5 py-3 text-left">Ação</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-50">
            {loading && (
              <tr><td colSpan={7} className="px-5 py-8 text-center">
                <Loader size={20} className="animate-spin text-gray-400 mx-auto" />
              </td></tr>
            )}
            {!loading && filtrados.map((r) => (
              <tr key={r.id} className="hover:bg-gray-50 transition-colors">
                <td className="px-5 py-3 font-medium text-gray-900">{r.paciente_nome}</td>
                <td className="px-5 py-3 text-gray-500">{r.ubs_origem}</td>
                <td className="px-5 py-3 text-gray-500">{r.municipio_paciente}</td>
                <td className="px-5 py-3">
                  <span className={`font-semibold ${r.dias_na_fila > 30 ? 'text-red-600' : 'text-gray-700'}`}>
                    {r.dias_na_fila}d
                  </span>
                </td>
                <td className="px-5 py-3">
                  <span className={`badge ${prioStyle[r.prioridade_codigo] || 'bg-gray-100 text-gray-700'}`}>
                    {corLabel[r.cor_risco] || r.cor_risco}
                  </span>
                </td>
                <td className="px-5 py-3 text-gray-500 capitalize">{r.status_local}</td>
                <td className="px-5 py-3">
                  <button className="text-blue-700 text-xs font-medium hover:underline">Agendar</button>
                </td>
              </tr>
            ))}
            {!loading && filtrados.length === 0 && (
              <tr><td colSpan={7} className="px-5 py-8 text-center text-gray-400 text-sm">
                Nenhum resultado encontrado
              </td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
