import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { decidirPropostaTurno, lerPropostasTurno } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { PropostaTurno } from '@/lib/tipos';

const nomeTipo: Record<PropostaTurno['tipo'], string> = {
  avisar_atraso: 'Avisar o cliente do atraso',
  confirmar: 'Confirmar o pedido',
  pausar_prato: 'Pausar o prato',
  reforco: 'Pedir reforço de estafetas',
  nota: 'Nota',
};
const nomeEstado: Record<PropostaTurno['estado'], string> = {
  pendente: 'Por decidir',
  aceite: 'Aceite',
  recusada: 'Recusada',
  expirada: 'Caducou',
};

/**
 * Gerente de turno: sugestões do agente para o turno. Nada acontece sem o gerente; ao aceitar, a acção corre
 * com as permissões dele (avisar o cliente, confirmar, pausar o prato). As sugestões caducam em 30 minutos.
 */
export default function Turno() {
  const router = useRouter();
  const [lista, setLista] = useState<PropostaTurno[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [edicao, setEdicao] = useState<Record<string, { motivo: string; minutos: string }>>({});

  const carregar = useCallback(() => {
    lerPropostasTurno().then(setLista, (e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function decidir(p: PropostaTurno, aceitar: boolean) {
    setErro(null);
    setOcupado(p.id);
    try {
      const ed = edicao[p.id];
      await decidirPropostaTurno(
        p.id,
        aceitar,
        p.tipo === 'avisar_atraso' ? (ed?.motivo ?? p.motivo_cliente) : null,
        p.tipo === 'avisar_atraso' ? Number(ed?.minutos ?? p.mais_minutos) || null : null,
      );
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  function cartao(p: PropostaTurno) {
    const ed = edicao[p.id] ?? { motivo: p.motivo_cliente ?? '', minutos: p.mais_minutos ? String(p.mais_minutos) : '' };
    const pendente = p.estado === 'pendente';
    return (
      <Cartao key={p.id}>
        <Text style={{ fontWeight: '700', color: p.prioridade === 'alta' && pendente ? cores.erro : cores.texto }}>
          {nomeTipo[p.tipo]}
          {p.prato ? `: ${p.prato}` : ''}
          {p.cliente ? ` · pedido de ${p.cliente}` : ''}
        </Text>
        <Text style={{ color: cores.textoSuave }}>
          {p.cozinha} · {new Date(p.criado_em).toLocaleTimeString('pt-PT', { hour: '2-digit', minute: '2-digit' })} · {nomeEstado[p.estado]}
          {p.decidido_por ? ` por ${p.decidido_por}` : ''}
        </Text>
        <Text>{p.explicacao}</Text>
        {pendente && (
          <View style={{ gap: espaco.s }}>
            {p.tipo === 'avisar_atraso' && (
              <>
                <Campo
                  rotulo="Mensagem para o cliente"
                  value={ed.motivo}
                  onChangeText={(t) => setEdicao({ ...edicao, [p.id]: { ...ed, motivo: t } })}
                  maxLength={200}
                />
                <Campo
                  rotulo="Minutos a mais"
                  value={ed.minutos}
                  onChangeText={(t) => setEdicao({ ...edicao, [p.id]: { ...ed, minutos: t.replace(/\D/g, '') } })}
                  keyboardType="number-pad"
                />
              </>
            )}
            <Botao
              titulo={p.tipo === 'reforco' || p.tipo === 'nota' ? 'Visto' : 'Aceitar'}
              aCarregar={ocupado === p.id}
              desactivado={p.tipo === 'avisar_atraso' && ed.motivo.trim().length < 3}
              aoCarregar={() => decidir(p, true)}
            />
            <Botao titulo="Recusar" variante="secundario" aoCarregar={() => decidir(p, false)} />
            {p.pedido_id && (
              <Botao
                titulo="Histórico do pedido"
                variante="texto"
                aoCarregar={() => router.push({ pathname: '/pedido/[id]', params: { id: p.pedido_id as string } })}
              />
            )}
          </View>
        )}
      </Cartao>
    );
  }

  const pendentes = lista?.filter((p) => p.estado === 'pendente') ?? [];
  const outras = lista?.filter((p) => p.estado !== 'pendente') ?? [];
  return (
    <Guarda permissoes={['pedidos.gerir']}>
      <Ecra>
        <Paragrafo suave>
          O agente olha para a fila de 5 em 5 minutos quando há algo a pedir atenção e sugere o que fazer. Nada acontece sem
          ti: ao aceitar, a acção é feita em teu nome.
        </Paragrafo>
        <Botao titulo="Actualizar" variante="texto" aoCarregar={carregar} />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {lista === null ? (
          <ACarregar />
        ) : (
          <>
            {pendentes.length === 0 && <Aviso tipo="sucesso">Sem sugestões por decidir.</Aviso>}
            {pendentes.map(cartao)}
            {outras.length > 0 && <Subtitulo>Últimas 12 horas</Subtitulo>}
            {outras.map(cartao)}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
