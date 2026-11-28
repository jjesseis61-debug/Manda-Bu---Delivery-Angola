import { useEffect, useRef, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { Campo } from '@/components/ui';
import { procurarBairros, procurarNoMapa, type ResultadoMorada } from '@/lib/pesquisaMorada';
import { cores, espaco, raio } from '@/lib/tema';
import type { Zona } from '@/lib/tipos';

/**
 * Caixa "Procurar rua, bairro ou sítio": bairros onde entregamos logo ao escrever e, a seguir,
 * ruas e sítios do mapa (OpenStreetMap). Escolher um resultado move o pino para lá.
 */
export function PesquisaMorada({
  zonas,
  perto,
  aoEscolher,
}: {
  zonas: Zona[];
  perto?: { lat: number; lng: number };
  aoEscolher: (r: ResultadoMorada) => void;
}) {
  const [texto, setTexto] = useState('');
  const [doMapa, setDoMapa] = useState<ResultadoMorada[]>([]);
  const [aProcurar, setAProcurar] = useState(false);
  const [semRede, setSemRede] = useState(false);
  const [escolhido, setEscolhido] = useState(false);
  const pedido = useRef<AbortController | null>(null);

  // Espera que o cliente pare de escrever (poupa dados e respeita o serviço gratuito)
  useEffect(() => {
    setSemRede(false);
    if (escolhido || texto.trim().length < 3) {
      setDoMapa([]);
      return;
    }
    const t = setTimeout(() => {
      pedido.current?.abort();
      const c = new AbortController();
      pedido.current = c;
      setAProcurar(true);
      procurarNoMapa(texto, perto, c.signal)
        .then(setDoMapa)
        .catch((e) => {
          if ((e as Error)?.name !== 'AbortError') {
            setDoMapa([]);
            setSemRede(true);
          }
        })
        .finally(() => setAProcurar(false));
    }, 600);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [texto, escolhido]);

  const bairros = escolhido ? [] : procurarBairros(texto, zonas);
  const lista = [...bairros, ...doMapa.filter((m) => !bairros.some((b) => b.nome === m.nome))];

  return (
    <View style={{ gap: espaco.xs }}>
      <Campo
        rotulo="Procurar rua, bairro ou sítio conhecido"
        placeholder="Ex.: Rua da Missão, Maianga, Largo do Kinaxixi"
        value={texto}
        onChangeText={(t) => {
          setEscolhido(false);
          setTexto(t);
        }}
        autoCorrect={false}
        returnKeyType="search"
      />
      {aProcurar && <Text style={{ color: cores.textoSuave }}>A procurar…</Text>}
      {semRede && <Text style={{ color: cores.textoSuave }}>Sem resultados do mapa agora. Marca o ponto tocando no mapa.</Text>}
      {!aProcurar && !semRede && !escolhido && texto.trim().length >= 3 && lista.length === 0 && (
        <Text style={{ color: cores.textoSuave }}>Não encontrámos. Tenta só o nome da rua ou do bairro.</Text>
      )}
      {lista.length > 0 && (
        <View style={{ borderWidth: 1, borderColor: cores.linha, borderRadius: raio, overflow: 'hidden' }}>
          {lista.map((r, i) => (
            <Pressable
              key={r.id}
              accessibilityRole="button"
              onPress={() => {
                setEscolhido(true);
                setTexto(r.nome);
                setDoMapa([]);
                aoEscolher(r);
              }}
              style={{
                paddingVertical: espaco.s,
                paddingHorizontal: espaco.m,
                borderTopWidth: i === 0 ? 0 : 1,
                borderTopColor: cores.linha,
                backgroundColor: cores.fundo,
              }}>
              <Text style={{ color: cores.texto, fontWeight: '600' }}>
                {r.zonaId ? '📍 ' : ''}
                {r.nome}
              </Text>
              {r.detalhe ? <Text style={{ color: cores.textoSuave, fontSize: 13 }}>{r.detalhe}</Text> : null}
            </Pressable>
          ))}
        </View>
      )}
    </View>
  );
}
