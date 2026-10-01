import { Redirect, useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Linking, Share, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { cancelarGrupo, fecharGrupo, grupoDetalhe } from '@/lib/api';
import { useCarrinho } from '@/lib/carrinho';
import { linkGrupo } from '@/lib/convite';
import { formatarKz, horaLuanda, mensagemErro, mensagemGrupo, nomeEstadoGrupo, nomeEstadoPedido, tempoEmFalta } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { GrupoDetalhe } from '@/lib/tipos';

/** C13. Grupo: participantes (primeiro nome) e estado, contagem regressiva, "Junta o teu pedido" */
export default function Grupo() {
  const router = useRouter();
  const { codigo } = useLocalSearchParams<{ codigo: string }>();
  const { ligada } = useSessao();
  const carrinho = useCarrinho();
  const [grupo, setGrupo] = useState<GrupoDetalhe | null | undefined>(undefined);
  const [erro, setErro] = useState<string | null>(null);
  const [agora, setAgora] = useState(new Date());
  const [aCancelar, setACancelar] = useState(false);
  const [motivo, setMotivo] = useState('');
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    if (!ligada('pedidos_grupo')) return;
    grupoDetalhe(String(codigo))
      .then(setGrupo)
      .catch((e) => setErro(mensagemErro(e)));
  }, [codigo, ligada]);
  useFocusEffect(carregar);

  // Contagem regressiva do prazo
  useEffect(() => {
    const t = setInterval(() => setAgora(new Date()), 30000);
    return () => clearInterval(t);
  }, []);

  if (!ligada('pedidos_grupo')) return <Redirect href="/inicio" />;
  if (grupo === undefined && !erro) return <ACarregar />;
  if (!grupo) {
    return (
      <Ecra>
        <Aviso tipo="erro">{erro ?? 'Grupo não encontrado. Confirma o link com quem o partilhou.'}</Aviso>
      </Ecra>
    );
  }

  const g = grupo;
  const falta = tempoEmFalta(g.prazo_adesao, agora);
  const aberto = g.estado === 'aberto' && falta !== null;
  const jaPedi = g.participantes.some((p) => p.sou_eu);

  async function partilhar() {
    const mensagem = mensagemGrupo(horaLuanda(g.hora_entrega), g.local, linkGrupo(g.codigo_convite));
    const whatsapp = `whatsapp://send?text=${encodeURIComponent(mensagem)}`;
    if (await Linking.canOpenURL(whatsapp).catch(() => false)) await Linking.openURL(whatsapp);
    else await Share.share({ message: mensagem });
  }

  function juntar() {
    carrinho.definirGrupo({ grupoId: g.grupo_id, codigo: g.codigo_convite, hora: horaLuanda(g.hora_entrega) });
    router.push('/inicio');
  }

  async function accao(f: () => Promise<void>) {
    setErro(null);
    setOcupado(true);
    try {
      await f();
      setACancelar(false);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  return (
    <Ecra>
      <Cartao>
        <Text style={{ fontSize: 20, fontWeight: '800' }}>Entrega às {horaLuanda(g.hora_entrega)}</Text>
        {g.local && <Text style={{ fontSize: 15 }}>{g.local}</Text>}
        <Text style={{ color: cores.textoSuave }}>
          Organizado por {g.sou_organizador ? 'ti' : g.organizador} ·{' '}
          {g.modo_pagamento === 'empresa' ? 'a empresa paga tudo' : 'cada um paga o seu'}
        </Text>
        <Text style={{ fontWeight: '700', color: aberto ? cores.marca : cores.textoSuave }}>
          {aberto ? `Fecha em ${falta} (às ${horaLuanda(g.prazo_adesao)})` : nomeEstadoGrupo[g.estado]}
        </Text>
        {aberto && g.modo_pagamento === 'individual' && g.taxa_estimada !== null && (
          <Text style={{ color: cores.textoSuave, fontSize: 13 }}>
            Entrega dividida por todos: hoje seriam cerca de {formatarKz(g.taxa_estimada)} por pessoa. O valor final fica fixo quando o
            grupo fechar.
          </Text>
        )}
      </Cartao>

      {aberto && !jaPedi && <Botao titulo="Junta o teu pedido" aoCarregar={juntar} />}
      {aberto && <Botao titulo="Convidar colegas no WhatsApp" variante="whatsapp" aoCarregar={partilhar} />}

      <Subtitulo>
        Quem já pediu ({g.participantes.length})
      </Subtitulo>
      {g.participantes.length === 0 && <Paragrafo suave>Ainda ninguém. Sê o primeiro e convida os colegas.</Paragrafo>}
      {g.participantes.map((p, i) => (
        <View key={`${p.nome}-${i}`} style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
          <Text style={{ fontSize: 15, fontWeight: p.sou_eu ? '700' : '400' }}>
            {p.nome}
            {p.sou_eu ? ' (tu)' : ''}
          </Text>
          <Text style={{ color: cores.textoSuave }}>{nomeEstadoPedido[p.estado] ?? p.estado}</Text>
        </View>
      ))}

      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {g.sou_organizador && (g.estado === 'aberto' || g.estado === 'fechado') && (
        <>
          {aCancelar ? (
            <Cartao>
              <Campo rotulo="Motivo (opcional, os colegas vêem-no no pedido)" value={motivo} onChangeText={setMotivo} />
              <Botao titulo="Cancelar o grupo" aCarregar={ocupado} aoCarregar={() => accao(() => cancelarGrupo(g.grupo_id, motivo.trim() || null))} />
              <Botao titulo="Voltar" variante="texto" aoCarregar={() => setACancelar(false)} />
            </Cartao>
          ) : (
            <>
              {g.estado === 'aberto' && (
                <Botao titulo="Fechar o grupo agora" variante="secundario" aCarregar={ocupado} aoCarregar={() => accao(() => fecharGrupo(g.grupo_id))} />
              )}
              <Botao titulo="Cancelar o grupo…" variante="texto" aoCarregar={() => setACancelar(true)} />
            </>
          )}
        </>
      )}
    </Ecra>
  );
}
