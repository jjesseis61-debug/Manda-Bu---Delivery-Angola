// Completa o app.json com valores que não vão para o repositório.
// GOOGLE_MAPS_ANDROID_API_KEY: chave do Maps SDK for Android (Google Cloud), usada pelos mapas
// ("Novo endereço", acompanhar a entrega). No Android, o Google Maps sem chave fecha a app, por isso
// extra.mapaGoogle diz se o build a tem e, sem ela, a app mostra o ecrã sem mapa. No iOS usa-se o
// Apple Maps e não é precisa. Em builds EAS, definir em EAS Environment Variables.
const chaveMapa = process.env.GOOGLE_MAPS_ANDROID_API_KEY ?? '';

module.exports = ({ config }) => ({
  ...config,
  extra: { ...config.extra, mapaGoogle: chaveMapa.trim() !== '' },
  android: {
    ...config.android,
    config: {
      ...config.android?.config,
      googleMaps: { apiKey: chaveMapa },
    },
  },
});
