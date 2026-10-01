import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { PessoasComoTu } from '@/components/PessoasComoTu';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { destaquesMes, minhaPosicao, totalPagoMes } from '@/lib/api';
import { formatarKz, mensagemErro, textoAmigosEmFalta, valorDestaque } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Destaque, MinhaPosicao } from '@/lib/tipos';

/** C3. Destaques do mês */
export default function Destaques() {
  const router = useRouter();
  const { ligada, parametros } = useSessao();
  const [lista, setLista] = useState<Destaque[] | null>(null);
  const [eu, setEu] = useState<MinhaPosicao | null>(null);
  const [totalPago, setTotalPago] = useState<number | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('destaques')) return;
      Promise.all([destaquesMes(), minhaPosicao(), totalPagoMes()])
        .then(([l, p, t]) => {
          setLista(l);
          setEu(p);
          setTotalPago(t);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [ligada]),
  );

  if (!ligada('destaques')) return <Redirect href="/inicio" />;
  if (!lista && !erro) return <ACarregar />;

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}

      {totalPago !== null && totalPago > 0 && (
        <Cartao>
          <Paragrafo suave>Pago aos nossos clientes este mês</Paragrafo>
          <Text style={{ fontSize: 24, fontWeight: '800', color: cores.sucesso }}>{formatarKz(totalPago)}</Text>
        </Cartao>
      )}

      <Subtitulo>Top {parametros?.tamanho_top ?? ''} do mês</Subtitulo>
      {lista && lista.length === 0 && (
        <Paragrafo suave>Ainda ninguém entrou na lista este mês. Partilha o teu código e sê o primeiro.</Paragrafo>
      )}
      {lista?.map((d) => {
        const valor = valorDestaque(d.valor, d.valor_min, d.valor_max);
        return (
          <View
            key={d.posicao}
            style={{
              flexDirection: 'row',
              justifyContent: 'space-between',
              paddingVertical: 8,
              borderBottomWidth: 1,
              borderBottomColor: cores.linha,
              backgroundColor: d.sou_eu ? cores.avisoFundo : undefined,
            }}>
            <Text style={{ fontSize: 15, fontWeight: d.sou_eu ? '700' : '400', flex: 1 }}>
              {d.posicao}. {d.nome_exibido}
              {d.sou_eu ? ' (tu)' : ''} · {d.amigos} {d.amigos === 1 ? 'amigo' : 'amigos'}
            </Text>
            {valor && <Text style={{ fontSize: 15, fontWeight: '700', color: cores.sucesso }}>{valor}</Text>}
          </View>
        );
      })}

      {eu && !eu.no_top && (
        <Cartao>
          <Linha
            esquerda={`${eu.nome_exibido} (tu)`}
            direita={eu.posicao ? `${eu.posicao}.º lugar` : 'Ainda sem ganhos este mês'}
            forte
          />
          {parametros && <Paragrafo>{textoAmigosEmFalta(eu.amigos_em_falta, parametros.tamanho_top)}</Paragrafo>}
        </Cartao>
      )}

      <PessoasComoTu />

      <Botao titulo="Privacidade na lista" variante="texto" aoCarregar={() => router.push('/privacidade')} />
    </Ecra>
  );
}
