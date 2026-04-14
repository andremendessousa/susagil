import { createContext, useContext, useState } from 'react'
import { ESCOPOS } from '../constants/macrorregiao'

const EscopoContext = createContext(null)

export function EscopoProvider({ children }) {
  const [escopo, setEscopo] = useState(() => {
    return localStorage.getItem('susagil_escopo') ?? ESCOPOS.MUNICIPAL
  })

  const mudarEscopo = (novoEscopo) => {
    setEscopo(novoEscopo)
    localStorage.setItem('susagil_escopo', novoEscopo)
  }

  const isMunicipal    = escopo === ESCOPOS.MUNICIPAL
  const isMacrorregiao = escopo === ESCOPOS.MACRORREGIAO

  return (
    <EscopoContext.Provider value={{ escopo, mudarEscopo, isMunicipal, isMacrorregiao }}>
      {children}
    </EscopoContext.Provider>
  )
}

export function useEscopo() {
  const ctx = useContext(EscopoContext)
  if (!ctx) throw new Error('useEscopo deve ser usado dentro de EscopoProvider')
  return ctx
}
