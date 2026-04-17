import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5173,
    proxy: {
      // Roteia /api/anthropic → https://api.anthropic.com (server-to-server, sem CORS)
      // configure() remove o header Origin antes de encaminhar: sem ele, Anthropic trata
      // como chamada server-to-server e não exige anthropic-dangerous-direct-browser-access.
      '/api/anthropic': {
        target:       'https://api.anthropic.com',
        changeOrigin: true,
        rewrite:      (path) => path.replace(/^\/api\/anthropic/, ''),
        configure:    (proxy) => {
          proxy.on('proxyReq', (proxyReq) => {
            proxyReq.removeHeader('origin')
            proxyReq.removeHeader('referer')
          })
        },
      },
    },
  },
})
