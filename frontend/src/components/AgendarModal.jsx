import { useState, useEffect } from 'react'
import { X, Loader, AlertCircle, Calendar } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useEquipment } from '../hooks/useEquipment'

const TURNOS = [
  { value: 'manha', label: 'Manhã',  hora: '08:00' },
  { value: 'tarde', label: 'Tarde',  hora: '13:00' },
  { value: 'noite', label: 'Noite',  hora: '18:00' },
]

function getTurnosDisponiveis(equip) {
  if (!equip) return TURNOS
  const raw = equip.turno || equip.turno_funcionamento
  if (!raw) return TURNOS
  const vals = (Array.isArray(raw) ? raw : raw.split(','))
    .map(v => v.trim().toLowerCase())
  const filtered = TURNOS.filter(t => vals.includes(t.value))
  return filtered.length ? filtered : TURNOS
}

function getTomorrow() {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().split('T')[0]
}

const INITIAL_FORM = { equipment_id: '', date: '', turno: '', observacoes: '' }

export default function AgendarModal({ isOpen, onClose, entry, onSuccess }) {
  const { equipment, loading: loadingEquip } = useEquipment()
  const [form, setForm] = useState(INITIAL_FORM)
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState(null)

  const selectedEquip = equipment.find(
    e => String(e.equipment_id ?? e.id) === form.equipment_id
  )
  const turnosDisponiveis = getTurnosDisponiveis(selectedEquip)

  // Resetar turno quando equipamento mudar e turno atual não for mais válido
  useEffect(() => {
    const valid = turnosDisponiveis.some(t => t.value === form.turno)
    if (!valid) setForm(f => ({ ...f, turno: '' }))
  }, [form.equipment_id]) // eslint-disable-line react-hooks/exhaustive-deps

  // Limpar form ao fechar
  useEffect(() => {
    if (!isOpen) {
      setForm(INITIAL_FORM)
      setSubmitError(null)
    }
  }, [isOpen])

  async function handleSubmit(e) {
    e.preventDefault()
    if (!entry) return
    setSubmitError(null)
    setSubmitting(true)

    const turnoObj = TURNOS.find(t => t.value === form.turno)
    const scheduledAt = `${form.date}T${turnoObj.hora}:00`

    try {
      // 1. INSERT em appointments
      const { data: appt, error: apptErr } = await supabase
        .from('appointments')
        .insert({
          queue_entry_id: entry.id,
          equipment_id: form.equipment_id,
          scheduled_at: scheduledAt,
          tipo_vaga: 'primeira_vez',
          status: 'agendado',
          observacoes: form.observacoes || null,
        })
        .select('id')
        .single()

      if (apptErr) {
        setSubmitError('Erro ao criar agendamento: ' + apptErr.message)
        return
      }

      // 2. UPDATE queue_entries -> status_local = 'agendado'
      const { error: updateErr } = await supabase
        .from('queue_entries')
        .update({ status_local: 'agendado' })
        .eq('id', entry.id)

      if (updateErr) {
        // Tentar reverter o insert do appointment (best-effort)
        await supabase.from('appointments').delete().eq('id', appt.id)
        setSubmitError('Erro ao atualizar status na fila: ' + updateErr.message)
        return
      }

      onSuccess?.()
      onClose()
    } finally {
      setSubmitting(false)
    }
  }

  if (!isOpen) return null

  const tomorrow = getTomorrow()

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      {/* Overlay */}
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />

      {/* Painel */}
      <div className="relative bg-white rounded-xl shadow-xl w-full max-w-md mx-4 flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 shrink-0">
          <div>
            <h2 className="text-base font-semibold text-gray-900">Agendar Exame</h2>
            {entry && (
              <p className="text-xs text-gray-400 mt-0.5 truncate max-w-xs">
                {entry.paciente_nome}
                {entry.cor_risco && (
                  <span className="ml-1.5 font-medium text-gray-500 capitalize">
                    · {entry.cor_risco}
                  </span>
                )}
              </p>
            )}
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
        <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4">
          {/* Equipamento */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Equipamento <span className="text-red-500">*</span>
            </label>
            {loadingEquip ? (
              <div className="flex items-center gap-2 py-2 text-xs text-gray-400">
                <Loader size={13} className="animate-spin" /> Carregando equipamentos...
              </div>
            ) : (
              <select
                value={form.equipment_id}
                onChange={e => setForm(f => ({ ...f, equipment_id: e.target.value, turno: '' }))}
                required
                className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
                           focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
              >
                <option value="">Selecione o equipamento...</option>
                {equipment.map(eq => {
                  const eqId = eq.equipment_id ?? eq.id
                  const vagas = eq.vagas_disponiveis ?? '—'
                  const pct = eq.pct_ocupacao != null
                    ? `${Math.round(eq.pct_ocupacao)}% ocupado`
                    : null
                  return (
                    <option key={eqId} value={String(eqId)}>
                      {eq.nome}
                      {vagas !== '—' ? ` · ${vagas} vagas` : ''}
                      {pct ? ` · ${pct}` : ''}
                    </option>
                  )
                })}
              </select>
            )}
            {selectedEquip && (
              <div className="mt-1.5 flex gap-4 text-xs text-gray-500">
                {selectedEquip.vagas_disponiveis != null && (
                  <span>
                    <span className="font-medium text-gray-700">
                      {selectedEquip.vagas_disponiveis}
                    </span> vagas disponíveis
                  </span>
                )}
                {selectedEquip.pct_ocupacao != null && (
                  <span>
                    <span className={`font-medium ${
                      selectedEquip.pct_ocupacao >= 90 ? 'text-red-600'
                        : selectedEquip.pct_ocupacao >= 70 ? 'text-amber-600'
                        : 'text-green-600'
                    }`}>
                      {Math.round(selectedEquip.pct_ocupacao)}%
                    </span> de ocupação
                  </span>
                )}
              </div>
            )}
          </div>

          {/* Data */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Data do Exame <span className="text-red-500">*</span>
            </label>
            <div className="relative">
              <Calendar size={14} className="absolute left-3 top-2.5 text-gray-400 pointer-events-none" />
              <input
                type="date"
                value={form.date}
                min={tomorrow}
                onChange={e => setForm(f => ({ ...f, date: e.target.value }))}
                required
                className="w-full pl-8 pr-3 py-2 text-sm border border-gray-200 rounded-lg
                           focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
              />
            </div>
          </div>

          {/* Turno */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Turno <span className="text-red-500">*</span>
            </label>
            <select
              value={form.turno}
              onChange={e => setForm(f => ({ ...f, turno: e.target.value }))}
              required
              disabled={!form.equipment_id}
              className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
                         focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white
                         disabled:bg-gray-50 disabled:text-gray-400"
            >
              <option value="">
                {form.equipment_id ? 'Selecione o turno...' : 'Selecione o equipamento primeiro'}
              </option>
              {turnosDisponiveis.map(t => (
                <option key={t.value} value={t.value}>
                  {t.label} · a partir das {t.hora}
                </option>
              ))}
            </select>
          </div>

          {/* Observações */}
          <div>
            <label className="block text-xs font-medium text-gray-700 mb-1">
              Observações
              <span className="ml-1 text-gray-400 font-normal">(opcional)</span>
            </label>
            <textarea
              value={form.observacoes}
              onChange={e => setForm(f => ({ ...f, observacoes: e.target.value }))}
              placeholder="Instruções de preparo, observações clínicas..."
              rows={3}
              className="w-full px-3 py-2 text-sm border border-gray-200 rounded-lg
                         focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
            />
          </div>

          {/* Erro */}
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
              disabled={submitting}
              className="btn-primary disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
            >
              {submitting && <Loader size={14} className="animate-spin" />}
              Confirmar Agendamento
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
