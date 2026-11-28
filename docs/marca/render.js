// Rasteriza os SVG de lista.json para PNG com o Chromium (transparência correta).
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
  const lista = JSON.parse(fs.readFileSync('lista.json', 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const item of lista) {
    const svg = fs.readFileSync(item.svg, 'utf8');
    // Dimensões em px: 'tamanho' (quadrado) ou as do próprio SVG (logótipo 1600x480).
    const m = svg.match(/width="(\d+)" height="(\d+)"/);
    const w = item.tamanho || parseInt(m[1], 10);
    const h = item.tamanho || parseInt(m[2], 10);
    await page.setViewportSize({ width: w, height: h });
    await page.setContent(
      `<!doctype html><html><head><meta charset="utf-8"><style>
        *{margin:0;padding:0}html,body{width:${w}px;height:${h}px;background:transparent}
        svg{display:block;width:${w}px;height:${h}px}
      </style></head><body>${svg}</body></html>`,
      { waitUntil: 'networkidle' }
    );
    fs.mkdirSync(path.dirname(item.png), { recursive: true });
    await page.screenshot({ path: item.png, omitBackground: true, clip: { x: 0, y: 0, width: w, height: h } });
    console.log(item.png, `${w}x${h}`);
  }
  await browser.close();
})();
