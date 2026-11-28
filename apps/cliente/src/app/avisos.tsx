import { useFocusEffect, useRouter, type Href } from 'expo-router';
import { useCallback, useState } from 'react';
import { Platform, Pressable, Text, View } from 'react-native';

import { ACarregar, Aviso as Caixa, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { marcarAvisosVistos, meusAvisos, type Aviso } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { rotaDaNotificacao } from '@/lib/push';
import { estadoPushWeb, ligarPushWeb, type EstadoPushWeb } from '@/lib/pushWeb';
import { cores, espaco } from '@/lib/tema';

function quando(iso: string): string {
  const d = new Date(iso);
  const min = Math.round((Date.now() - d.getTime()) / 60000);
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  if (min < 24 * 60) return `há ${Math.round(min / 60)} h`;
  return d.toLocaleDateString('pt-PT');
}

/** Na versão web: ligar os avisos no telemóvel (push): explica o caso do iPhone */
function LigarAvisosWeb() {
  const [estado, setEstado] = useState<EstadoPushWeb | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  useFocusEffect(
    useCallback(() => {
      void estadoPushWeb().then(setEstado);
    }, []),
  );
  if (Platform.OS !== 'web' || !estado || estado === 'ligado' || estado === 'nao_suportado') return null;
  return (
    <Cartao estilo={{ gap: espaco.s }}>
      <Text style={{ fontWeight: '700', color: cores.texto }}>🔔 Receber os avisos no telemóvel</Text>
      {estado === 'instalar_no_iphone' && (
        <Paragrafo suave>
          No iPhone, primeiro adiciona o Manda Bué ao ecrã principal: toca em Partilhar e depois em «Adicionar ao ecrã
          principal». Abre-o a partir daí e volta aqui.
        </Paragrafo>
      )}
      {estado === 'bloqueado' && (
        <Paragrafo suave>
          Os avisos estão bloqueados neste navegador. Abre as definições do site (o cadeado ao lado do endereço) e permite
          as notificações.
        </Paragrafo>
      )}
      {estado === 'desligado' && (
        <>
          <Paragrafo suave>Sabe logo quando o pedido é confirmado, sai para entrega ou ganhas no Convida, mesmo com o site fechado.</Paragrafo>
          <Botao
            titulo="Ligar avisos"
            aCarregar={ocupado}
            aoCarregar={() => {
              setOcupado(true);
              setErro(null);
              ligarPushWeb()
                .then(setEstado)
                .catch((e) => setErro(mensagemErro(e)))
                .finally(() => setOcupado(false));
            }}
          />
        </>
      )}
      {erro && <Caixa tipo="erro">{erro}</Caixa>}
    </Cartao>
  );
}

/** Sino: os avisos do cliente (pedidos, Convida, mensagens), guardados para ler dentro da app */
export default function Avisos() {
  const router = useRouter();
  const [lista, setLista] = useState<Aviso[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useFocusEffect(
    useCallback(() => {
      meusAvisos()
        .then((a) => {
          setLista(a);
          // Abrir o sino marca tudo como visto (o contador volta a zero)
          if (a.some((x) => !x.vista_em)) void marcarAvisosVistos().catch(() => undefined);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, []),
  );

  return (
    <Ecra>
      <LigarAvisosWeb />
      {erro && <Caixa tipo="erro">{erro}</Caixa>}
      {!lista && !erro && <ACarregar />}
      {lista?.length === 0 && <Paragrafo suave>Ainda não tens avisos. Aparecem aqui os do teu pedido e do Convida e Ganha.</Paragrafo>}
      {lista?.map((a) => {
        const rota = rotaDaNotificacao({ ...a.dados, codigo: a.codigo });
        return (
          <Pressable
            key={a.id}
            accessibilityRole={rota ? 'button' : undefined}
            disabled={!rota}
            onPress={() => rota && router.push(rota as Href)}>
            <Cartao estilo={{ gap: 2, borderLeftWidth: a.vista_em ? 0 : 4, borderLeftColor: cores.marca }}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', gap: espaco.s }}>
                <Text style={{ fontWeight: '700', color: cores.texto, flex: 1 }}>{a.titulo}</Text>
                <Text style={{ color: cores.textoSuave, fontSize: 12 }}>{quando(a.criado_em)}</Text>
              </View>
              <Text style={{ color: cores.texto }}>{a.corpo}</Text>
            </Cartao>
          </Pressable>
        );
      })}
    </Ecra>
  );
}
