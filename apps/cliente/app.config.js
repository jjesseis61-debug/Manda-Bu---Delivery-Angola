const fs = require('fs');
const path = require('path');

// Completa o app.json com valores que não vão para o repositório.
// GOOGLE_MAPS_ANDROID_API_KEY: chave do Maps SDK for Android (Google Cloud), usada pelos mapas
// ("Novo endereço", acompanhar a entrega). No Android, o Google Maps sem chave fecha a app, por isso
// extra.mapaGoogle diz se o build a tem e, sem ela, a app mostra o ecrã sem mapa. No iOS usa-se o
// Apple Maps e não é precisa. Em builds EAS, definir em EAS Environment Variables.
const chaveMapa = process.env.GOOGLE_MAPS_ANDROID_API_KEY ?? '';
// Notificações push: EXPO_PROJECT_ID (projecto da app em expo.dev) e google-services.json (Firebase,
// escrito pelo workflow a partir do segredo GOOGLE_SERVICES_JSON). Sem eles a app funciona sem push.
const projectId = process.env.EXPO_PROJECT_ID || undefined;
const firebase = fs.existsSync(path.join(__dirname, 'google-services.json')) ? './google-services.json' : undefined;

module.exports = ({ config }) => ({
  ...config,
  extra: { ...config.extra, mapaGoogle: chaveMapa.trim() !== '', ...(projectId ? { eas: { projectId } } : {}) },
  android: {
    ...config.android,
    ...(firebase ? { googleServicesFile: firebase } : {}),
    config: {
      ...config.android?.config,
      googleMaps: { apiKey: chaveMapa },
    },
  },
});
