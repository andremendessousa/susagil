import { Activity, Loader } from 'lucide-react'
import { useEquipment } from '../hooks/useEquipment'

const turnoLabel = { manha: 'Manhã', tarde: 'Tarde', integral: 'Integral' }

export default function MaquinasPage() {
  const { equipment, loading } = useEquipment()

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Equipamentos</h1>
          <p className="text-sm text-gray-500 mt-0.5">Ocupação dos aparelhos de raio-x em tempo real</p>
        </div>
        {loading && <Loader size={16} className="animate-spin text-gray-400" />}
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {equipment.map((m) => {
          const pct = Number(m.pct_ocupacao) || 0
          const isIdle = m.status === 'inativo'
          return (
            <div key={m.id} className="card p-5">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h3 className="font-semibold text-gray-900">{m.nome}</h3>
                  <p className="text-sm text-gray-500 mt-0.5">{m.unidade_nome}</p>
                </div>
                <span className={`badge ${isIdle ? 'bg-red-100 text-red-700' : 'bg-green-100 text-green-700'}`}>
                  {m.status}
                </span>
              </div>

              <div className="mb-3">
                <div className="flex justify-between text-xs text-gray-500 mb-1.5">
                  <span>Ocupação hoje</span>
                  <span className="font-medium text-gray-700">
                    {m.realizados_hoje}/{m.capacidade_dia} exames ({pct}%)
                  </span>
                </div>
                <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${
                      pct > 80 ? 'bg-green-500' : pct > 40 ? 'bg-amber-400' : 'bg-red-400'
                    }`}
                    style={{ width: `${pct}%` }}
                  />
                </div>
              </div>

              <div className="flex items-center justify-between text-xs text-gray-400 mt-3">
                <span>Turno: {turnoLabel[m.turno] || m.turno}</span>
                <span>Vagas livres: <strong className="text-gray-600">{m.vagas_disponiveis}</strong></span>
                {pct < 50 && !isIdle && (
                  <span className="flex items-center gap-1 text-amber-600 font-medium">
                    <Activity size={12} /> Capacidade ociosa
                  </span>
                )}
              </div>
            </div>
          )
        })}

        {!loading && equipment.length === 0 && (
          <div className="col-span-2 py-12 text-center text-gray-400 text-sm">
            Nenhum equipamento cadastrado
          </div>
        )}
      </div>
    </div>
  )
}
