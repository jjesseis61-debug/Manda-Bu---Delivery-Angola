// Completa o app.json com valores que não vão para o repositório.
// GOOGLE_MAPS_ANDROID_API_KEY: chave do Maps SDK for Android (Google Cloud), usada pelo mapa
// do ecrã "Novo endereço". Sem ela o mapa fica em branco nos builds Android; no iOS usa-se o
// Apple Maps e não é precisa. Em builds EAS, definir em EAS Environment Variables.
module.exports = ({ config }) => ({
  ...config,
  android: {
    ...config.android,
    config: {
      ...config.android?.config,
      googleMaps: { apiKey: process.env.GOOGLE_MAPS_ANDROID_API_KEY ?? '' },
    },
  },
});
