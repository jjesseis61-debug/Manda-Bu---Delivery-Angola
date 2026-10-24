# Marcas das apps.
# Cliente — Cozinha da Alexandra (conceito KFC, paleta VERMELHO + BRANCO + PRETO):
#   quadrado vermelho + prato branco + retrato a traço (preto) da fundadora. Mesmo símbolo no
#   ícone, logótipo e letreiro. Dourado NÃO entra na marca — fica só como realce funcional na app
#   (selos, "Prato do dia", estrelas). Versão abstrata (anel + "A") só no ícone monocromático.
# Operador — Manda Bué: anel + "MB" + linhas de velocidade (entrega), inalterado.
VERMELHO = '#B5121B'; CARVAO = '#1F1A17'; PRETO = '#1A1A1A'; BRANCO = '#FFFFFF'; DOURADO = '#F4B400'
SUAVE = '#5F6368'
FONTE = 'Liberation Sans, Arial, Helvetica, sans-serif'


def marca(anel=BRANCO, letras=BRANCO, linhas=DOURADO):
    """Manda Bué (operador): anel + MB + linhas de velocidade. Centro (512,512)."""
    return f'''
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="540" cy="512" r="292" stroke="{anel}" stroke-width="40"/>
    <path d="M359 636 V392 L433 512 L507 392 V636" stroke="{letras}" stroke-width="58"/>
    <path d="M595 392 V636 M595 392 H647 a58 58 0 0 1 0 116 H595 M595 508 H659 a64 64 0 0 1 0 128 H595" stroke="{letras}" stroke-width="58"/>
    <path d="M108 432 H200 M72 512 H200 M108 592 H200" stroke="{linhas}" stroke-width="34"/>
  </g>'''


def marca_A(anel=BRANCO, letra=BRANCO, vapor=BRANCO):
    """Versão abstrata: anel + "A" + vapor (ícone monocromático e marca de apoio). Centro (512,512)."""
    return f'''
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="512" cy="512" r="300" stroke="{anel}" stroke-width="42"/>
    <path d="M430 654 L512 360 L594 654" stroke="{letra}" stroke-width="62"/>
    <path d="M455 560 H569" stroke="{letra}" stroke-width="62"/>
    <path d="M458 196 C434 174 482 158 458 136 C434 114 482 96 458 76" stroke="{vapor}" stroke-width="24"/>
    <path d="M512 206 C486 182 538 164 512 140 C486 116 538 96 512 70" stroke="{vapor}" stroke-width="24"/>
    <path d="M566 196 C542 174 590 158 566 136 C542 114 590 96 566 76" stroke="{vapor}" stroke-width="24"/>
  </g>'''


def _retrato(cor=PRETO, dente=BRANCO):
    """Retrato a traço (coords próprias, rosto ~ centro 600,540). Preto, sorriso aberto (Foto 2)."""
    return f'''
    <path d="M600 150 C468 150 372 240 360 366 C356 410 360 448 370 478 C384 432 410 392 448 372 C508 342 692 342 752 372 C790 392 816 432 830 478 C840 448 844 410 840 366 C828 240 732 150 600 150 Z" fill="{cor}"/>
    <path d="M402 418 C388 520 402 612 470 674 C512 712 560 728 600 728 C640 728 688 712 730 674 C798 612 812 520 798 418" fill="none" stroke="{cor}" stroke-width="11" stroke-linecap="round"/>
    <path d="M402 470 q-26 6 -20 44 q8 26 28 22" fill="none" stroke="{cor}" stroke-width="9"/>
    <path d="M798 470 q26 6 20 44 q-8 26 -28 22" fill="none" stroke="{cor}" stroke-width="9"/>
    <circle cx="410" cy="556" r="12" fill="none" stroke="{cor}" stroke-width="9"/>
    <circle cx="790" cy="556" r="12" fill="none" stroke="{cor}" stroke-width="9"/>
    <path d="M452 452 Q496 434 540 452" stroke="{cor}" stroke-width="10" fill="none" stroke-linecap="round"/>
    <path d="M660 452 Q704 434 748 452" stroke="{cor}" stroke-width="10" fill="none" stroke-linecap="round"/>
    <path d="M454 486 Q496 462 540 486 Q498 502 454 486 Z" fill="none" stroke="{cor}" stroke-width="9"/>
    <path d="M660 486 Q704 462 748 486 Q706 502 660 486 Z" fill="none" stroke="{cor}" stroke-width="9"/>
    <circle cx="497" cy="484" r="11" fill="{cor}"/>
    <circle cx="703" cy="484" r="11" fill="{cor}"/>
    <path d="M600 500 Q590 556 584 566" stroke="{cor}" stroke-width="8" fill="none" stroke-linecap="round"/>
    <path d="M576 576 Q600 592 624 576" stroke="{cor}" stroke-width="8" fill="none" stroke-linecap="round"/>
    <path d="M506 612 Q600 648 694 612 Q600 740 506 612 Z" fill="{dente}" stroke="{cor}" stroke-width="11" stroke-linejoin="round"/>
    <path d="M524 620 Q600 648 676 620" stroke="{cor}" stroke-width="7" fill="none"/>
    <path d="M486 596 Q470 626 486 656" stroke="{cor}" stroke-width="7" fill="none" stroke-linecap="round"/>
    <path d="M714 596 Q730 626 714 656" stroke="{cor}" stroke-width="7" fill="none" stroke-linecap="round"/>'''


def simbolo_rosto(cx=512, cy=512, raio=438, esc=0.96):
    """Prato branco + retrato preto (o símbolo da marca). Centro (cx,cy)."""
    # retrato centrado: leva o seu centro visual (~600,500) para (cx,cy)
    g = f'<g transform="translate({cx} {cy}) scale({esc}) translate(-600 -500)">{_retrato()}</g>'
    return f'<circle cx="{cx}" cy="{cy}" r="{raio}" fill="{BRANCO}"/>{g}'


def svg(conteudo, fundo=None, escala=1.0, tamanho=1024, keyline=False):
    f = f'<rect x="8" y="8" width="1008" height="1008" rx="150" fill="{fundo}" stroke="{PRETO}" stroke-width="10"/>' if (fundo and keyline) else (f'<rect width="1024" height="1024" fill="{fundo}"/>' if fundo else '')
    t = f'translate({512 * (1 - escala)} {512 * (1 - escala)}) scale({escala})'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{tamanho}" height="{tamanho}" viewBox="0 0 1024 1024">{f}<g transform="{t}">{conteudo}</g></svg>'


def logotipo(fundo=None):
    """Logótipo horizontal: símbolo (quadrado vermelho + prato + retrato) + nome. Vermelho+branco+preto."""
    m = (svg(simbolo_rosto(), VERMELHO, 0.9, keyline=True)
         .replace('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">', '')
         .replace('</svg>', ''))
    f = f'<rect width="1600" height="480" fill="{fundo}"/>' if fundo else ''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="480" viewBox="0 0 1600 480">{f}
  <defs><clipPath id="c"><rect x="40" y="40" width="400" height="400" rx="88"/></clipPath></defs>
  <g clip-path="url(#c)"><g transform="translate(40 40) scale(0.390625)">{m}</g></g>
  <text x="500" y="214" font-family="{FONTE}" font-weight="600" font-size="84" fill="{PRETO}" letter-spacing="-1">Cozinha da</text>
  <text x="500" y="348" font-family="{FONTE}" font-weight="800" font-size="150" fill="{VERMELHO}" letter-spacing="-3">Alexandra</text>
  <text x="506" y="408" font-family="{FONTE}" font-weight="600" font-size="40" fill="{PRETO}" letter-spacing="6">ENTREGUE POR MANDA BUÉ</text>
</svg>'''


def letreiro():
    """Letreiro vertical (montra/marketing): fundo vermelho + prato branco com retrato + nome."""
    W, H = 1200, 1560
    m = f'<g transform="translate(600 520) scale(0.95) translate(-600 -500)">{_retrato()}</g>'
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <rect x="40" y="40" width="{W-80}" height="{H-80}" rx="110" fill="{VERMELHO}" stroke="{BRANCO}" stroke-width="12"/>
  <circle cx="600" cy="520" r="372" fill="{BRANCO}"/>
  <clipPath id="med"><circle cx="600" cy="520" r="372"/></clipPath>
  <g clip-path="url(#med)">{m}</g>
  <text x="600" y="1170" text-anchor="middle" font-family="{FONTE}" font-weight="600" font-size="96" fill="{BRANCO}" letter-spacing="-1">Cozinha da</text>
  <text x="600" y="1322" text-anchor="middle" font-family="{FONTE}" font-weight="800" font-size="190" fill="{BRANCO}" letter-spacing="-5">Alexandra</text>
  <text x="600" y="1404" text-anchor="middle" font-family="{FONTE}" font-weight="600" font-size="46" fill="#F3D9DA" letter-spacing="7">ENTREGUE POR MANDA BUÉ</text>
</svg>'''


ficheiros = {}

# Cliente — símbolo da marca (rosto, vermelho+branco+preto); monocromático usa o "A"
r = simbolo_rosto()
ficheiros['cliente/icon.png'] = (svg(r, VERMELHO, 0.92, keyline=True), 1024)
ficheiros['cliente/android-icon-background.png'] = (svg('', VERMELHO), 512)
ficheiros['cliente/android-icon-foreground.png'] = (svg(r, None, 0.68), 512)
ficheiros['cliente/android-icon-monochrome.png'] = (svg(marca_A(BRANCO, BRANCO, BRANCO), None, 0.72), 432)
ficheiros['cliente/splash-icon.png'] = (svg(r, None, 0.96), 1024)
ficheiros['cliente/favicon.png'] = (svg(r, VERMELHO, 0.92, keyline=True), 48)

# Operador — Manda Bué (carvão)
mo = marca(anel=VERMELHO)
ficheiros['operador/icon.png'] = (svg(mo, CARVAO, 0.92), 1024)
ficheiros['operador/android-icon-background.png'] = (svg('', CARVAO), 512)
ficheiros['operador/android-icon-foreground.png'] = (svg(mo, None, 0.72), 512)
ficheiros['operador/android-icon-monochrome.png'] = (svg(marca(BRANCO, BRANCO, BRANCO), None, 0.72), 432)
ficheiros['operador/splash-icon.png'] = (svg(marca(anel=VERMELHO), None, 1.0), 1024)
ficheiros['operador/favicon.png'] = (svg(mo, CARVAO, 0.92), 48)

# Peças de marca (docs)
ficheiros['marca/logotipo.png'] = (logotipo(), None)
ficheiros['marca/logotipo-fundo-claro.png'] = (logotipo('#FFFFFF'), None)
ficheiros['marca/letreiro.png'] = (letreiro(), None)
ficheiros['marca/simbolo.png'] = (svg(simbolo_rosto(), VERMELHO, 0.92, keyline=True), 1024)
ficheiros['marca/simbolo-abstrato.png'] = (svg(marca_A(), VERMELHO, 0.92, keyline=True), 1024)
ficheiros['marca/simbolo-operador.png'] = (svg(marca(anel=VERMELHO), CARVAO, 0.92), 1024)

import json, os
os.makedirs('svg', exist_ok=True)
lista = []
for nome, (conteudo, tam) in ficheiros.items():
    caminho_svg = 'svg/' + nome.replace('/', '__').replace('.png', '.svg')
    open(caminho_svg, 'w').write(conteudo)
    lista.append({'svg': caminho_svg, 'png': 'out/' + nome, 'tamanho': tam})
open('svg/logotipo.svg', 'w').write(logotipo())
open('svg/simbolo.svg', 'w').write(svg(simbolo_rosto(), VERMELHO, 0.92, keyline=True))
open('simbolo.svg', 'w').write(svg(simbolo_rosto(), VERMELHO, 0.92, keyline=True))
open('logotipo.svg', 'w').write(logotipo())
json.dump(lista, open('lista.json', 'w'), indent=1)
print(len(lista), 'ficheiros')
