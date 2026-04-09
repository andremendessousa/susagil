import { Outlet, NavLink } from 'react-router-dom'
import { LayoutDashboard, ListOrdered, Monitor, Bell } from 'lucide-react'

const nav = [
  { to: '/dashboard', icon: LayoutDashboard, label: 'Dashboard' },
  { to: '/fila',      icon: ListOrdered,     label: 'Fila de Exames' },
  { to: '/maquinas',  icon: Monitor,         label: 'Equipamentos' },
]

export default function Layout() {
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
              <Icon size={18} />
              {label}
            </NavLink>
          ))}
        </nav>
        <div className="px-6 py-4 border-t border-blue-800">
          <p className="text-xs text-blue-400">UBS Central — Atendente</p>
        </div>
      </aside>

      <div className="flex-1 flex flex-col overflow-hidden">
        <header className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
          <h2 className="text-sm font-medium text-gray-500">Sistema Municipal de Regulação de Imagem</h2>
          <button className="relative p-2 rounded-lg hover:bg-gray-100">
            <Bell size={18} className="text-gray-500" />
            <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-red-500 rounded-full" />
          </button>
        </header>
        <main className="flex-1 overflow-y-auto p-6">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
