# Marcas das apps.
# Cliente — Cozinha da Alexandra: anel (tacho/prato visto de cima) + monograma "A"
#   em traço contínuo + vapor dourado (comida quente de casa).
# Operador — Manda Bué: anel + monograma "MB" + linhas de velocidade douradas (entrega).
VERMELHO = '#B5121B'; CARVAO = '#1F1A17'; BRANCO = '#FFFFFF'; DOURADO = '#F4B400'; SUAVE = '#5F6368'


def marca(anel=BRANCO, letras=BRANCO, linhas=DOURADO):
    """Manda Bué (operador): anel + MB + linhas de velocidade. Área 1024, centro (512,512)."""
    return f'''
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="540" cy="512" r="292" stroke="{anel}" stroke-width="40"/>
    <path d="M359 636 V392 L433 512 L507 392 V636" stroke="{letras}" stroke-width="58"/>
    <path d="M595 392 V636 M595 392 H647 a58 58 0 0 1 0 116 H595 M595 508 H659 a64 64 0 0 1 0 128 H595" stroke="{letras}" stroke-width="58"/>
    <path d="M108 432 H200 M72 512 H200 M108 592 H200" stroke="{linhas}" stroke-width="34"/>
  </g>'''


def marca_alexandra(anel=BRANCO, letra=BRANCO, vapor=DOURADO):
    """Cozinha da Alexandra (cliente): anel + "A" + vapor. Composição centrada em (512,512)."""
    return f'''
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="512" cy="512" r="300" stroke="{anel}" stroke-width="42"/>
    <path d="M430 654 L512 360 L594 654" stroke="{letra}" stroke-width="62"/>
    <path d="M455 560 H569" stroke="{letra}" stroke-width="62"/>
    <path d="M458 196 C434 174 482 158 458 136 C434 114 482 96 458 76" stroke="{vapor}" stroke-width="24"/>
    <path d="M512 206 C486 182 538 164 512 140 C486 116 538 96 512 70" stroke="{vapor}" stroke-width="24"/>
    <path d="M566 196 C542 174 590 158 566 136 C542 114 590 96 566 76" stroke="{vapor}" stroke-width="24"/>
  </g>'''


def svg(conteudo, fundo=None, escala=1.0, tamanho=1024):
    f = f'<rect width="1024" height="1024" fill="{fundo}"/>' if fundo else ''
    t = f'translate({512 * (1 - escala)} {512 * (1 - escala)}) scale({escala})'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{tamanho}" height="{tamanho}" viewBox="0 0 1024 1024">{f}<g transform="{t}">{conteudo}</g></svg>'


def logotipo_alexandra(fundo=None):
    """Logótipo horizontal da Cozinha da Alexandra: símbolo num quadrado vermelho + nome."""
    m = (svg(marca_alexandra(), VERMELHO, 0.86)
         .replace('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">', '')
         .replace('</svg>', ''))
    f = f'<rect width="1600" height="480" fill="{fundo}"/>' if fundo else ''
    fonte = 'Liberation Sans, Arial, Helvetica, sans-serif'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="480" viewBox="0 0 1600 480">{f}
  <defs><clipPath id="c"><rect x="40" y="40" width="400" height="400" rx="88"/></clipPath></defs>
  <g clip-path="url(#c)"><g transform="translate(40 40) scale(0.390625)">{m}</g></g>
  <text x="500" y="214" font-family="{fonte}" font-weight="600" font-size="84" fill="{CARVAO}" letter-spacing="-1">Cozinha da</text>
  <text x="500" y="348" font-family="{fonte}" font-weight="800" font-size="150" fill="{VERMELHO}" letter-spacing="-3">Alexandra</text>
  <text x="506" y="408" font-family="{fonte}" font-size="40" fill="{SUAVE}" letter-spacing="6">ENTREGUE POR MANDA BUÉ</text>
</svg>'''


ficheiros = {}

# Cliente — Cozinha da Alexandra
ma = marca_alexandra()
ficheiros['cliente/icon.png'] = (svg(ma, VERMELHO, 0.92), 1024)
ficheiros['cliente/android-icon-background.png'] = (svg('', VERMELHO), 512)
ficheiros['cliente/android-icon-foreground.png'] = (svg(ma, None, 0.72), 512)
ficheiros['cliente/android-icon-monochrome.png'] = (svg(marca_alexandra(BRANCO, BRANCO, BRANCO), None, 0.72), 432)
ficheiros['cliente/splash-icon.png'] = (svg(marca_alexandra(), None, 1.0), 1024)
ficheiros['cliente/favicon.png'] = (svg(ma, VERMELHO, 0.92), 48)

# Operador — Manda Bué (carvão)
mo = marca(anel=VERMELHO)
ficheiros['operador/icon.png'] = (svg(mo, CARVAO, 0.92), 1024)
ficheiros['operador/android-icon-background.png'] = (svg('', CARVAO), 512)
ficheiros['operador/android-icon-foreground.png'] = (svg(mo, None, 0.72), 512)
ficheiros['operador/android-icon-monochrome.png'] = (svg(marca(BRANCO, BRANCO, BRANCO), None, 0.72), 432)
ficheiros['operador/splash-icon.png'] = (svg(marca(anel=VERMELHO), None, 1.0), 1024)
ficheiros['operador/favicon.png'] = (svg(mo, CARVAO, 0.92), 48)

# Peças de marca (docs)
ficheiros['marca/logotipo.png'] = (logotipo_alexandra(), None)
ficheiros['marca/logotipo-fundo-claro.png'] = (logotipo_alexandra('#FFFFFF'), None)
ficheiros['marca/simbolo.png'] = (svg(marca_alexandra(), VERMELHO, 0.92), 1024)
ficheiros['marca/simbolo-operador.png'] = (svg(marca(anel=VERMELHO), CARVAO, 0.92), 1024)

import json, os
os.makedirs('svg', exist_ok=True)
lista = []
for nome, (conteudo, tam) in ficheiros.items():
    caminho_svg = 'svg/' + nome.replace('/', '__').replace('.png', '.svg')
    open(caminho_svg, 'w').write(conteudo)
    lista.append({'svg': caminho_svg, 'png': 'out/' + nome, 'tamanho': tam})
# SVGs vetoriais de referência
open('svg/logotipo.svg', 'w').write(logotipo_alexandra())
open('svg/simbolo.svg', 'w').write(svg(marca_alexandra(), VERMELHO, 0.92))
open('simbolo.svg', 'w').write(svg(marca_alexandra(), VERMELHO, 0.92))
open('simbolo-icone.svg', 'w').write(svg(marca_alexandra(), VERMELHO, 0.92))
open('logotipo.svg', 'w').write(logotipo_alexandra())
json.dump(lista, open('lista.json', 'w'), indent=1)
print(len(lista), 'ficheiros')
