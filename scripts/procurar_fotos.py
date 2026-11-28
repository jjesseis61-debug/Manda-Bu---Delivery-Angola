"""Procura fotos de licença livre na Wikimedia Commons para os pratos.

Lê docs/fotos-pratos/pesquisa.json ({chave: [termos]}) e grava em docs/fotos-pratos/candidatos/
as primeiras fotos de cada termo (640 px) e um candidatos.json com a origem, o autor e a licença.
Corre no GitHub Actions (a rede do contentor de desenvolvimento não chega à Wikimedia)."""
import json, pathlib, re, urllib.parse, urllib.request

RAIZ = pathlib.Path(__file__).resolve().parent.parent / 'docs' / 'fotos-pratos'
SAIDA = RAIZ / 'candidatos'
UA = 'MandaBue/1.0 (https://github.com/jjesseis61-debug)'
LIVRES = re.compile(r'^(CC0|Public domain|CC BY(-SA)? [0-9.]+)', re.I)


def pedir(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=60).read()


def procurar(termo, limite=12):
    q = urllib.parse.urlencode({
        'action': 'query', 'format': 'json', 'generator': 'search', 'gsrnamespace': 6,
        'gsrsearch': f'{termo} filetype:bitmap', 'gsrlimit': limite, 'prop': 'imageinfo',
        'iiprop': 'url|size|mime|extmetadata', 'iiurlwidth': 640,
        'iiextmetadatafilter': 'LicenseShortName|Artist|ObjectName'})
    paginas = json.loads(pedir('https://commons.wikimedia.org/w/api.php?' + q)).get('query', {}).get('pages', {})
    return sorted(paginas.values(), key=lambda p: p.get('index', 99))


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    pesquisa = json.loads((RAIZ / 'pesquisa.json').read_text())
    resultado = []
    for chave, termos in pesquisa.items():
        n = 0
        vistos = set()
        for termo in termos:
            for p in procurar(termo):
                i = p['imageinfo'][0]
                meta = i.get('extmetadata', {})
                licenca = meta.get('LicenseShortName', {}).get('value', '')
                if p['title'] in vistos or i.get('mime') not in ('image/jpeg', 'image/png') or not LIVRES.match(licenca):
                    continue
                if i['width'] < 600 or i['height'] < 400:
                    continue
                vistos.add(p['title'])
                n += 1
                nome = f'{chave}-{n:02d}.jpg'
                (SAIDA / nome).write_bytes(pedir(i['thumburl']))
                autor = re.sub(r'<[^>]+>', '', meta.get('Artist', {}).get('value', '')).strip()
                resultado.append({'ficheiro': nome, 'chave': chave, 'termo': termo, 'titulo': p['title'],
                                  'pagina': i['descriptionurl'], 'original': i['url'], 'miniatura': i['thumburl'],
                                  'licenca': licenca, 'autor': autor})
                if n >= 8:
                    break
            if n >= 8:
                break
    (SAIDA / 'candidatos.json').write_text(json.dumps(resultado, ensure_ascii=False, indent=1))
    print(len(resultado), 'candidatos')


if __name__ == '__main__':
    main()
