// Pós-compilação da versão web (PWA): liga o manifesto, os ícones do iPhone e o service worker
// ao index.html gerado pelo Expo, e carimba a versão no sw.js. Uso: node scripts/pwa.mjs dist
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const dist = process.argv[2] ?? 'dist';
const versao = process.env.COMMIT_REF?.slice(0, 7) || String(Date.now());

const cabecalho = `
    <link rel="manifest" href="/manifest.webmanifest" />
    <meta name="theme-color" content="#B5121B" />
    <meta name="description" content="Comida de casa, entregue quente. Pede a tua refeição e acompanha a entrega." />
    <link rel="apple-touch-icon" href="/icons/apple-touch-icon.png" />
    <meta name="apple-mobile-web-app-capable" content="yes" />
    <meta name="mobile-web-app-capable" content="yes" />
    <meta name="apple-mobile-web-app-title" content="Cozinha da Alexandra" />
    <meta name="apple-mobile-web-app-status-bar-style" content="default" />
    <script>
      if ('serviceWorker' in navigator) {
        window.addEventListener('load', function () { navigator.serviceWorker.register('/sw.js').catch(function () {}); });
      }
    </script>`;

const indexPath = join(dist, 'index.html');
let html = readFileSync(indexPath, 'utf8');
if (!html.includes('manifest.webmanifest')) {
  html = html.replace('</head>', `${cabecalho}\n  </head>`);
  html = html.replace(/<html lang="[^"]*"/, '<html lang="pt"');
  writeFileSync(indexPath, html);
}
const swPath = join(dist, 'sw.js');
writeFileSync(swPath, readFileSync(swPath, 'utf8').replace("'__VERSAO__'", `'${versao}'`));
console.log(`PWA: manifesto e service worker ligados (versão ${versao})`);
