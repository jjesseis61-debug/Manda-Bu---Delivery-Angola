import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { PainelNivel } from '@/components/PainelNivel';
import { PartilharCodigo } from '@/components/PartilharCodigo';
import { PessoasComoTu } from '@/components/PessoasComoTu';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerSaldo, meusAmigos } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro, textoAmigo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Amigo, Saldo } from '@/lib/tipos';
import { limparDestino } from '@/lib/visitante';
import Ganhar from '@/app/ganhar';

/** C1. Convida e Ganha */
function ConvidaCliente() {
  const router = useRouter();
  const { carregado, perfil, parametros, ligada } = useSessao();
  const [saldo, setSaldo] = useState<Saldo | null>(null);
  const [amigos, setAmigos] = useState<Amigo[] | null>(null);
  const [verExpirados, setVerExpirados] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  // Chegou aqui depois de criar conta pelo «Convida e ganha» do visitante: destino cumprido
  useEffect(() => {
    void limparDestino();
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (!perfil || !ligada('indicacao')) return;
      Promise.all([lerSaldo(perfil.cliente_id), meusAmigos()])
        .then(([s, a]) => {
          setSaldo(s);
          setAmigos(a);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [perfil, ligada]),
  );

  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('indicacao')) return <Redirect href="/inicio" />;
  if (!amigos && !erro) return <ACarregar />;

  const activos = (amigos ?? []).filter((a) => a.estado !== 'expirado');
  const expirados = (amigos ?? []).filter((a) => a.estado === 'expirado');
  // "Primeira vitória" (Bandura): até o embaixador ganhar a 1.ª comissão, guia-se o primeiro passo.
  const jaGanhou = (amigos ?? []).some((a) => a.ganho_total > 0);
  const gpp = parametros?.ganho_por_pedido ?? 0;
  const descInd = parametros?.desconto_indicado ?? 0;
  // Bónus de boas-vindas: soma-se à 1.ª comissão (uma vez por pessoa); 0 = desligado
  const bonus = parametros?.bonus_boas_vindas ?? 0;

  return (
    <Ecra>
      {!jaGanhou ? (
        <Cartao>
          <Subtitulo>A tua primeira vitória</Subtitulo>
          <Text style={{ fontSize: 20, fontWeight: '800', color: cores.marca, lineHeight: 26 }}>
            Partilha e ganha os teus primeiros{gpp ? ` ${formatarKz(gpp + bonus)}` : ''} 🎉
          </Text>
          <View style={{ gap: 6, marginVertical: 4 }}>
            <Text style={{ color: cores.texto }}>1. Partilha o teu código no WhatsApp.</Text>
            <Text style={{ color: cores.texto }}>
              2. O teu amigo pede e ganha{descInd ? ` ${formatarKz(descInd)}` : ''} de desconto.
            </Text>
            <Text style={{ color: cores.texto }}>3. Ganhas{gpp ? ` ${formatarKz(gpp)}` : ''} por cada pedido dele{parametros?.comissao_primeiro_pedido ? '' : ', a partir do 2.º'}.</Text>
          </View>
          {bonus > 0 && (
            <View style={{ backgroundColor: cores.marcaClara, borderRadius: 8, padding: 10 }}>
              <Text style={{ color: cores.marca, fontWeight: '700' }}>
                🎁 Bónus de boas-vindas: +{formatarKz(bonus)} extra na tua primeira comissão.
              </Text>
            </View>
          )}
          <PartilharCodigo />
          <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Leva 10 segundos · a mensagem já vai pronta.</Text>
        </Cartao>
      ) : (
        <Cartao>
          <Paragrafo suave>O teu código de convite</Paragrafo>
          <PartilharCodigo />
        </Cartao>
      )}

      {erro && <Aviso tipo="erro">{erro}</Aviso>}

      {saldo && (
        <Cartao>
          <Linha esquerda="Ganho hoje" direita={formatarKz(saldo.ganho_hoje)} />
          <Linha esquerda="Ganho esta semana" direita={formatarKz(saldo.ganho_semana)} />
          <Linha esquerda="Saldo disponível" direita={formatarKz(saldo.saldo_disponivel)} forte />
          {(saldo.a_expirar_em_breve ?? 0) > 0 && (
            <Aviso>
              {`${formatarKz(saldo.a_expirar_em_breve ?? 0)} expiram${
                saldo.proxima_expiracao ? ` a partir de ${formatarData(saldo.proxima_expiracao)}` : ' em breve'
              }. Usa em refeições ou levanta antes disso.`}
            </Aviso>
          )}
          {saldo.em_verificacao > 0 && (
            <>
              <Linha esquerda="Em verificação" direita={formatarKz(saldo.em_verificacao)} />
              <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Confirmamos estes pedidos antes de pagar.</Text>
            </>
          )}
        </Cartao>
      )}

      <PainelNivel />

      <View style={{ flexDirection: 'row', gap: 10 }}>
        <View style={{ flex: 1 }}>
          <Botao titulo="Levantar saldo" variante="secundario" aoCarregar={() => router.push('/levantar')} />
        </View>
        {ligada('destaques') && (
          <View style={{ flex: 1 }}>
            <Botao titulo="Destaques" variante="secundario" aoCarregar={() => router.push('/destaques')} />
          </View>
        )}
      </View>

      <Subtitulo>Os teus amigos</Subtitulo>
      {activos.length === 0 && expirados.length === 0 ? (
        <Paragrafo suave>Ainda não convidaste ninguém — partilha o teu código acima.</Paragrafo>
      ) : (
        activos.map((a, i) => (
          <Linha key={`${a.primeiro_nome}-${i}`} esquerda={textoAmigo(a.primeiro_nome, a.estado, a.dias_restantes)} direita={formatarKz(a.ganho_total)} />
        ))
      )}
      {expirados.length > 0 && (
        <Pressable onPress={() => setVerExpirados((v) => !v)}>
          <Text style={{ color: cores.marca, fontWeight: '600' }}>
            {verExpirados ? 'Esconder' : 'Ver'} períodos terminados ({expirados.length})
          </Text>
        </Pressable>
      )}
      {verExpirados &&
        expirados.map((a, i) => (
          <Linha key={`exp-${a.primeiro_nome}-${i}`} esquerda={textoAmigo(a.primeiro_nome, a.estado, null)} direita={formatarKz(a.ganho_total)} />
        ))}

      <PessoasComoTu />

      <Botao titulo="Como funciona" variante="texto" aoCarregar={() => router.push('/como-funciona')} />
    </Ecra>
  );
}

/** Sem conta: a montra do programa (regras e níveis); o código e os ganhos só depois de criar conta */
export default function Convida() {
  const { sessao, perfil } = useSessao();
  if (!sessao || !perfil) return <Ganhar />;
  return <ConvidaCliente />;
}
