import { Redirect, useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { PartilharCodigo } from '@/components/PartilharCodigo';
import { PessoasComoTu } from '@/components/PessoasComoTu';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerSaldo, meusAmigos } from '@/lib/api';
import { formatarKz, mensagemErro, textoAmigo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Amigo, Saldo } from '@/lib/tipos';

/** C1. Convida e Ganha */
export default function Convida() {
  const router = useRouter();
  const { perfil, ligada } = useSessao();
  const [saldo, setSaldo] = useState<Saldo | null>(null);
  const [amigos, setAmigos] = useState<Amigo[] | null>(null);
  const [verExpirados, setVerExpirados] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

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

  if (!ligada('indicacao')) return <Redirect href="/inicio" />;
  if (!amigos && !erro) return <ACarregar />;

  const activos = (amigos ?? []).filter((a) => a.estado !== 'expirado');
  const expirados = (amigos ?? []).filter((a) => a.estado === 'expirado');

  return (
    <Ecra>
      <Cartao>
        <Paragrafo suave>O teu código de convite</Paragrafo>
        <PartilharCodigo />
      </Cartao>

      {erro && <Aviso tipo="erro">{erro}</Aviso>}

      {saldo && (
        <Cartao>
          <Linha esquerda="Ganho hoje" direita={formatarKz(saldo.ganho_hoje)} />
          <Linha esquerda="Ganho esta semana" direita={formatarKz(saldo.ganho_semana)} />
          <Linha esquerda="Saldo disponível" direita={formatarKz(saldo.saldo_disponivel)} forte />
          {saldo.em_verificacao > 0 && (
            <>
              <Linha esquerda="Em verificação" direita={formatarKz(saldo.em_verificacao)} />
              <Text style={{ color: cores.textoSuave, fontSize: 13 }}>Confirmamos estes pedidos antes de pagar.</Text>
            </>
          )}
        </Cartao>
      )}

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
        <Paragrafo suave>
          Ainda não convidaste ninguém. Partilha o teu código: os teus amigos ganham desconto no primeiro pedido e tu ganhas em
          cada pedido deles.
        </Paragrafo>
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
