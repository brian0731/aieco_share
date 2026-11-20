export default defineNuxtConfig({
  compatibilityDate: '2026-11-20',
  telemetry: false,
  modules: ['@nuxt/ui'],
  css: ['~/assets/css/main.css'],
  icon: { serverBundle: { collections: ['lucide'] } },
  runtimeConfig: { databaseUrl: '' },
})
