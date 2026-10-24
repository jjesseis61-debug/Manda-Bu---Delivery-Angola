# Marcas das apps.
# Cliente — Cozinha da Alexandra: rosto estilizado da fundadora (persona, estilo "Coronel" do KFC)
#   dentro do prato creme, com vapor dourado. Versão abstrata (anel + "A" + vapor) usada no ícone
#   monocromático (temático) do Android, onde um rosto a uma só cor não funciona.
# Operador — Manda Bué: anel + monograma "MB" + linhas de velocidade douradas (entrega).
VERMELHO = '#B5121B'; CARVAO = '#1F1A17'; BRANCO = '#FFFFFF'; DOURADO = '#F4B400'; SUAVE = '#5F6368'
CREME = '#FBF0DA'; PELE = '#774C31'; PELE_ESC = '#5E3A24'; CABELO = '#241812'
TOP = '#33403F'; TOP2 = '#46555A'; BOCA = '#50241B'


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
    """Versão abstrata: anel + "A" + vapor (usada no ícone monocromático)."""
    return f'''
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="512" cy="512" r="300" stroke="{anel}" stroke-width="42"/>
    <path d="M430 654 L512 360 L594 654" stroke="{letra}" stroke-width="62"/>
    <path d="M455 560 H569" stroke="{letra}" stroke-width="62"/>
    <path d="M458 196 C434 174 482 158 458 136 C434 114 482 96 458 76" stroke="{vapor}" stroke-width="24"/>
    <path d="M512 206 C486 182 538 164 512 140 C486 116 538 96 512 70" stroke="{vapor}" stroke-width="24"/>
    <path d="M566 196 C542 174 590 158 566 136 C542 114 590 96 566 76" stroke="{vapor}" stroke-width="24"/>
  </g>'''


def rosto(vapor=True):
    """Rosto estilizado da Alexandra dentro do prato creme. Centro (512,500)."""
    v = f'''
  <g fill="none" stroke="{DOURADO}" stroke-width="24" stroke-linecap="round">
    <path d="M458 150 C434 128 482 112 458 90 C434 68 482 52 458 34"/>
    <path d="M512 160 C486 136 538 118 512 94 C486 70 538 50 512 26"/>
    <path d="M566 150 C542 128 590 112 566 90 C542 68 590 52 566 34"/>
  </g>''' if vapor else ''
    return f'''
  <clipPath id="prato"><circle cx="512" cy="500" r="336"/></clipPath>
  <circle cx="512" cy="500" r="336" fill="{CREME}"/>
  <g clip-path="url(#prato)">
    <path d="M150 905 C210 718 352 664 512 664 C672 664 814 718 874 905 Z" fill="{TOP}"/>
    <path d="M150 905 C210 760 352 712 512 712 C672 712 814 760 874 905 Z" fill="{TOP2}" opacity="0.5"/>
    <path d="M454 566 h116 v96 a58 58 0 0 1 -116 0 Z" fill="{PELE_ESC}"/>
    <ellipse cx="350" cy="470" rx="28" ry="40" fill="{PELE}"/>
    <ellipse cx="674" cy="470" rx="28" ry="40" fill="{PELE}"/>
    <circle cx="350" cy="516" r="14" fill="{DOURADO}"/>
    <circle cx="674" cy="516" r="14" fill="{DOURADO}"/>
    <path d="M362 452 C362 300 662 300 662 452 C662 580 596 648 512 648 C428 648 362 580 362 452 Z" fill="{PELE}"/>
    <g fill="{CABELO}">
      <path d="M360 452 C330 452 322 392 340 356 C318 330 338 286 372 288 C372 250 420 232 452 252 C470 214 548 210 572 250 C612 236 664 256 660 300 C700 302 712 356 686 390 C708 420 690 470 660 462 C664 404 646 366 614 352 C560 332 470 330 418 352 C384 366 362 400 360 452 Z"/>
      <circle cx="356" cy="372" r="34"/><circle cx="392" cy="322" r="34"/><circle cx="440" cy="296" r="32"/>
      <circle cx="500" cy="286" r="34"/><circle cx="560" cy="292" r="32"/><circle cx="612" cy="318" r="32"/>
      <circle cx="652" cy="360" r="32"/><circle cx="668" cy="408" r="26"/><circle cx="346" cy="416" r="26"/>
    </g>
    <path d="M414 436 Q448 422 482 434" stroke="{CABELO}" stroke-width="10" fill="none" stroke-linecap="round"/>
    <path d="M542 434 Q576 422 610 436" stroke="{CABELO}" stroke-width="10" fill="none" stroke-linecap="round"/>
    <ellipse cx="450" cy="472" rx="27" ry="18" fill="{BRANCO}"/>
    <ellipse cx="574" cy="472" rx="27" ry="18" fill="{BRANCO}"/>
    <circle cx="453" cy="474" r="12" fill="{CABELO}"/>
    <circle cx="571" cy="474" r="12" fill="{CABELO}"/>
    <path d="M512 486 Q498 530 486 540 Q500 552 512 548 Q524 552 538 540 Q526 530 512 486 Z" fill="{PELE_ESC}" opacity="0.55"/>
    <path d="M454 578 Q512 636 570 578 Q512 600 454 578 Z" fill="{BOCA}"/>
    <path d="M470 582 Q512 598 554 582 Q512 592 470 582 Z" fill="{CREME}"/>
    <circle cx="420" cy="528" r="22" fill="#8A5636" opacity="0.4"/>
    <circle cx="604" cy="528" r="22" fill="#8A5636" opacity="0.4"/>
  </g>{v}'''


def svg(conteudo, fundo=None, escala=1.0, tamanho=1024):
    f = f'<rect width="1024" height="1024" fill="{fundo}"/>' if fundo else ''
    t = f'translate({512 * (1 - escala)} {512 * (1 - escala)}) scale({escala})'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{tamanho}" height="{tamanho}" viewBox="0 0 1024 1024">{f}<g transform="{t}">{conteudo}</g></svg>'


def logotipo_alexandra(fundo=None):
    """Logótipo horizontal: rosto da Alexandra num quadrado vermelho + nome."""
    m = (svg(rosto(), VERMELHO, 0.9)
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

# Cliente — Cozinha da Alexandra (rosto); monocromático usa a marca abstrata
r = rosto()
ficheiros['cliente/icon.png'] = (svg(r, VERMELHO, 0.92), 1024)
ficheiros['cliente/android-icon-background.png'] = (svg('', VERMELHO), 512)
ficheiros['cliente/android-icon-foreground.png'] = (svg(r, None, 0.72), 512)
ficheiros['cliente/android-icon-monochrome.png'] = (svg(marca_alexandra(BRANCO, BRANCO, BRANCO), None, 0.72), 432)
ficheiros['cliente/splash-icon.png'] = (svg(rosto(), None, 1.0), 1024)
ficheiros['cliente/favicon.png'] = (svg(r, VERMELHO, 0.92), 48)

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
ficheiros['marca/simbolo.png'] = (svg(rosto(), VERMELHO, 0.92), 1024)
ficheiros['marca/simbolo-abstrato.png'] = (svg(marca_alexandra(), VERMELHO, 0.92), 1024)
ficheiros['marca/simbolo-operador.png'] = (svg(marca(anel=VERMELHO), CARVAO, 0.92), 1024)

import json, os
os.makedirs('svg', exist_ok=True)
lista = []
for nome, (conteudo, tam) in ficheiros.items():
    caminho_svg = 'svg/' + nome.replace('/', '__').replace('.png', '.svg')
    open(caminho_svg, 'w').write(conteudo)
    lista.append({'svg': caminho_svg, 'png': 'out/' + nome, 'tamanho': tam})
open('svg/logotipo.svg', 'w').write(logotipo_alexandra())
open('svg/simbolo.svg', 'w').write(svg(rosto(), VERMELHO, 0.92))
open('simbolo.svg', 'w').write(svg(rosto(), VERMELHO, 0.92))
open('simbolo-icone.svg', 'w').write(svg(rosto(), VERMELHO, 0.92))
open('logotipo.svg', 'w').write(logotipo_alexandra())
json.dump(lista, open('lista.json', 'w'), indent=1)
print(len(lista), 'ficheiros')
