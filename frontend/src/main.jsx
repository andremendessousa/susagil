import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App.jsx'
import { EscopoProvider } from './contexts/EscopoContext'
import './index.css'
ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <BrowserRouter>
      <EscopoProvider>
        <App />
      </EscopoProvider>
    </BrowserRouter>
  </React.StrictMode>
)
