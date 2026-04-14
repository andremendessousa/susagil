import { useState, useEffect, useCallback, useRef } from 'react'
import { Settings, ChevronRight, Save, Loader, ShieldOff, Upload, FileText, CheckCircle, AlertTriangle, X, MessageSquare, Users } from 'lucide-react'
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

// ─── Utilitários CSV ─────────────────────────────────────────────────────────

const CAMPO_MAP = {
  paciente_nome:    ['paciente_nome', 'nome', 'nome_paciente', 'paciente'],
  cns:              ['cns', 'cartao_sus', 'cns_paciente', 'numero_cns'],
  telefone:         ['telefone', 'fone', 'celular', 'tel'],
  ubs_origem:       ['ubs_origem', 'ubs', 'unidade_origem', 'unidade', 'estabelecimento'],
  data_solicitacao: ['data_solicitacao', 'data', 'data_pedido', 'dt_solicitacao', 'data_entrada'],
  procedimento:     ['procedimento', 'especialidade', 'exame', 'servico', 'serviço'],
}

function parseCsvLine(line, sep) {
  const result = []
  let cur = ''
  let inQ = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (ch === '"') {
      if (inQ && line[i + 1] === '"') { cur += '"'; i++ } // escaped quote
      else inQ = !inQ                                       // toggle, não adiciona ao valor
    } else if (ch === sep && !inQ) {
      // Limpa aspas residuais e espaços de cada campo ao empurrar
      result.push(cur.trim().replace(/^"|"$/g, '').trim())
      cur = ''
    } else {
      cur += ch
    }
  }
  result.push(cur.trim().replace(/^"|"$/g, '').trim())
  return result
}

// Detecta separador pontuando ',' ';' '\t' contra as primeiras N linhas
function detectSeparator(lines) {
  const candidates = [',', ';', '\t']
  const sample = lines.slice(0, Math.min(5, lines.length))
  let bestSep = ','
  let bestScore = -1

  for (const sep of candidates) {
    const counts = sample.map(l => parseCsvLine(l, sep).length)
    const minFields = Math.min(...counts)
    const maxFields = Math.max(...counts)
    if (minFields <= 1) continue                      // sep não divide a linha — descarta
    const consistency = (maxFields - minFields <= 1) ? 20 : 0  // bônus: contagem uniforme
    const score = counts.reduce((a, b) => a + b, 0) + consistency
    if (score > bestScore) { bestScore = score; bestSep = sep }
  }

  return bestSep
}

function parseCSV(text) {
  const clean = text.replace(/^\uFEFF/, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n')
  const linhas = clean.trim().split('\n')
  if (linhas.length < 2) return { rows: [], headers: [], sep: ',' }

  // Detectar separador com scoring multi-linha (mais robusto que contagem no header)
  const sep = detectSeparator(linhas)

  // Strip outer quotes da linha inteira (alguns exportadores envolvem a linha toda em aspas)
  const rawHeaders = parseCsvLine(linhas[0].trim().replace(/^"|"$/g, ''), sep)
    .map(h => h.toLowerCase().replace(/"/g, '').trim())
  console.debug('[importacao] sep detectado:', JSON.stringify(sep), '| headers raw:', rawHeaders)

  const headerMap = {}
  for (let i = 0; i < rawHeaders.length; i++) {
    for (const [campo, alts] of Object.entries(CAMPO_MAP)) {
      if (alts.includes(rawHeaders[i])) { headerMap[i] = campo; break }
    }
  }
  console.debug('[importacao] headerMap:', headerMap)

  const rows = linhas.slice(1)
    .filter(l => l.trim())
    .map(l => {
      // Remove aspas externas da linha inteira antes de fazer split por campo
      const stripped = l.trim().replace(/^"|"$/g, '')
      const cells = parseCsvLine(stripped, sep)
      const row = {}
      cells.forEach((cell, i) => { if (headerMap[i]) row[headerMap[i]] = cell })
      return row
    })
    .filter(r => Object.keys(r).length > 0)

  return { rows, headers: [...new Set(Object.values(headerMap))], sep }
}

function parseBrDate(str) {
  if (!str?.trim()) return null
  const s = str.trim().replace(/["']/g, '')

  // ISO já no formato correto: YYYY-MM-DD ou YYYY-MM-DDTHH:MM...
  if (/^\d{4}-\d{2}-\d{2}/.test(s)) return s.slice(0, 10)

  // Suporta DD/MM/YYYY, DD-MM-YYYY, DD.MM.YYYY (separadores mistos)
  const parts = s.split(/[\/\-\.]/)  
  if (parts.length !== 3) return null

  let [a, b, c] = parts.map(p => p.trim())

  // Se o terceiro campo tiver 4 dígitos é ano: DD MM YYYY
  if (c.length === 4) {
    const d  = a.padStart(2, '0')
    const mo = b.padStart(2, '0')
    if (Number(mo) < 1 || Number(mo) > 12) return null
    if (Number(d)  < 1 || Number(d)  > 31) return null
    return `${c}-${mo}-${d}`
  }

  // Se o primeiro campo tiver 4 dígitos é ISO sem hífen: YYYY MM DD
  if (a.length === 4) {
    const mo = b.padStart(2, '0')
    const d  = c.padStart(2, '0')
    return `${a}-${mo}-${d}`
  }

  return null
}

// ─── Importação de Dados ─────────────────────────────────────────────────────

const PREVIEW_COLS = [
  { key: 'paciente_nome',    label: 'Paciente' },
  { key: 'cns',              label: 'CNS' },
  { key: 'telefone',         label: 'Telefone' },
  { key: 'ubs_origem',       label: 'UBS Origem' },
  { key: 'data_solicitacao', label: 'Data solicitação' },
  { key: 'procedimento',     label: 'Procedimento' },
]

function ImportacaoPanel({ onToast }) {
  const inputRef = useRef(null)

  const [arquivo,     setArquivo]     = useState(null)
  const [linhas,      setLinhas]      = useState(null)
  const [erroArq,     setErroArq]     = useState(null)
  const [isDragging,  setIsDragging]  = useState(false)
  const [importando,  setImportando]  = useState(false)
  const [resultado,   setResultado]   = useState(null)
  const [erroImport,  setErroImport]  = useState(null)

  function resetar() {
    setArquivo(null); setLinhas(null); setErroArq(null)
    setResultado(null); setErroImport(null)
    if (inputRef.current) inputRef.current.value = ''
  }

  function processarArquivo(file) {
    if (!file) return
    if (!file.name.toLowerCase().endsWith('.csv')) {
      setErroArq('Selecione um arquivo .csv válido.')
      return
    }
    setArquivo(file)
    setErroArq(null); setLinhas(null); setResultado(null); setErroImport(null)

    const reader = new FileReader()
    reader.onload = (e) => {
      const { rows, headers, sep } = parseCSV(e.target.result)
      if (rows.length === 0) {
        setErroArq('Nenhum registro válido encontrado. Verifique os cabeçalhos do CSV.')
        return
      }
      if (!headers.includes('paciente_nome') && !headers.includes('cns')) {
        setErroArq('Coluna obrigatória não encontrada. O CSV precisa de "paciente_nome" ou "cns".')
        return
      }
      console.debug('[importacao] CSV lido — separador:', sep, '| campos mapeados:', headers, '| linhas:', rows.length)
      setLinhas(rows)
    }
    reader.onerror = () => setErroArq('Falha ao ler o arquivo.')
    reader.readAsText(file, 'UTF-8')
  }

  async function handleImportar() {
    if (!linhas?.length || importando) return
    setImportando(true)
    setErroImport(null)

    const CHUNK = 500
    let batchId = null

    try {
      // 1 — Criar lote — NÃO enviar 'status' no INSERT (enum sync_status não tem 'processando')
      // O banco usa o DEFAULT do campo; atualizamos para 'ok' ou 'erro' ao final
      const batchPayload = { source: 'csv_import', registros_total: linhas.length }
      console.debug('[importacao] insert import_batches:', batchPayload)

      const { data: batch, error: batchErr } = await supabase
        .from('import_batches')
        .insert(batchPayload)
        .select('id')
        .single()
      if (batchErr) {
        console.error('[importacao] import_batches error:', batchErr)
        throw new Error(`Erro ao criar lote: ${batchErr.message} (code: ${batchErr.code})`)
      }
      batchId = batch.id
      console.debug('[importacao] batch criado:', batchId)

      // 2 — Upsert patients (deduplica por CNS).
      // O upsert retorna os IDs diretamente via .select(), evitando um SELECT separado
      // que poderia falhar por RLS (erro 42501) em políticas que bloqueiam leitura.
      const patientsByCSN = new Map()
      for (const r of linhas) {
        if (r.cns && !patientsByCSN.has(r.cns)) {
          patientsByCSN.set(r.cns, {
            cns:      r.cns,
            nome:     r.paciente_nome || null,
            telefone: r.telefone      || null,
          })
        }
      }
      const patientsPayload = [...patientsByCSN.values()]
      let ptsData = []
      console.debug('[importacao] patients upsert:', patientsPayload.length)

      if (patientsPayload.length > 0) {
        const { data: upserted, error: pErr } = await supabase
          .from('patients')
          .upsert(patientsPayload, { onConflict: 'cns', ignoreDuplicates: false })
          .select('id, cns')
        if (pErr) {
          console.error('[importacao] patients upsert error:', pErr)
          throw new Error(`Erro ao criar pacientes: ${pErr.message} (code: ${pErr.code})`)
        }
        ptsData = upserted || []
      }

      // Fallback: se o upsert não retornou todos os IDs (ex: ignoreDuplicates=true em outra config),
      // faz um SELECT complementar — isso evita falha silenciosa por RLS parcial.
      if (ptsData.length < patientsByCSN.size) {
        const { data: fetched, error: ptsErr } = await supabase
          .from('patients')
          .select('id, cns')
          .in('cns', [...patientsByCSN.keys()])
        if (ptsErr) throw new Error(`Erro ao buscar pacientes (fallback): ${ptsErr.message} (code: ${ptsErr.code})`)
        ptsData = fetched || []
      }

      const cnsToId = Object.fromEntries(ptsData.map(p => [p.cns, p.id]))
      console.debug('[importacao] cnsToId mapeado:', Object.keys(cnsToId).length, 'pacientes')

      // 3 — Lookup de UBS: carrega todas de uma vez e faz match client-side (evita N queries)
      const { data: todasUbs } = await supabase.from('ubs').select('id, nome')
      const ubsList = todasUbs || []
      // Fallback para UBS não encontrada: procura "Desconhecida" ou usa a primeira da lista
      const ubsFallback = ubsList.find(u => /desconhecida/i.test(u.nome)) ?? ubsList[0] ?? null
      const fallbackUbsId = ubsFallback?.id ?? null
      console.debug('[importacao] UBS carregadas:', ubsList.length, '| fallback:', ubsFallback?.nome)

      function resolveUbsId(nomeOrigem) {
        if (!nomeOrigem) return fallbackUbsId
        const norm = nomeOrigem.toLowerCase().trim()
        const match = ubsList.find(u =>
          u.nome.toLowerCase().includes(norm) || norm.includes(u.nome.toLowerCase())
        )
        return match?.id ?? fallbackUbsId
      }

      // 4 — Montar payload correto de queue_entries conforme schema real do banco
      const qePayload = linhas
        .filter(r => r.cns && cnsToId[r.cns])
        .map(r => {
          const obj = {
            patient_id:              cnsToId[r.cns],
            ubs_id:                  resolveUbsId(r.ubs_origem),
            data_solicitacao_sisreg: parseBrDate(r.data_solicitacao),
            nome_grupo_procedimento: r.procedimento        || null,
            prioridade_codigo:       4,
            cor_risco:               'azul',
            tipo_regulacao:          'F',
            tipo_vaga:               'fila',
            tipo_atendimento:        'exame',
            status_local:            'aguardando',
            data_source:             'csv_import',
            import_batch_id:         batchId,
          }
          console.log('Objeto enviado para queue_entries:', obj)
          return obj
        })

      console.log('Total de linhas prontas para insert:', qePayload.length)

      let allEntries = []
      for (let i = 0; i < qePayload.length; i += CHUNK) {
        const { data: chunk, error: qeErr } = await supabase
          .from('queue_entries')
          .insert(qePayload.slice(i, i + CHUNK))
          .select('id, nome_grupo_procedimento, patient_id')
        if (qeErr) {
          console.error('[importacao] queue_entries error (chunk', i, '):', qeErr)
          throw new Error(`Erro ao inserir fila: ${qeErr.message} (code: ${qeErr.code})`)
        }
        allEntries = allEntries.concat(chunk)
      }
      console.debug('[importacao] queue_entries inseridos:', allEntries.length)

      // 5 — notification_log: mensagem e telefone_destino são NOT NULL no banco
      // Resgata o telefone do patient a partir do map em memória (evita SELECT extra)
      const ptById = Object.fromEntries(
        ptsData.map(p => [p.id, patientsByCSN.get(p.cns)])
      )
      const enviado_at = new Date().toISOString()
      const notifPayload = allEntries.map(e => ({
        queue_entry_id:   e.id,
        patient_id:       e.patient_id,
        tipo:             '72h',
        canal:            'whatsapp',
        data_source:      'csv_import',
        enviado_at,                                              // NOT NULL no banco
        telefone_destino: ptById[e.patient_id]?.telefone || 'não informado',
        mensagem:         `Você ainda precisa da consulta de ${e.nome_grupo_procedimento ?? 'especialidade'} solicitada anteriormente? Responda: 1 - SIM, 2 – NÃO`,
      }))
      console.debug('[importacao] notification_log payload[0]:', notifPayload[0])

      for (let i = 0; i < notifPayload.length; i += CHUNK) {
        const { error: notifErr } = await supabase
          .from('notification_log')
          .insert(notifPayload.slice(i, i + CHUNK))
        if (notifErr) {
          console.error('[importacao] notification_log error (chunk', i, '):', notifErr)
          throw new Error(`Erro ao agendar notificações: ${notifErr.message} (code: ${notifErr.code})`)
        }
      }

      // 6 — Finalizar lote como 'ok' (enum: sync_status)
      await supabase.from('import_batches').update({ status: 'ok' }).eq('id', batchId)

      const total = allEntries.length
      setResultado({ total, batchId })
      onToast(`Importação concluída: ${total.toLocaleString('pt-BR')} registros marcados como 'csv_import' e validação iniciada.`)
    } catch (err) {
      console.error('[importacao] ERRO GERAL:', err)
      if (batchId)
        await supabase.from('import_batches').update({ status: 'erro' }).eq('id', batchId)
      setErroImport(err.message ?? 'Erro desconhecido. Verifique o console para detalhes.')
    } finally {
      setImportando(false)
    }
  }

  // ── Tela de sucesso ──────────────────────────────────────────────────────────
  if (resultado) {
    return (
      <div className="card p-12 flex flex-col items-center justify-center gap-4 text-center">
        <CheckCircle size={40} className="text-green-500" />
        <div>
          <p className="text-base font-semibold text-gray-900">Importação concluída</p>
          <p className="text-sm text-gray-500 mt-1">
            {resultado.total.toLocaleString('pt-BR')} pacientes importados ·{' '}
            Mensagens WhatsApp agendadas para validação de demanda
          </p>
          <p className="text-xs text-gray-400 font-mono mt-2">
            Lote #{resultado.batchId.slice(0, 8)}
          </p>
        </div>
        <button onClick={resetar} className="btn-primary mt-2 flex items-center gap-2">
          <Upload size={14} />
          Nova importação
        </button>
      </div>
    )
  }

  // ── Tela principal ───────────────────────────────────────────────────────────
  return (
    <div className="space-y-5">

      {/* Dropzone */}
      <div
        onDragOver={(e) => { e.preventDefault(); setIsDragging(true) }}
        onDragLeave={() => setIsDragging(false)}
        onDrop={(e) => { e.preventDefault(); setIsDragging(false); processarArquivo(e.dataTransfer.files[0]) }}
        onClick={() => !arquivo && inputRef.current?.click()}
        className={`card relative border-2 border-dashed p-10 flex flex-col items-center justify-center gap-3 text-center transition-colors select-none
          ${isDragging
            ? 'border-blue-500 bg-blue-50 cursor-copy'
            : arquivo
              ? 'border-green-400 bg-green-50 cursor-default'
              : 'border-gray-200 hover:border-blue-300 hover:bg-gray-50 cursor-pointer'
          }`}
      >
        <input
          ref={inputRef}
          type="file"
          accept=".csv"
          className="sr-only"
          onChange={(e) => processarArquivo(e.target.files[0])}
        />

        {arquivo ? (
          <>
            <FileText size={32} className="text-green-600" />
            <div>
              <p className="text-sm font-semibold text-gray-900">{arquivo.name}</p>
              {linhas ? (
                <p className="text-xs text-green-700 mt-0.5 font-medium">
                  ✓ {linhas.length.toLocaleString('pt-BR')} registros detectados
                </p>
              ) : (
                <p className="text-xs text-gray-400 mt-0.5 flex items-center gap-1 justify-center">
                  <Loader size={11} className="animate-spin" /> Lendo arquivo…
                </p>
              )}
            </div>
            <button
              onClick={(e) => { e.stopPropagation(); resetar() }}
              className="absolute top-3 right-3 p-1.5 rounded-lg hover:bg-gray-100 text-gray-400 hover:text-gray-600 transition-colors"
              title="Remover arquivo"
            >
              <X size={15} />
            </button>
          </>
        ) : (
          <>
            <Upload size={32} className={isDragging ? 'text-blue-500' : 'text-gray-300'} />
            <div>
              <p className="text-sm font-semibold text-gray-700">
                {isDragging ? 'Solte o arquivo aqui' : 'Arraste um CSV ou clique para selecionar'}
              </p>
              <p className="text-xs text-gray-400 mt-1.5">
                Campos esperados:{' '}
                <code className="font-mono text-[11px] text-gray-500">
                  paciente_nome · cns · telefone · ubs_origem · data_solicitacao · procedimento
                </code>
              </p>
            </div>
          </>
        )}
      </div>

      {/* Erro de leitura */}
      {erroArq && (
        <div className="flex items-start gap-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg px-4 py-3">
          <AlertTriangle size={14} className="flex-shrink-0 mt-0.5" />
          {erroArq}
        </div>
      )}

      {/* Prévia dos dados */}
      {linhas?.length > 0 && (
        <div className="card overflow-hidden">
          <div className="px-5 py-3 border-b border-gray-100 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Users size={14} className="text-blue-700" />
              <span className="text-sm font-medium text-gray-900">
                Prévia — {linhas.length.toLocaleString('pt-BR')} registros
              </span>
            </div>
            <span className="text-xs text-gray-400">
              Exibindo {Math.min(5, linhas.length)} de {linhas.length}
            </span>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="bg-gray-50 text-gray-500 uppercase tracking-wide">
                <tr>
                  {PREVIEW_COLS.map(c => (
                    <th key={c.key} className="px-4 py-2.5 text-left whitespace-nowrap font-medium">
                      {c.label}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {linhas.slice(0, 5).map((row, i) => (
                  <tr key={i} className="hover:bg-gray-50 transition-colors">
                    {PREVIEW_COLS.map(c => {
                      // Fallback explícito: chave canonica > 'nome' > placeholder
                      const val =
                        c.key === 'paciente_nome'
                          ? (row.paciente_nome || row.nome || row.paciente || '')
                          : (row[c.key] || '')
                      return (
                        <td key={c.key} className="px-4 py-2.5 text-gray-700 max-w-[180px] truncate" title={val}>
                          {val || <span className="text-gray-300">—</span>}
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Erro de importação */}
      {erroImport && (
        <div className="flex items-start gap-2 text-xs text-red-700 bg-red-50 border border-red-200 rounded-lg px-4 py-3">
          <AlertTriangle size={14} className="flex-shrink-0 mt-0.5" />
          <span>{erroImport}</span>
        </div>
      )}

      {/* Botão de disparo */}
      {linhas?.length > 0 && (
        <div className="flex flex-col sm:flex-row sm:items-center gap-3">
          <button
            onClick={handleImportar}
            disabled={importando}
            className="btn-primary flex items-center gap-2 disabled:opacity-60"
          >
            {importando
              ? <Loader size={14} className="animate-spin" />
              : <MessageSquare size={14} />}
            {importando
              ? `Importando ${linhas.length.toLocaleString('pt-BR')} registros…`
              : 'Iniciar Validação Multicanal'}
          </button>
          <p className="text-xs text-gray-400">
            Agendará {linhas.length.toLocaleString('pt-BR')} mensagens WhatsApp de confirmação de demanda
          </p>
        </div>
      )}
    </div>
  )
}

// ─── ConfiguracoesPage ────────────────────────────────────────────────────────

export default function ConfiguracoesPage() {
  const { profile } = useAuth()
  const { update, loading: saving, error: saveError } = useKpiConfigsMutation()
  const [aba, setAba] = useState('kpis')

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

  const isAdmin = profile?.role === 'admin'

  // Não-admins abrem direto na aba de importação
  useEffect(() => {
    if (profile && !isAdmin) setAba('importacao')
  }, [profile, isAdmin])

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
          <h1 className="text-xl font-semibold text-gray-900">Configurações</h1>
          <p className="text-sm text-gray-500 mt-0.5">
            Gerencie metas de KPIs e importe lotes para saneamento de fila
          </p>
        </div>

        {/* Abas de navegação */}
        <div className="flex gap-1 border-b border-gray-200 -mt-1">
          {[
            isAdmin && { key: 'kpis',       label: 'Metas de KPIs',      icon: Settings },
                        { key: 'importacao', label: 'Importação de Dados', icon: Upload   },
          ].filter(Boolean).map(({ key, label, icon: Icon }) => (
            <button
              key={key}
              onClick={() => setAba(key)}
              className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
                aba === key
                  ? 'border-blue-600 text-blue-700'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <Icon size={13} />
              {label}
            </button>
          ))}
        </div>

        {aba === 'kpis' && !isAdmin && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <ShieldOff size={36} className="text-gray-200" />
            <p className="text-sm font-medium text-gray-500">Acesso restrito a administradores</p>
          </div>
        )}

        {aba === 'kpis' && isAdmin && (loadingConfigs ? (
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
        ))}

        {aba === 'importacao' && (
          <ImportacaoPanel onToast={setToast} />
        )}
      </div>
    </>
  )
}
