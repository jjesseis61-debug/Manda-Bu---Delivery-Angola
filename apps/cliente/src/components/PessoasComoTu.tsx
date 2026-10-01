import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { pessoasComoTu } from '@/lib/api';
import { formatarKz } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { PessoaComoTu } from '@/lib/tipos';

import { Cartao, Subtitulo } from './ui';

/** Exemplos reais do mês; o bloco não aparece com menos de 2 exemplos (o servidor devolve vazio) */
export function PessoasComoTu() {
  const { ligada } = useSessao();
  const [exemplos, setExemplos] = useState<PessoaComoTu[]>([]);

  useEffect(() => {
    if (!ligada('pessoas_como_tu')) return;
    pessoasComoTu().then(setExemplos).catch(() => setExemplos([]));
  }, [ligada]);

  if (!ligada('pessoas_como_tu') || exemplos.length < 2) return null;
  return (
    <Cartao>
      <Subtitulo>Pessoas como tu este mês</Subtitulo>
      {exemplos.map((e) => (
        <View key={e.nome_exibido} style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
          <Text style={{ fontSize: 15 }}>
            {e.nome_exibido} · {e.amigos} amigos
          </Text>
          <Text style={{ fontSize: 15, fontWeight: '700', color: cores.sucesso }}>{formatarKz(e.valor)}</Text>
        </View>
      ))}
    </Cartao>
  );
}
