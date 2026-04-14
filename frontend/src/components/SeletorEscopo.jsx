import { MapPin, Globe } from 'lucide-react'
import { useEscopo } from '../contexts/EscopoContext'
import { ESCOPOS } from '../constants/macrorregiao'

const OPCOES = [
  {
    value: ESCOPOS.MUNICIPAL,
    label: 'Montes Claros',
    icon:  MapPin,
    title: 'Visão municipal — pacientes e UBS de Montes Claros. Uso operacional diário.',
  },
  {
    value: ESCOPOS.MACRORREGIAO,
    label: 'Macrorregião',
    icon:  Globe,
    title: 'Visão macrorregional — todos os municípios pactuados do Norte de Minas. Uso em reuniões CIR e relatórios PPI.',
  },
]

export function SeletorEscopo() {
  const { escopo, mudarEscopo } = useEscopo()

  return (
    <div className="flex items-center gap-1 bg-gray-100 rounded-lg p-1">
      {OPCOES.map(({ value, label, icon: Icon, title }) => (
        <button
          key={value}
          title={title}
          onClick={() => mudarEscopo(value)}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-sm font-medium transition-all ${
            escopo === value
              ? 'bg-white text-blue-700 shadow-sm'
              : 'text-gray-500 hover:text-gray-700'
          }`}
        >
          <Icon size={14} />
          {label}
        </button>
      ))}
    </div>
  )
}
