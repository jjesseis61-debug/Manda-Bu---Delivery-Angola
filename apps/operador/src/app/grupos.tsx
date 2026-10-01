import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { cancelarGrupo, fecharGrupo, gruposDoDia, mudarEstadoGrupo } from '@/lib/api';
import { diaLuanda, formatarKz, horaLuanda, mensagemErro, nomeEstadoGrupo, nomeEstadoPedido } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { GrupoOperador } from '@/lib/tipos';

/** O10. Grupos do dia: todos os pedidos juntos para a preparação e a expedição */
export default function Grupos() {
  const { pode } = useSessao();
  const gerir = pode('pedidos.gerir');
  const [dia, setDia] = useState<'hoje' | 'amanha'>('hoje');
  const [lista, setLista] = useState<GrupoOperador[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [aCancelar, setACancelar] = useState<string | null>(null);
  const [motivo, setMotivo] = useState('');

  const carregar = useCallback(() => {
    setLista(null);
    gruposDoDia(diaLuanda(dia === 'hoje' ? 0 : 1))
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, [dia]);
  useFocusEffect(carregar);

  async function accao(chave: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(chave);
    try {
      await f();
      setACancelar(null);
      setMotivo('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  return (
    <Guarda permissoes={['pedidos.gerir', 'entregas.registar']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'hoje', rotulo: 'Hoje' },
            { valor: 'amanha', rotulo: 'Amanhã' },
          ]}
          valor={dia}
          aoMudar={setDia}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Sem pedidos de grupo.</Paragrafo>}
        {lista?.map((g) => {
          const activos = g.pedidos.filter((p) => p.estado !== 'cancelado');
          return (
            <Cartao key={g.grupo_id}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 18, fontWeight: '800' }}>{horaLuanda(g.hora_entrega)}</Text>
                <Text style={{ fontWeight: '700', color: cores.marca }}>{nomeEstadoGrupo[g.estado]}</Text>
              </View>
              <Text style={{ fontWeight: '600' }}>
                {g.local.referencia ?? 'Local de trabalho'}
                {g.local.zona ? ` · ${g.local.zona}` : ''}
              </Text>
              {g.local.lat !== null && g.local.lng !== null && (
                <Text style={{ color: cores.marca }} onPress={() => Linking.openURL(`https://maps.google.com/?q=${g.local.lat},${g.local.lng}`)}>
                  Abrir no mapa
                </Text>
              )}
              <Text style={{ color: cores.textoSuave }}>
                Organizador: {g.organizador}
                {g.organizador_telefone ? ` · ${g.organizador_telefone}` : ''} ·{' '}
                {g.modo_pagamento === 'empresa' ? 'a empresa paga tudo' : 'cada um paga o seu'}
                {g.estado === 'aberto' ? ` · adesão até às ${horaLuanda(g.prazo_adesao)}` : ''}
              </Text>

              <Subtitulo>Para preparar ({activos.length} pedidos)</Subtitulo>
              {g.resumo.map((r) => (
                <Linha key={r.nome} esquerda={r.nome} direita={`× ${r.qtd}`} />
              ))}

              <Subtitulo>Pedidos</Subtitulo>
              {g.pedidos.map((p) => (
                <View key={p.pedido_id} style={{ gap: 2, paddingVertical: 4, borderBottomWidth: 1, borderBottomColor: cores.linha }}>
                  <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                    <Text style={{ fontWeight: '600', textDecorationLine: p.estado === 'cancelado' ? 'line-through' : 'none' }}>
                      {p.cliente_nome}
                    </Text>
                    <Text>{formatarKz(p.a_pagar)}</Text>
                  </View>
                  <Text style={{ color: cores.textoSuave }}>
                    {nomeEstadoPedido[p.estado] ?? p.estado} · {p.itens.map((i) => `${i.qtd}× ${i.nome}`).join(', ')}
                  </Text>
                  {p.observacoes && <Text style={{ fontStyle: 'italic' }}>“{p.observacoes}”</Text>}
                </View>
              ))}
              <Linha esquerda="Total a receber" direita={formatarKz(g.total_a_pagar)} forte />

              {aCancelar === g.grupo_id ? (
                <>
                  <Campo rotulo="Motivo do cancelamento" value={motivo} onChangeText={setMotivo} />
                  <Botao
                    titulo="Cancelar o grupo"
                    desactivado={!motivo.trim()}
                    aCarregar={ocupado === g.grupo_id}
                    aoCarregar={() => accao(g.grupo_id, () => cancelarGrupo(g.grupo_id, motivo.trim()))}
                  />
                  <Botao titulo="Voltar" variante="texto" aoCarregar={() => setACancelar(null)} />
                </>
              ) : (
                <View style={{ gap: espaco.s }}>
                  {gerir && g.estado === 'aberto' && (
                    <Botao titulo="Fechar o grupo agora" variante="secundario" aCarregar={ocupado === g.grupo_id} aoCarregar={() => accao(g.grupo_id, () => fecharGrupo(g.grupo_id))} />
                  )}
                  {gerir && (g.estado === 'fechado' || g.estado === 'aberto') && (
                    <Botao titulo="Confirmar todos" variante="secundario" aCarregar={ocupado === `${g.grupo_id}c`} aoCarregar={() => accao(`${g.grupo_id}c`, () => mudarEstadoGrupo(g.grupo_id, 'confirmado'))} />
                  )}
                  {gerir && (g.estado === 'fechado' || g.estado === 'aberto') && (
                    <Botao titulo="Todos em preparação" aCarregar={ocupado === `${g.grupo_id}p`} aoCarregar={() => accao(`${g.grupo_id}p`, () => mudarEstadoGrupo(g.grupo_id, 'em_preparacao'))} />
                  )}
                  {g.estado === 'em_preparacao' && (
                    <Botao titulo="Todos saíram para entrega" aCarregar={ocupado === `${g.grupo_id}e`} aoCarregar={() => accao(`${g.grupo_id}e`, () => mudarEstadoGrupo(g.grupo_id, 'em_entrega'))} />
                  )}
                  {g.estado === 'em_preparacao' && (
                    <Paragrafo suave>A entrega e o pagamento de cada pessoa registam-se em Pedidos e entregas.</Paragrafo>
                  )}
                  {gerir && (g.estado === 'aberto' || g.estado === 'fechado') && (
                    <Botao titulo="Cancelar o grupo…" variante="texto" aoCarregar={() => setACancelar(g.grupo_id)} />
                  )}
                </View>
              )}
            </Cartao>
          );
        })}
      </Ecra>
    </Guarda>
  );
}
