const fs = require('fs');
const path = require('path');

// Completa o app.json com valores que não vão para o repositório.
// Notificações push: EXPO_PROJECT_ID (projecto da app em expo.dev) e google-services.json (Firebase,
// escrito pelo workflow a partir do segredo GOOGLE_SERVICES_JSON). Sem eles a app funciona sem push.
const projectId = process.env.EXPO_PROJECT_ID || undefined;
const firebase = fs.existsSync(path.join(__dirname, 'google-services.json')) ? './google-services.json' : undefined;

module.exports = ({ config }) => ({
  ...config,
  extra: { ...config.extra, ...(projectId ? { eas: { projectId } } : {}) },
  android: { ...config.android, ...(firebase ? { googleServicesFile: firebase } : {}) },
});
