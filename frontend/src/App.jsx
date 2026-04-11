import { Routes, Route, Navigate } from 'react-router-dom'
import Layout from './components/Layout.jsx'
import DashboardPage from './pages/DashboardPage.jsx'
import FilaPage from './pages/FilaPage.jsx'
import MaquinasPage from './pages/MaquinasPage.jsx'
import ConfiguracoesPage from './pages/ConfiguracoesPage.jsx'
import NotificacoesPage from './pages/NotificacoesPage.jsx'
import LoginPage from './pages/LoginPage.jsx'
import { useAuth } from './hooks/useAuth.js'

export default function App() {
  const { user, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <p className="text-sm text-gray-400">Carregando…</p>
      </div>
    )
  }

  if (!user) {
    return <LoginPage />
  }

  return (
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<DashboardPage />} />
        <Route path="fila" element={<FilaPage />} />
        <Route path="maquinas" element={<MaquinasPage />} />
        <Route path="notificacoes" element={<NotificacoesPage />} />
        <Route path="configuracoes" element={<ConfiguracoesPage />} />
      </Route>
    </Routes>
  )
}
