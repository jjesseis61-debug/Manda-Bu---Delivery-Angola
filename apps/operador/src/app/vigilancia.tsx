import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { CasosAgente, type OpcoesCasos } from '@/components/CasosAgente';
import { Guarda } from '@/components/Guarda';
import { Botao, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { abrirVigilancia, aparelhosPartilhados, decidirCasoConvida, lerCasosConvida, vigiarDeNovo, type AparelhoPartilhado } from '@/lib/api';
import { diaLuanda, formatarData, formatarKz } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { CasoConvida } from '@/lib/tipos';

const opcoes: OpcoesCasos<CasoConvida> = {
  descricao:
    'O agente procura redes de contas no Convida e Ganha: o mesmo telemóvel em várias contas, levantamentos para o número de ' +
    'um indicado, indicados que só fazem o pedido do desconto, muitos no mesmo dia ou no mesmo local. Vizinhos e famílias ' +
    'são legítimos. Só lê dados (sem nomes nem telefones): quem decide és tu, na Verificação dos ganhos.',
  carregar: lerCasosConvida,
  abrir: abrirVigilancia,
  decidir: decidirCasoConvida,
  deNovo: vigiarDeNovo,
  titulo: (c) => `${c.indicador}${c.codigo ? ` · código ${c.codigo}` : ''}`,
  sinais: (c) =>
    `${c.sinais.indicados} indicados · ${c.sinais.telemovel_partilhado} com o mesmo telemóvel · ` +
    `${c.sinais.levantamento_para_indicado} levantamentos para um indicado · ${c.sinais.so_um_pedido} só com o pedido do desconto · ` +
    `${c.sinais.mesmo_local} no mesmo local · ganhos ${formatarKz(c.sinais.ganhos_kz)}`,
  perguntarA: () => null,
  textoAbrir: 'Abrir vigilância do período',
};

/** Telemóveis com várias contas: só para olhar (não se bloqueia ninguém; famílias partilham telemóveis) */
function AparelhosPartilhados() {
  const [lista, setLista] = useState<AparelhoPartilhado[] | null>(null);
  useFocusEffect(
    useCallback(() => {
      aparelhosPartilhados()
        .then(setLista)
        .catch(() => setLista([]));
    }, []),
  );
  if (!lista) return null;
  return (
    <Cartao estilo={{ gap: espaco.s }}>
      <Subtitulo>Telemóveis com várias contas ({lista.length})</Subtitulo>
      <Paragrafo suave>
        Só um alerta: ninguém é bloqueado (famílias partilham telemóveis). Vê se as contas se convidaram umas às outras.
      </Paragrafo>
      {lista.length === 0 && <Paragrafo suave>Nenhum telemóvel acima do limite.</Paragrafo>}
      {lista.map((a) => (
        <View key={a.chave} style={{ borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.xs, gap: 2 }}>
          <Text style={{ fontWeight: '700', color: cores.texto }}>
            {a.contas} contas · {a.modelo ?? a.plataforma} · último uso {formatarData(a.ultimo_em, true)}
          </Text>
          {a.clientes.map((c) => (
            <Text
              key={c.cliente_id}
              style={{ color: cores.texto }}
              onPress={c.telefone ? () => Linking.openURL(`tel:+244${c.telefone}`) : undefined}>
              • {c.nome}
              {c.telefone ? ` (${c.telefone})` : ''} · {c.pedidos} pedido{c.pedidos === 1 ? '' : 's'}
              {c.convidado_por ? ` · convidado por ${c.convidado_por}` : ''}
            </Text>
          ))}
        </View>
      ))}
    </Cartao>
  );
}

/** Vigilância do Convida e Ganha: casos do agente vigilante */
export default function Vigilancia() {
  const router = useRouter();
  const hoje = diaLuanda();
  return (
    <Guarda permissoes={['indicacoes.verificar']}>
      <Ecra>
        <CasosAgente inicioPadrao={diaLuanda(-28)} fimPadrao={hoje} opcoes={opcoes} />
        <AparelhosPartilhados />
        <Botao titulo="Ir para a Verificação dos ganhos" variante="texto" aoCarregar={() => router.push('/verificacao')} />
      </Ecra>
    </Guarda>
  );
}
