/**
 * Calcula o status semafórico de um KPI comparando valor real vs configuração do banco.
 *
 * @param {number|null|undefined} valorReal - Valor atual calculado
 * @param {object|null|undefined} config    - Linha de kpi_configs: { valor_meta, valor_critico, direcao }
 * @returns {'ok'|'atencao'|'critico'|'sem_dados'}
 *
 * direcao='menor_melhor' (ex: absenteísmo, espera):
 *   valorReal <= valor_meta                         → 'ok'
 *   valor_meta < valorReal <= valor_critico          → 'atencao'
 *   valorReal > valor_critico                        → 'critico'
 *
 * direcao='maior_melhor' (ex: capacidade, satisfação):
 *   valorReal >= valor_meta                          → 'ok'
 *   valor_critico <= valorReal < valor_meta          → 'atencao'
 *   valorReal < valor_critico                        → 'critico'
 *
 * Nunca lança exceções — trata silenciosamente.
 */
export function calcularStatus(valorReal, config) {
  if (valorReal == null || config == null) return 'sem_dados'
  const v = Number(valorReal)
  if (Number.isNaN(v)) return 'sem_dados'

  const meta    = Number(config.valor_meta)
  const critico = Number(config.valor_critico)

  if (config.direcao === 'maior_melhor') {
    if (v >= meta)    return 'ok'
    if (v >= critico) return 'atencao'
    return 'critico'
  }

  if (config.direcao === 'menor_melhor') {
    if (v <= meta)    return 'ok'
    if (v <= critico) return 'atencao'
    return 'critico'
  }

  // direcao não reconhecida → neutro
  return 'ok'
}
