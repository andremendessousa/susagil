import { useState, useEffect } from 'react'
import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { LayoutDashboard, ListOrdered, Monitor, Bell, Settings, BarChart2, Globe, MessageSquare, Bot } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { supabase } from '../lib/supabase'
import { SeletorEscopo } from './SeletorEscopo'
import { useEscopo } from '../contexts/EscopoContext'

const baseNav = [
  { to: '/dashboard',     icon: LayoutDashboard, label: 'Dashboard'        },
  { to: '/fila',          icon: ListOrdered,     label: 'Fila de Exames'  },
  { to: '/maquinas',      icon: Monitor,         label: 'Equipamentos'    },
  { to: '/analise',       icon: BarChart2,       label: 'Análise Gerencial' },
  { to: '/notificacoes',  icon: Bell,            label: 'Notificações'    },
  { to: '/whatsapp',      icon: MessageSquare,   label: 'Comunicação WhatsApp' },
  { to: '/assistente',    icon: Bot,             label: 'Assistente IA',  badge: 'Novo' },
  { to: '/configuracoes', icon: Settings,        label: 'Configurações'   },
]

function useVagasEmRiscoCount() {
  const [count, setCount] = useState(0)

  useEffect(() => {
    async function fetch() {
      const limite = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString()
      const { count: total } = await supabase
        .from('appointments')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'agendado')
        .eq('st_paciente_avisado', 0)
        .gte('scheduled_at', new Date().toISOString())
        .lte('scheduled_at', limite)
      setCount(total ?? 0)
    }

    fetch()

    const channel = supabase
      .channel('layout-vagas-risco')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments' }, fetch)
      .subscribe()

    return () => supabase.removeChannel(channel)
  }, [])

  return count
}

function usePendingNotifCount() {
  const [count, setCount] = useState(0)

  useEffect(() => {
    async function fetch() {
      const { count: total } = await supabase
        .from('notification_log')
        .select('id', { count: 'exact', head: true })
        .is('resposta_paciente', null)
      setCount(total ?? 0)
    }

    fetch()

    const channel = supabase
      .channel('layout-notif-pending')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'notification_log' }, fetch)
      .subscribe()

    return () => supabase.removeChannel(channel)
  }, [])

  return count
}

export default function Layout() {
  const { profile } = useAuth()
  const navigate = useNavigate()
  const isAdmin = profile?.role === 'admin'
  const vagasEmRisco  = useVagasEmRiscoCount()
  const pendingNotifs = usePendingNotifCount()
  const { isMacrorregiao } = useEscopo()

  const nav = baseNav

  return (
    <div className="flex h-screen bg-gray-50">
      <aside className="w-60 bg-blue-900 text-white flex flex-col">
        <div className="px-6 py-5 border-b border-blue-800">
          <p className="text-xs text-blue-300 font-medium uppercase tracking-wider">SUS Montes Claros</p>
          <h1 className="text-base font-semibold mt-0.5">Gestão de Raio-X</h1>
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1">
          {nav.map(({ to, icon: Icon, label }) => (
            <NavLink
              key={to}
              to={to}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm transition-colors
                 ${isActive
                   ? 'bg-blue-700 text-white font-medium'
                   : 'text-blue-200 hover:bg-blue-800 hover:text-white'}`
              }
            >
              <span className="relative">
                <Icon size={18} />
                {to === '/assistente' && (
                  <span className="absolute -top-1 -right-1 h-2 w-2 rounded-full bg-emerald-400" />
                )}
                {to === '/notificacoes' && vagasEmRisco > 0 && (
                  <span className="absolute -top-1 -right-1 h-2 w-2 rounded-full bg-red-500" />
                )}
                {to === '/whatsapp' && pendingNotifs > 0 && (
                  <span className="absolute -top-1 -right-1 h-2 w-2 rounded-full bg-blue-400" />
                )}
              </span>
              {label}
              {to === '/assistente' && (
                <span className="ml-auto text-[10px] font-bold bg-emerald-500 text-white rounded-full px-1.5 py-0.5 leading-none">
                  Novo
                </span>
              )}
              {to === '/notificacoes' && vagasEmRisco > 0 && (
                <span className="ml-auto text-xs bg-red-500 text-white rounded-full px-1.5 py-0.5 leading-none">
                  {vagasEmRisco}
                </span>
              )}
              {to === '/whatsapp' && pendingNotifs > 0 && (
                <span className="ml-auto text-xs bg-blue-500 text-white rounded-full px-1.5 py-0.5 leading-none">
                  {pendingNotifs}
                </span>
              )}
            </NavLink>
          ))}
        </nav>
        <div className="px-6 py-4 border-t border-blue-800">
          <p className="text-xs text-blue-400">{profile?.nome_completo ?? 'Operador'}</p>
        </div>
      </aside>

      <div className="flex-1 flex flex-col overflow-hidden">
        <header className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <SeletorEscopo />
            {isMacrorregiao && (
              <div className="flex items-center gap-1.5 px-2 py-1 bg-amber-100 text-amber-700 rounded text-xs font-medium">
                <Globe size={12} />
                Visão Macrorregional ativa
              </div>
            )}
          </div>
          <button
            onClick={() => navigate('/notificacoes')}
            className="relative p-2 rounded-lg hover:bg-gray-100"
            title="Notificações"
          >
            <Bell size={18} className="text-gray-500" />
            {vagasEmRisco > 0 && (
              <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-red-500 rounded-full" />
            )}
          </button>
        </header>
        <main className="flex-1 overflow-y-auto p-6">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
