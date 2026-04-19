export const MUNICIPIOS_MACRORREGIAO = [
  'Montes Claros',
  'Bocaiúva',
  'Pirapora',
  'Janaúba',
  'Salinas',
  'Claro dos Poções',
  'Bocaiuva',         // variante sem acento (compatibilidade com seed)
  'Januaba',          // variante sem acento (compatibilidade com seed)
  'Claro dos Pocoes', // variante sem acento (compatibilidade com seed)
]

export const MUNICIPIO_SEDE = 'Montes Claros'

export const ESCOPOS = {
  MUNICIPAL:              'montes_claros',
  MACRORREGIAO:           'macrorregiao',
  REGIONAL_INDEPENDENCIA: 'regional_independencia', // Piloto CPSI 004/2026
}

// UBSs que compõem a Regional Independência
// Devem corresponder EXATAMENTE ao campo ubs.nome no banco
export const UBS_REGIONAL_INDEPENDENCIA = [
  'ESF Ônix',
  'ESF Coral — Ibituruna',
  'ESF Santos Reis',
  'ESF Alto Boa Vista',
]

// UBS executante (prestadora) que atende a Regional Independência
// Usada para filtrar MaquinasPage quando isRegionalIndependencia=true
export const EXECUTANTES_REGIONAL_INDEPENDENCIA = [
  'HU Clemente de Faria',
]

export const REGIONAL_INDEPENDENCIA_META = {
  nome:      'Regional Independência',
  municipio: 'Montes Claros',
  uf:        'MG',
  descricao: 'Projeto piloto — Ortopedia e Traumatologia (Edital CPSI 004/2026)',
}
