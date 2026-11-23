import * as Notifications from 'expo-notifications';
import { type Href, Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';

import { EcraCadeado } from '@/components/EcraCadeado';
import { CadeadoProvider } from '@/lib/cadeadoContexto';
import { CarrinhoProvider } from '@/lib/carrinho';
import { esquecerProprioCodigo } from '@/lib/convite';
import { convitePartilhaDe, partilharPrato } from '@/lib/partilha';
import { tirarPartilhaPendente } from '@/lib/partilhaPendente';
import { registarEsteAparelho } from '@/lib/dispositivo';
import { desligarPushWeb, renovarPushWeb } from '@/lib/pushWeb';
import { activarPush, desactivarPush, rotaDaNotificacao } from '@/lib/push';
import { SessaoProvider, useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

/** Regista o telemóvel para push depois do registo e abre o ecrã certo ao tocar numa notificação */
function EfeitosSessao() {
  const { perfil, parametros, ligada } = useSessao();
  const router = useRouter();

  // «Entrar e partilhar»: depois de entrar (ou criar conta), a partilha continua sozinha com o código
  const convite = convitePartilhaDe(perfil, parametros, ligada('indicacao'));
  useEffect(() => {
    if (!perfil?.codigo || !convite) return;
    void tirarPartilhaPendente().then((p) => p && partilharPrato(p.nome, p.id, convite));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [perfil?.codigo, convite?.codigo]);

  useEffect(() => {
    if (perfil) void activarPush().catch(() => undefined);
    if (perfil) void registarEsteAparelho();
    if (perfil) void renovarPushWeb();
    // Código guardado de um link próprio (aberto antes de entrar): não é convite, apaga-se
    if (perfil) void esquecerProprioCodigo(perfil.codigo);
  }, [perfil]);

  useEffect(() => {
    const sub = Notifications.addNotificationResponseReceivedListener((resposta) => {
      const rota = rotaDaNotificacao(resposta.notification.request.content.data);
      if (rota) router.push(rota as Href);
    });
    return () => sub.remove();
  }, [router]);

  return null;
}

/** Ao sair da conta: este telemóvel/navegador deixa de receber os avisos dela */
async function sairDosAvisos() {
  await Promise.all([desactivarPush(), desligarPushWeb()]);
}

export default function LayoutRaiz() {
  return (
    <SessaoProvider aoSair={sairDosAvisos}>
      {/* Cadeado opcional (código / biometria) por cima de tudo: ver docs/plano-cadeado-conta.md */}
      <CadeadoProvider>
      <CarrinhoProvider>
        <EfeitosSessao />
        <Stack
          screenOptions={{
            headerTintColor: cores.marca,
            headerTitleStyle: { color: cores.texto },
            headerBackButtonDisplayMode: 'minimal',
          }}>
          <Stack.Screen name="index" options={{ headerShown: false }} />
          <Stack.Screen name="entrar" options={{ headerShown: false }} />
          <Stack.Screen name="registo" options={{ title: 'Criar conta', headerBackVisible: false }} />
          <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
          <Stack.Screen name="convite/[codigo]" options={{ headerShown: false }} />
          <Stack.Screen name="p/[id]" options={{ headerShown: false }} />
          <Stack.Screen name="condominio/[codigo]" options={{ title: 'Condomínio' }} />
          <Stack.Screen name="carrinho" options={{ title: 'O teu pedido' }} />
          <Stack.Screen name="pedido/[id]" options={{ title: 'Pedido' }} />
          <Stack.Screen name="levantar" options={{ title: 'Levantar saldo' }} />
          <Stack.Screen name="como-funciona" options={{ title: 'Como funciona' }} />
          <Stack.Screen name="cozinha" options={{ title: 'A cozinha' }} />
          <Stack.Screen name="destaques" options={{ title: 'Destaques do mês' }} />
          <Stack.Screen name="privacidade" options={{ title: 'Privacidade na lista' }} />
          <Stack.Screen name="notificacoes" options={{ title: 'Notificações' }} />
          <Stack.Screen name="avisos" options={{ title: 'Avisos' }} />
          <Stack.Screen name="avaliar/[id]" options={{ title: 'Avaliar pedido' }} />
          <Stack.Screen name="avaliacoes" options={{ title: 'Avaliações' }} />
          <Stack.Screen name="grupos" options={{ title: 'Pedidos de grupo' }} />
          <Stack.Screen name="grupo/novo" options={{ title: 'Junta Bué' }} />
          <Stack.Screen name="grupo/[codigo]" options={{ title: 'Pedido de grupo' }} />
          <Stack.Screen name="enderecos/index" options={{ title: 'Endereços' }} />
          <Stack.Screen name="montar/[id]" options={{ title: 'Servir o prato' }} />
          <Stack.Screen name="visita/[cozinha]" options={{ title: 'Cardápio' }} />
          <Stack.Screen name="explorar" options={{ title: 'O teu bairro' }} />
          <Stack.Screen name="ganhar" options={{ title: 'Convida e ganha' }} />
          <Stack.Screen name="pacotes" options={{ title: 'Pacote do mês' }} />
          <Stack.Screen name="ajuda" options={{ title: 'Ajuda' }} />
          <Stack.Screen name="contactos" options={{ title: 'Contactos' }} />
          <Stack.Screen name="receitas" options={{ title: 'Cozinha de casa' }} />
          <Stack.Screen name="receita/[id]" options={{ title: 'Receita' }} />
          <Stack.Screen name="encomenda/nova" options={{ title: 'Boda Bué' }} />
          <Stack.Screen name="encomendas" options={{ title: 'Boda Bué · as minhas encomendas' }} />
          <Stack.Screen name="apagar-conta" options={{ title: 'Apagar a conta' }} />
          <Stack.Screen name="conta/cadeado" options={{ title: 'Cadeado da app' }} />
          <Stack.Screen name="recuperar-conta" options={{ title: 'Recuperar a conta' }} />
          <Stack.Screen name="politica-privacidade" options={{ title: 'Política de privacidade' }} />
          <Stack.Screen name="enderecos/novo" options={{ title: 'Novo endereço' }} />
        </Stack>
        <StatusBar style="dark" />
        <EcraCadeado />
      </CarrinhoProvider>
      </CadeadoProvider>
    </SessaoProvider>
  );
}
