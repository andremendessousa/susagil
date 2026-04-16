import { useState, useEffect, useCallback } from 'react'
import { X, Loader, CheckCircle, AlertCircle } from 'lucide-react'
import { supabase } from '../lib/supabase'

const RISCO_OPTIONS = [
  { codigo: 4, cor: 'azul',     label: 'Rotina',     badgeClass: 'bg-gray-100 text-gray-700' },
  { codigo: 3, cor: 'verde',    label: 'Prioridade', badgeClass: 'bg-green-100 text-green-800' },
  { codigo: 2, cor: 'amarelo',  label: 'Urgência',   badgeClass: 'bg-amber-100 text-amber-800' },
  { codigo: 1, cor: 'vermelho', label: 'Emergência', badgeClass: 'bg-red-100 text-red-800' },
]

const INITIAL_FORM = {
  cns: '',
  nome: '',
  ubs_id: '',
  prioridade_codigo: 4,
  cor_risco: 'azul',
  tipo_regulacao: 'fila_espera',
  observacoes: '',
}

export default function NovoEncaminhamentoModal({ isOpen, onClose, onSuccess }) {
  const [form, setForm] = useState(INITIAL_FORM)
  const [ubsList, setUbsList] = useState([])
  const [patientId, setPatientId] = useState(null)
  const [cnsStatus, setCnsStatus] = useState('idle') // idle | loading | found | not_found
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState(null)

  // Busca UBS ao abrir o modal
  useEffect(() => {
    if (!isOpen) return
    supabase
      .from('ubs')
      .select('id, nome')
      .eq('tipo', 'R')
      .order('nome')
      .then(({ data }) => setUbsList(data || []))
  }, [isOpen])

  // Limpa estado ao fechar
  useEffect(() => {
    if (!isOpen) {
      setForm(INITIAL_FORM)
      setPatientId(null)
      setCnsStatus('idle')
      setSubmitError(null)
    }
  }, [isOpen])

  const buscarPacientePorCns = useCallback(async (cns) => {
    if (cns.length !== 15) return
    setCnsStatus('loading')
    const { data } = await supabase
      .from('patients')
      .select('id, nome')
      .eq('cns', cns)
      .maybeSingle()

    if (data) {
      setPatientId(data.id)
      setForm(f => ({ ...f, nome: data.nome }))
      setCnsStatus('found')
    } else {
      setPatientId(null)
      setCnsStatus('not_found')
    }
  }, [])

  function handleCnsChange(e) {
    const digits = e.target.value.replace(/\D/g, '').slice(0, 15)
    setForm(f => ({ ...f, cns: digits }))
    if (digits.length < 15) {
      setCnsStatus('idle')
      setPatientId(null)
    } else {
      buscarPacientePorCns(digits)
    }
  }

  function handleCnsBlur() {
    if (form.cns.length === 15 && cnsStatus === 'idle') {
      buscarPacientePorCns(form.cns)
    }
  }

  function handleRiscoSelect(option) {
    setForm(f => ({ ...f, prioridade_codigo: option.codigo, cor_risco: option.cor }))
  }

  async function handleSubmit(e) {
    e.preventDefault()
    setSubmitError(null)
    setSubmitting(true)

    try {
      let pid = patientId

      // Se paciente não existe no banco, cria registro
      if (!pid) {
        const { data: newPatient, error: patErr } = await supabase
          .from('patients')
          .insert({ cns: form.cns, nome: form.nome })
          .select('id')
          .single()

        if (patErr) {
          setSubmitError('Erro ao registrar paciente: ' + patErr.message)
          return
        }
        pid = newPatient.id
      }

      const { error: queueErr } = await supabase.from('queue_entries').insert({
        patient_id: pid,
        ubs_id: form.ubs_id || null,
        prioridade_codigo: form.prioridade_codigo,
        cor_risco: form.cor_risco,
        tipo_regulacao: form.tipo_regulacao,
        observacoes: form.observacoes || null,
        status_local: 'aguardando',
      })

      if (queueErr) {
        setSubmitError('Erro ao adicionar à fila: ' + queueErr.message)
        return
      }

      onSuccess?.()
      onClose()
    } finally {
      setSubmitting(false)
    }
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Overlay */}
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />

      {/* Painel */}
      <div className="relative bg-white rounded-xl shadow-xl w-full max-w-lg mx-4 max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 shrink-0">
          <div>
            <h2 className="text-base font-semibold text-gray-900">Novo Encaminhamento</h2>
            <p className="text-xs text-gray-400 mt-0.5">Fila de Raio-X — Montes Claros (MG)</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
            aria-label="Fechar"
          >
            <X size={20} />
          </button>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="overflow-y-auto px-6 py-5 space-y-4">
          {/* CNS */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              CNS do Paciente <span className="text-red-500">*</span>
            </label>
            <div className="relative">
              <input
                type="text"
                inputMode="numeric"
                value={form.cns}
                onChange={handleCnsChange}
                onBlur={handleCnsBlur}
                placeholder="000 0000 0000 0000"
                required
                maxLength={15}
                className="w-full px-3 py-2 pr-28 text-sm border border-gray-200 rounded-lg
                           focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              <span className="absolute right-3 top-2.5 flex items-center gap-1">
                {cnsStatus === 'loading' && (
                  <Loader size={14} className="animate-spin text-gray-400" />
                )}
                {cnsStatus === 'found' && (
                  <>
                    <CheckCircle size={14} className="text-green-500" />
                    <span className="text-xs text-green-600 font-medium">encontrado</span>
                  </>
                )}
                {cnsStatus === 'not_found' && (
                  <>
                    <AlertCircle size={14} className="text-amber-500" />
                    <span className="text-xs text-amber-600">novo paciente</span>
                  </>
                )}
              </span>
            </div>
            <p className="text-xs text-gray-400 mt-0.5">15 dígitos — Cartão Nacional de Saúde</p>
          </div>

          {/* Nome */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Nome do Paciente <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={form.nome}
              onChange={e => setForm(f => ({ ...f, nome: e.target.value }))}
              placeholder="Nome completo"
              required
              className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
                         focus:outline-none focus:ring-2 focus:ring-blue-500
                         disabled:bg-gray-50 disabled:text-gray-500"
            />
          </div>

          {/* UBS de Origem */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              UBS de Origem <span className="text-red-500">*</span>
            </label>
            <select
              value={form.ubs_id}
              onChange={e => setForm(f => ({ ...f, ubs_id: e.target.value }))}
              required
              className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
                         focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
            >
              <option value="">Selecione a UBS...</option>
              {ubsList.map(u => (
                <option key={u.id} value={u.id}>{u.nome}</option>
              ))}
            </select>
          </div>

          {/* Classificação de Risco */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-2">
              Classificação de Risco <span className="text-red-500">*</span>
            </label>
            <div className="grid grid-cols-2 gap-2">
              {RISCO_OPTIONS.map(opt => {
                const selected = form.prioridade_codigo === opt.codigo
                return (
                  <button
                    type="button"
                    key={opt.codigo}
                    onClick={() => handleRiscoSelect(opt)}
                    className={`px-3 py-2 rounded-lg text-xs font-medium border-2 transition-all text-left
                      ${selected
                        ? `${opt.badgeClass} border-current ring-2 ring-offset-1 ring-current`
                        : 'bg-white border-gray-200 text-gray-500 hover:border-gray-300'
                      }`}
                  >
                    {opt.label}
                  </button>
                )
              })}
            </div>
          </div>

          {/* Tipo de Regulação */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-2">
              Tipo de Regulação <span className="text-red-500">*</span>
            </label>
            <div className="flex gap-5">
              {[
                { value: 'fila_espera', label: 'Fila de Espera' },
                { value: 'regulado',    label: 'Regulado' },
              ].map(opt => (
                <label
                  key={opt.value}
                  className="flex items-center gap-2 text-sm text-gray-700 cursor-pointer"
                >
                  <input
                    type="radio"
                    name="tipo_regulacao"
                    value={opt.value}
                    checked={form.tipo_regulacao === opt.value}
                    onChange={() => setForm(f => ({ ...f, tipo_regulacao: opt.value }))}
                    className="accent-blue-600"
                  />
                  {opt.label}
                </label>
              ))}
            </div>
          </div>

          {/* Hipótese Diagnóstica */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Hipótese Diagnóstica / Observações
              <span className="ml-1 text-gray-400 font-normal">(opcional)</span>
            </label>
            <textarea
              value={form.observacoes}
              onChange={e => setForm(f => ({ ...f, observacoes: e.target.value }))}
              placeholder="Ex: Suspeita de fratura, histórico relevante, solicitação médica..."
              rows={3}
              className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
                         focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
            />
          </div>

          {/* Erro de submissão */}
          {submitError && (
            <div className="flex items-start gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-xs text-red-700">
              <AlertCircle size={14} className="mt-0.5 shrink-0" />
              {submitError}
            </div>
          )}

          {/* Ações */}
          <div className="flex justify-end gap-3 pt-1">
            <button type="button" onClick={onClose} className="btn-ghost">
              Cancelar
            </button>
            <button
              type="submit"
              disabled={submitting || form.cns.length !== 15}
              className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
            >
              {submitting && <Loader size={14} className="animate-spin" />}
              Adicionar à Fila
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
