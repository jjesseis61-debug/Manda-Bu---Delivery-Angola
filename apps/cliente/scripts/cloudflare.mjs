// Prepara a app web construída (dist) para o Cloudflare Pages. Uso: node scripts/cloudflare.mjs dist
//
// 1. O envio do Cloudflare (wrangler) ignora pastas node_modules, e é lá que o Expo põe a fonte dos
//    ícones (Ionicons) e as imagens da navegação: a pasta passa a assets/nm e os caminhos acompanham.
// 2. Um ficheiro de /_expo/static/ que muda de conteúdo tem de mudar de NOME: o Cloudflare manda-os
//    guardar um ano («immutable») e o service worker usa a cópia guardada. Com o mesmo nome, quem já
//    abriu a app continuaria com o código antigo (ícones em caixas). Cada ficheiro alterado ganha um
//    sufixo com o resumo do novo conteúdo, e as referências (index.html e outros ficheiros) acompanham.
// 3. Pára com erro se ficar algum node_modules ou se se perder algum ficheiro.
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative, sep } from 'node:path';

const dist = process.argv[2] ?? 'dist';
const TEXTO = /\.(js|html|css|json|map|webmanifest)$/;

function ficheiros(pasta) {
  return readdirSync(pasta).flatMap((n) => {
    const c = join(pasta, n);
    return statSync(c).isDirectory() ? ficheiros(c) : [c];
  });
}
const resumo = (t) => createHash('md5').update(t).digest('hex').slice(0, 10);
const web = (c) => '/' + relative(dist, c).split(sep).join('/');
const falhar = (m) => {
  console.error(`::error::${m}`);
  process.exit(1);
};

rmSync(join(dist, '_redirects'), { force: true }); // o Cloudflare já abre qualquer endereço na app
const antes = ficheiros(dist).length;

// 1. assets/node_modules -> assets/nm
const velha = join(dist, 'assets', 'node_modules');
const alterados = new Set();
if (existsSync(velha)) {
  renameSync(velha, join(dist, 'assets', 'nm'));
  for (const f of ficheiros(dist).filter((f) => TEXTO.test(f))) {
    const t = readFileSync(f, 'utf8');
    if (!t.includes('/assets/node_modules/')) continue;
    writeFileSync(f, t.split('/assets/node_modules/').join('/assets/nm/'));
    alterados.add(f);
  }
}

// 2. Ficheiros de /_expo/static/ alterados mudam de nome (e quem os refere também, se mudar)
const estatico = (f) => web(f).startsWith('/_expo/static/');
let porRenomear = [...alterados].filter(estatico);
for (let volta = 0; porRenomear.length > 0; volta++) {
  if (volta > 10) falhar('As referências entre ficheiros não estabilizam.');
  const trocas = porRenomear.map((f) => {
    const nome = basename(f);
    const ponto = nome.indexOf('.');
    const novo = `${nome.slice(0, ponto)}-${resumo(readFileSync(f))}${nome.slice(ponto)}`;
    const destino = join(dirname(f), novo);
    renameSync(f, destino);
    alterados.delete(f);
    alterados.add(destino);
    return [web(f), web(destino)];
  });
  const mudaram = [];
  for (const f of ficheiros(dist).filter((f) => TEXTO.test(f))) {
    let t = readFileSync(f, 'utf8');
    const original = t;
    for (const [de, para] of trocas) {
      t = t.split(de).join(para);
      // referências relativas dentro dos pacotes de JS (só o nome)
      t = t.split(basename(de)).join(basename(para));
    }
    if (t !== original) {
      writeFileSync(f, t);
      mudaram.push(f);
    }
  }
  porRenomear = mudaram.filter(estatico);
  for (const [de, para] of trocas) console.log(`Novo nome: ${de} -> ${para}`);
}

// 3. Verificações
const todos = ficheiros(dist);
if (todos.some((f) => f.includes('node_modules'))) falhar('Ainda há pastas node_modules: o Cloudflare não as enviaria.');
if (todos.filter((f) => /\.(js|html|css)$/.test(f)).some((f) => readFileSync(f, 'utf8').includes('/assets/node_modules/')))
  falhar('Ainda há caminhos /assets/node_modules/ na app construída.');
if (todos.length !== antes) falhar(`Perderam-se ficheiros na preparação (${antes} -> ${todos.length}).`);
const html = readFileSync(join(dist, 'index.html'), 'utf8');
for (const m of html.matchAll(/(?:src|href)="(\/_expo\/static\/[^"]+)"/g))
  if (!existsSync(join(dist, m[1]))) falhar(`O index.html aponta para um ficheiro que não existe: ${m[1]}`);
console.log(`Cloudflare: ${todos.length} ficheiros prontos a enviar.`);
