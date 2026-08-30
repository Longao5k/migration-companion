import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  // 后台挂在产品域名的 /admin/ 路径下，不单独占一个子域名——
  // 少一条 DNS 记录、少一张证书、少一处会过期的东西。
  // 资源引用必须跟着走这个前缀，否则线上会去 / 根目录找 assets 而 404。
  base: '/admin/',
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 53002,
    proxy: {
      '/v1': 'http://127.0.0.1:53001',
    },
  },
})
