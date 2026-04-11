import { useState, useEffect, useCallback } from 'react'
import { Settings, ChevronRight, Save, Loader, ShieldOff } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { useKpiConfigsMutation } from '../hooks/useKpiConfigsMutation'

// ─── Helpers ─────────────────────────────────────────────────────────────────

const DIRECAO_LABEL = {
  menor_melhor: 'Menor é melhor (↓)',
  maior_melhor: 'Maior é melhor (↑)',
}

function validarForm({ valor_meta, valor_atencao, valor_critico }, direcao) {
  const m = Number(valor_meta)
  const a = Number(valor_atencao)
  const c = Number(valor_critico)

  if ([m, a, c].some(isNaN)) return 'Preencha todos os campos com valores numéricos.'

  if (direcao === 'menor_melhor') {
    if (!(m < a && a < c))
      return 'Para "menor é melhor": Meta < Atenção < Crítico. Ex: 15 < 20 < 35'
  } else {
    if (!(m > a && a > c))
      return 'Para "maior é melhor": Meta > Atenção > Crítico. Ex: 85 > 70 > 50'
  }

  return null
}

function formatarData(iso) {
  if (!iso) return '—'
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  }).format(new Date(iso))
}

// ─── Toast inline ─────────────────────────────────────────────────────────────

function Toast({ message, onDone }) {
  useEffect(() => {
    const t = setTimeout(onDone, 3500)
    return () => clearTimeout(t)
  }, [onDone])

  return (
    <div className="fixed bottom-6 right-6 z-50 bg-green-700 text-white text-sm font-medium px-5 py-3 rounded-xl shadow-lg flex items-center gap-2 animate-pulse">
      <span className="h-2 w-2 rounded-full bg-green-300" />
      {message}
    </div>
  )
}

// ─── ConfiguracoesPage ────────────────────────────────────────────────────────

export default function ConfiguracoesPage() {
  const { profile } = useAuth()
  const { update, loading: saving, error: saveError } = useKpiConfigsMutation()

  const [configs, setConfigs] = useState([])
  const [loadingConfigs, setLoadingConfigs] = useState(true)
  const [selectedKey, setSelectedKey] = useState(null)

  const [form, setForm] = useState({ valor_meta: '', valor_atencao: '', valor_critico: '' })
  const [formError, setFormError] = useState(null)
  const [toast, setToast] = useState(null)

  const [updatedByName, setUpdatedByName] = useState(null)

  // ── Carregar configs completos ─────────────────────────────────────────────

  const fetchConfigs = useCallback(async () => {
    setLoadingConfigs(true)
    const { data, error } = await supabase
      .from('v_kpi_status')
      .select('*')
      .order('ordem_exibicao')

    if (!error) setConfigs(data || [])
    setLoadingConfigs(false)
  }, [])

  useEffect(() => { fetchConfigs() }, [fetchConfigs])

  // ── Pré-preencher formulário ao selecionar KPI ─────────────────────────────

  useEffect(() => {
    if (!selectedKey) return
    const cfg = configs.find((c) => c.chave === selectedKey)
    if (!cfg) return

    setForm({
      valor_meta:    cfg.valor_meta    ?? '',
      valor_atencao: cfg.valor_atencao ?? '',
      valor_critico: cfg.valor_critico ?? '',
    })
    setFormError(null)
    setUpdatedByName(null)

    if (cfg.atualizado_por) {
      supabase
        .from('profiles')
        .select('nome_completo')
        .eq('user_id', cfg.atualizado_por)
        .single()
        .then(({ data }) => setUpdatedByName(data?.nome_completo ?? null))
    }
  }, [selectedKey, configs])

  // ── Acesso restrito ────────────────────────────────────────────────────────

  if (profile && profile.role !== 'admin') {
    return (
      <div className="flex flex-col items-center justify-center py-24 gap-4">
        <ShieldOff size={40} className="text-gray-300" />
        <p className="text-base font-medium text-gray-600">Acesso restrito</p>
        <p className="text-sm text-gray-400">
          Esta área é exclusiva para gestores com perfil de administrador.
        </p>
      </div>
    )
  }

  const selected = configs.find((c) => c.chave === selectedKey) ?? null

  // ── Salvar ─────────────────────────────────────────────────────────────────

  async function handleSalvar() {
    if (!selected) return
    const erroValidacao = validarForm(form, selected.direcao)
    if (erroValidacao) { setFormError(erroValidacao); return }
    setFormError(null)

    const ok = await update(selected.chave, form)
    if (ok) {
      setToast('Meta atualizada com sucesso')
      await fetchConfigs()
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <>
      {toast && <Toast message={toast} onDone={() => setToast(null)} />}

      <div className="space-y-6">
        <div>
          <h1 className="text-xl font-semibold text-gray-900">Configurações de KPIs</h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Ajuste as metas operacionais sem necessidade de código
          </p>
        </div>

        {loadingConfigs ? (
          <div className="flex items-center gap-2 text-sm text-gray-400">
            <Loader size={14} className="animate-spin" />
            Carregando configurações…
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">

            {/* ── Coluna esquerda: lista ──────────────────────────────────── */}
            <div className="space-y-2">
              {configs.map((cfg) => {
                const isSelected = selectedKey === cfg.chave
                const simboloMeta = cfg.direcao === 'maior_melhor' ? '≥' : '≤'
                return (
                  <button
                    key={cfg.chave}
                    onClick={() => setSelectedKey(cfg.chave)}
                    className={`w-full text-left card px-4 py-3.5 flex items-center justify-between transition-colors
                      ${isSelected
                        ? 'border-blue-600 bg-blue-50 ring-1 ring-blue-500'
                        : 'hover:bg-gray-50'
                      }`}
                  >
                    <div>
                      <p className="text-sm font-medium text-gray-900">{cfg.label}</p>
                      <p className="text-xs text-gray-400 mt-0.5">
                        Meta: {simboloMeta}{cfg.valor_meta}{cfg.unidade}
                      </p>
                    </div>
                    <ChevronRight
                      size={16}
                      className={isSelected ? 'text-blue-600' : 'text-gray-300'}
                    />
                  </button>
                )
              })}
            </div>

            {/* ── Coluna direita: formulário ──────────────────────────────── */}
            <div className="lg:col-span-2">
              {!selected ? (
                <div className="card p-10 flex flex-col items-center justify-center gap-3 text-center">
                  <Settings size={32} className="text-gray-200" />
                  <p className="text-sm text-gray-400">
                    Selecione um indicador à esquerda para editar suas metas
                  </p>
                </div>
              ) : (
                <div className="card p-6 space-y-6">

                  {/* Cabeçalho */}
                  <div>
                    <h2 className="text-base font-semibold text-gray-900">{selected.label}</h2>
                    {selected.descricao && (
                      <p className="text-sm text-gray-500 mt-1">{selected.descricao}</p>
                    )}
                  </div>

                  {/* Campos editáveis */}
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                    {[
                      { field: 'valor_meta',    label: 'Meta',    hint: 'Valor a atingir'                       },
                      { field: 'valor_atencao', label: 'Atenção', hint: 'Alertar quando passar deste valor'      },
                      { field: 'valor_critico', label: 'Crítico', hint: 'Situação crítica — ação imediata'       },
                    ].map(({ field, label, hint }) => (
                      <div key={field}>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          {label}
                          {selected.unidade && (
                            <span className="ml-1 text-gray-400">({selected.unidade})</span>
                          )}
                        </label>
                        <input
                          type="number"
                          step="any"
                          value={form[field]}
                          onChange={(e) =>
                            setForm((prev) => ({ ...prev, [field]: e.target.value }))
                          }
                          className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                        />
                        <p className="text-xs text-gray-400 mt-1">{hint}</p>
                      </div>
                    ))}
                  </div>

                  {/* Erro de validação */}
                  {(formError || saveError) && (
                    <p className="text-xs text-red-600 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
                      {formError || saveError}
                    </p>
                  )}

                  {/* Campos informativos (somente leitura) */}
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 pt-2 border-t border-gray-100">
                    {[
                      { label: 'Chave técnica',  value: selected.chave              },
                      { label: 'Unidade',         value: selected.unidade ?? '—'    },
                      { label: 'Direção',         value: DIRECAO_LABEL[selected.direcao] ?? selected.direcao },
                    ].map(({ label, value }) => (
                      <div key={label}>
                        <p className="text-xs text-gray-400">{label}</p>
                        <p className="text-xs font-medium text-gray-700 mt-0.5 font-mono">{value}</p>
                      </div>
                    ))}
                  </div>

                  {/* Ação */}
                  <div className="flex items-center justify-between pt-2">
                    <button
                      onClick={handleSalvar}
                      disabled={saving}
                      className="btn-primary flex items-center gap-2"
                    >
                      {saving
                        ? <Loader size={14} className="animate-spin" />
                        : <Save size={14} />}
                      {saving ? 'Salvando…' : 'Salvar meta'}
                    </button>
                  </div>

                  {/* Histórico */}
                  {(selected.updated_at || updatedByName) && (
                    <p className="text-xs text-gray-400 border-t border-gray-100 pt-3">
                      Última atualização:{' '}
                      <span className="text-gray-600">{formatarData(selected.updated_at)}</span>
                      {updatedByName && (
                        <> por <span className="text-gray-600 font-medium">{updatedByName}</span></>
                      )}
                    </p>
                  )}
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </>
  )
}
