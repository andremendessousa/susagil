import { MapPin, Globe, Building2 } from 'lucide-react'
import { useEscopo } from '../contexts/EscopoContext'
import { ESCOPOS } from '../constants/macrorregiao'

const OPCOES = [
  {
    value: ESCOPOS.MUNICIPAL,
    label: 'Montes Claros',
    icon:  MapPin,
    title: 'Visão municipal — pacientes e UBS de Montes Claros. Uso operacional diário.',
    piloto: false,
  },
  {
    value: ESCOPOS.MACRORREGIAO,
    label: 'Macrorregião',
    icon:  Globe,
    title: 'Visão macrorregional — todos os municípios pactuados do Norte de Minas. Uso em reuniões CIR e relatórios PPI.',
    piloto: false,
  },
  {
    value: ESCOPOS.REGIONAL_INDEPENDENCIA,
    label: 'Reg. Independência',
    icon:  Building2,
    title: 'Regional Independência — piloto Ortopedia e Traumatologia (Edital CPSI 004/2026).',
    piloto: true,
  },
]

export function SeletorEscopo() {
  const { escopo, mudarEscopo } = useEscopo()

  return (
    <div className="flex items-center gap-1 bg-gray-100 rounded-lg p-1">
      {OPCOES.map(({ value, label, icon: Icon, title, piloto }) => (
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
          {piloto && escopo !== value && (
            <span className="ml-0.5 px-1 py-0.5 rounded text-[10px] bg-amber-100 text-amber-700 font-semibold leading-none">
              Piloto
            </span>
          )}
        </button>
      ))}
    </div>
  )
}
