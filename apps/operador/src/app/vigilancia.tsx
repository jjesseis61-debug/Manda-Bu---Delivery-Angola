import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { CasosAgente, type OpcoesCasos } from '@/components/CasosAgente';
import { Guarda } from '@/components/Guarda';
import { Aviso, Botao, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  abrirVigilancia,
  aparelhosPartilhados,
  decidirCasoConvida,
  lerCasosConvida,
  painelVigilancia,
  vigiarDeNovo,
  type AparelhoPartilhado,
  type PainelVigilancia,
} from '@/lib/api';
import { diaLuanda, formatarData, formatarDia, formatarKz } from '@/lib/formatar';
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

/** Nomes dos motivos de anulação (servidor) */
const MOTIVOS: Record<string, string> = {
  mesmo_dispositivo: 'Mesmo telemóvel',
  limite_local: 'Muitos no mesmo local',
  numero_pagamento_partilhado: 'Número de pagamento partilhado',
  limite_semanal: 'Limite semanal',
  pedido_estornado: 'Pedido estornado',
  rejeitado_verificacao: 'Rejeitado na verificação',
  pedido_minimo: 'Abaixo do pedido mínimo',
};

/** #9. Resumo: ganhos à espera e anulados, levantamentos por pagar, picos por dia e quem mais ganha */
function PainelResumo() {
  const router = useRouter();
  const [dias, setDias] = useState('14');
  const [p, setP] = useState<PainelVigilancia | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  useFocusEffect(
    useCallback(() => {
      setErro(null);
      painelVigilancia(Number(dias))
        .then(setP)
        .catch(() => setErro('Não foi possível carregar o painel.'));
    }, [dias]),
  );
  if (erro) return <Aviso tipo="erro">{erro}</Aviso>;
  if (!p) return null;
  const picos = p.serie.filter((s) => s.pico);
  const comPedidos = p.serie.filter((s) => s.contas + s.ligacoes + s.ganhos > 0);
  return (
    <Cartao estilo={{ gap: espaco.s }}>
      <Subtitulo>Painel de vigilância</Subtitulo>
      <Escolha
        opcoes={[{ valor: '7', rotulo: '7 dias' }, { valor: '14', rotulo: '14 dias' }, { valor: '30', rotulo: '30 dias' }]}
        valor={dias}
        aoMudar={setDias}
      />
      <Linha
        esquerda="Ganhos à espera de verificação"
        direita={`${p.em_verificacao.n} · ${formatarKz(p.em_verificacao.valor)}`}
        forte={p.em_verificacao.n > 0}
      />
      {p.em_verificacao.mais_antigo && (
        <Paragrafo suave>{`O mais antigo é de ${formatarData(p.em_verificacao.mais_antigo, true)}.`}</Paragrafo>
      )}
      <Linha
        esquerda="Levantamentos por pagar"
        direita={`${p.levantamentos.n} · ${formatarKz(p.levantamentos.valor)}`}
        forte={p.levantamentos.n > 0}
      />
      {p.levantamentos.n > 0 && (
        <Paragrafo suave>
          {`${p.levantamentos.pedidos} por aprovar · ${p.levantamentos.aprovados} aprovados por pagar${
            p.levantamentos.mais_antigo ? ` · o mais antigo de ${formatarData(p.levantamentos.mais_antigo, true)}` : ''
          }`}
        </Paragrafo>
      )}
      <Linha esquerda={`Ganhos anulados (${p.dias} dias)`} direita={`${p.anulados.n} · ${formatarKz(p.anulados.valor)}`} />
      {p.anulados.por_motivo.map((m) => (
        <Linha key={m.motivo} esquerda={`  ${MOTIVOS[m.motivo] ?? m.motivo}`} direita={`${m.n} · ${formatarKz(m.valor)}`} />
      ))}
      <Linha esquerda="Telemóveis com várias contas" direita={String(p.aparelhos_partilhados)} forte={p.aparelhos_partilhados > 0} />

      <Text style={{ fontWeight: '700', color: cores.texto, marginTop: espaco.s }}>Picos por dia</Text>
      <Paragrafo suave>
        {`Média por dia: ${p.medias.contas} contas novas · ${p.medias.ligacoes} códigos usados · ${p.medias.ganhos} ganhos. ` +
          'Marca-se um dia com mais do dobro da média (e pelo menos 5).'}
      </Paragrafo>
      {picos.length > 0 && <Aviso>{`${picos.length} dia(s) com pico: vê se as contas novas se convidaram umas às outras.`}</Aviso>}
      {comPedidos.length === 0 && <Paragrafo suave>Sem movimento no período.</Paragrafo>}
      {comPedidos
        .slice()
        .reverse()
        .map((s) => (
          <Linha
            key={s.dia}
            esquerda={`${s.pico ? '⚠️ ' : ''}${formatarDia(s.dia)}`}
            direita={`${s.contas} contas · ${s.ligacoes} códigos · ${s.ganhos} ganhos`}
            forte={s.pico}
          />
        ))}

      {p.topo.length > 0 && <Text style={{ fontWeight: '700', color: cores.texto, marginTop: espaco.s }}>Quem mais ganhou</Text>}
      {p.topo.map((t) => (
        <View key={t.cliente_id} style={{ borderTopWidth: 1, borderTopColor: cores.linha, paddingTop: espaco.xs }}>
          <Text style={{ fontWeight: '700', color: cores.texto }}>
            {t.nome}
            {t.codigo ? ` · ${t.codigo}` : ''}
            {t.nivel && t.nivel !== 'normal' ? ` · ${t.nivel === 'ouro' ? 'Ouro' : 'Embaixador'}` : ''}
          </Text>
          <Text style={{ color: t.so_um_pedido > t.indicados / 2 || t.anulados > 0 ? cores.erro : cores.textoSuave }}>
            {`${formatarKz(t.valor)} em ${t.ganhos} ganho(s) · ${t.indicados} amigo(s) · ${t.so_um_pedido} só com 1 pedido` +
              (t.anulados > 0 ? ` · ${t.anulados} anulado(s)` : '')}
          </Text>
        </View>
      ))}
      <Botao titulo="Ver levantamentos" variante="texto" aoCarregar={() => router.push('/levantamentos')} />
    </Cartao>
  );
}

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
        <PainelResumo />
        <CasosAgente inicioPadrao={diaLuanda(-28)} fimPadrao={hoje} opcoes={opcoes} />
        <AparelhosPartilhados />
        <Botao titulo="Ir para a Verificação dos ganhos" variante="texto" aoCarregar={() => router.push('/verificacao')} />
      </Ecra>
    </Guarda>
  );
}
