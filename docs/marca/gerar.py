# Marca Manda Bué: prato (anel) + monograma MB em traço contínuo + linhas de velocidade douradas.
VERMELHO='#B5121B'; CARVAO='#1F1A17'; BRANCO='#FFFFFF'; DOURADO='#F4B400'

def marca(anel=BRANCO, letras=BRANCO, linhas=DOURADO):
    # tudo desenhado numa área de 1024, centrado em (512,512)
    return f'''
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="540" cy="512" r="292" stroke="{anel}" stroke-width="40"/>
    <path d="M359 636 V392 L433 512 L507 392 V636" stroke="{letras}" stroke-width="58"/>
    <path d="M595 392 V636 M595 392 H647 a58 58 0 0 1 0 116 H595 M595 508 H659 a64 64 0 0 1 0 128 H595" stroke="{letras}" stroke-width="58"/>
    <path d="M108 432 H200 M72 512 H200 M108 592 H200" stroke="{linhas}" stroke-width="34"/>
  </g>'''

def svg(conteudo, fundo=None, escala=1.0, tamanho=1024):
    f = f'<rect width="1024" height="1024" fill="{fundo}"/>' if fundo else ''
    t = f'translate({512*(1-escala)} {512*(1-escala)}) scale({escala})'
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{tamanho}" height="{tamanho}" viewBox="0 0 1024 1024">{f}<g transform="{t}">{conteudo}</g></svg>'

def logotipo_horizontal(fundo=None, cor_texto=CARVAO):
    # marca num quadrado vermelho arredondado + nome
    m = svg(marca(), VERMELHO, 0.86).replace('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">','').replace('</svg>','')
    f = f'<rect width="1600" height="480" fill="{fundo}"/>' if fundo else ''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="480" viewBox="0 0 1600 480">{f}
  <defs><clipPath id="c"><rect x="40" y="40" width="400" height="400" rx="88"/></clipPath></defs>
  <g clip-path="url(#c)"><g transform="translate(40 40) scale(0.390625)">{m}</g></g>
  <text x="500" y="262" font-family="Liberation Sans, Arial, Helvetica, sans-serif" font-weight="700" font-size="150" fill="{cor_texto}" letter-spacing="-3">Manda <tspan fill="{VERMELHO}">Bué</tspan></text>
  <text x="506" y="352" font-family="Liberation Sans, Arial, Helvetica, sans-serif" font-size="58" fill="#5F6368" letter-spacing="10">DELIVERY ANGOLA</text>
</svg>'''

ficheiros = {}
for app, fundo, anel in (('cliente', VERMELHO, BRANCO), ('operador', CARVAO, VERMELHO)):
    m = marca(anel=anel)
    ficheiros[f'{app}/icon.png'] = (svg(m, fundo, 0.92), 1024)
    ficheiros[f'{app}/android-icon-background.png'] = (svg('', fundo), 512)
    # zona segura do ícone adaptativo: ~66% do centro
    ficheiros[f'{app}/android-icon-foreground.png'] = (svg(m, None, 0.72), 512)
    ficheiros[f'{app}/android-icon-monochrome.png'] = (svg(marca(BRANCO, BRANCO, BRANCO), None, 0.72), 432)
    ficheiros[f'{app}/splash-icon.png'] = (svg(marca(anel=BRANCO), None, 1.0), 1024)
    ficheiros[f'{app}/favicon.png'] = (svg(m, fundo, 0.92), 48)
ficheiros['marca/logotipo.png'] = (logotipo_horizontal(), None)
ficheiros['marca/logotipo-fundo-claro.png'] = (logotipo_horizontal('#FFFFFF'), None)
ficheiros['marca/simbolo.png'] = (svg(marca(), VERMELHO, 0.92), 1024)
ficheiros['marca/simbolo-operador.png'] = (svg(marca(anel=VERMELHO), CARVAO, 0.92), 1024)

import json, os
os.makedirs('svg', exist_ok=True)
lista = []
for nome, (conteudo, tam) in ficheiros.items():
    caminho_svg = 'svg/' + nome.replace('/', '__').replace('.png', '.svg')
    open(caminho_svg, 'w').write(conteudo)
    lista.append({'svg': caminho_svg, 'png': 'out/' + nome, 'tamanho': tam})
open('svg/logotipo.svg','w').write(logotipo_horizontal())
open('svg/simbolo.svg','w').write(svg(marca(), VERMELHO, 0.92))
json.dump(lista, open('lista.json', 'w'), indent=1)
print(len(lista), 'ficheiros')
