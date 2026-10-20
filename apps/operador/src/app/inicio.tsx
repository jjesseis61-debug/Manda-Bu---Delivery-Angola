import { Redirect, useFocusEffect, useRouter, type Href } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { ACarregar, Botao, Campo, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { contarNotificacoesNovas } from '@/lib/api';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { Funcionario, Permissao } from '@/lib/tipos';

/** Minúsculas e sem acentos, para a pesquisa encontrar com ou sem acentos */
const normalizar = (s: string): string => {
  try {
    return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  } catch {
    return s.toLowerCase();
  }
};

const ecras: {
  rota: Href;
  titulo: string;
  descricao: string;
  permissoes: Permissao[];
  permitir?: (f: Funcionario) => boolean;
}[] = [
  { rota: '/entregas', titulo: 'Pedidos e entregas', descricao: 'Fila de pedidos, saída e entrega (E1)', permissoes: ['entregas.registar', 'pedidos.gerir'] },
  { rota: '/turno', titulo: 'Gerente de turno', descricao: 'Sugestões do agente para o turno (aceitar ou recusar)', permissoes: ['pedidos.gerir'] },
  { rota: '/estafetas', titulo: 'Estafetas e despacho', descricao: 'Mapa dos estafetas ao vivo e sugestão de quem leva cada pedido', permissoes: ['pedidos.gerir'] },
  { rota: '/compras', titulo: 'Stock e compras', descricao: 'Plano de compras do agente e alertas do stock', permissoes: ['stock.gerir'] },
  { rota: '/atendimento', titulo: 'Atendimento', descricao: 'Conversas dos clientes que o assistente passou para uma pessoa', permissoes: ['atendimento.responder'] },
  { rota: '/caixa', titulo: 'Caixa', descricao: 'Abrir, sangrias e fecho com a contagem do dinheiro', permissoes: ['vendas.registar'] },
  { rota: '/analista', titulo: 'Analista', descricao: 'Pergunta sobre o negócio e lê o relatório do mês', permissoes: ['analista.usar'] },
  { rota: '/reclamacoes', titulo: 'Reclamações', descricao: 'Análise automática, resposta ao cliente e resumo do mês', permissoes: ['pedidos.gerir', 'clientes.gerir'] },
  { rota: '/empresas', titulo: 'Empresas (B2B)', descricao: 'Contas de empresa: almoços dos funcionários e fatura mensal', permissoes: ['clientes.gerir'] },
  { rota: '/feiras', titulo: 'Feiras', descricao: 'Vendas por consignação em feiras (preço fixo, fora da app)', permissoes: ['feira.gerir'] },
  { rota: '/avisos', titulo: 'Avisos', descricao: 'Enviar notificações a clientes e à equipa (por zona, cozinha, função)', permissoes: ['avisos.enviar'] },
  { rota: '/reconquista', titulo: 'Reconquista', descricao: 'Clientes que pararam de comprar: lista, telefones e campanha de regresso', permissoes: ['clientes.reconquista'] },
  { rota: '/estimulos', titulo: 'Estímulos do mês', descricao: 'Desempenho, metas e bónus da equipa e dos melhores clientes', permissoes: ['equipa.gerir'] },
  { rota: '/conferencia', titulo: 'Conferência', descricao: 'Fecho do dia e do mês, extratos e comprovativos', permissoes: ['financas.conferir'] },
  { rota: '/grupos', titulo: 'Grupos do dia', descricao: 'Pedidos de grupo juntos para preparar e expedir (O10)', permissoes: ['pedidos.gerir', 'entregas.registar'] },
  { rota: '/painel', titulo: 'Painel do programa', descricao: 'Custo, vendas por indicação, retenção (O1)', permissoes: ['indicacoes.ver'] },
  { rota: '/verificacao', titulo: 'Verificação', descricao: 'Ganhos em verificação (O2)', permissoes: ['indicacoes.verificar'] },
  { rota: '/vigilancia', titulo: 'Vigilância do Convida', descricao: 'Redes de contas e abusos, investigados pelo agente', permissoes: ['indicacoes.verificar'] },
  { rota: '/levantamentos', titulo: 'Levantamentos', descricao: 'Aprovar e pagar (O3)', permissoes: ['indicacoes.aprovar_pagamentos'] },
  { rota: '/pacotes', titulo: 'Pacotes do mês', descricao: 'Confirmar pagamentos, reembolsos e catálogo (I12)', permissoes: ['pacotes.gerir'] },
  { rota: '/embaixadores', titulo: 'Embaixadores', descricao: 'Elegíveis e actuais (O4)', permissoes: ['plataforma.parametros'] },
  { rota: '/zonas', titulo: 'Zonas de entrega', descricao: 'Bairros onde se entrega e a taxa de cada um', permissoes: ['plataforma.parametros'] },
  { rota: '/parametros', titulo: 'Parâmetros e interruptores', descricao: 'Valores do programa e funcionalidades (O5)', permissoes: ['plataforma.parametros'] },
  { rota: { pathname: '/cozinhas', params: { foco: 'cardapio' } }, titulo: 'Cardápio', descricao: 'Pratos, doses e opções de cada cozinha (O6)', permissoes: ['cozinhas.gerir', 'cardapio.gerir'] },
  { rota: '/cozinhas', titulo: 'Cozinhas', descricao: 'Perfil, consentimento, contactos e localização (O6)', permissoes: ['cozinhas.gerir', 'cozinha.perfil'] },
  { rota: '/pessoal', titulo: 'Pessoal', descricao: 'Cadastrar estafetas e funcionários, telefone de login e permissões', permissoes: [], permitir: (f) => f.administrador_principal },
  { rota: '/relatorios', titulo: 'Relatórios de cozinha', descricao: 'Por período, com exportação (O9)', permissoes: ['relatorios.exportar'] },
  { rota: '/moderacao', titulo: 'Moderação', descricao: 'Comentários das avaliações e palavras filtradas (O7)', permissoes: ['avaliacoes.moderar'] },
  {
    rota: '/equipa',
    titulo: 'Equipa',
    descricao: 'Métricas da semana por turno e reconhecimentos (O8)',
    permissoes: ['equipa.reconhecer'],
    permitir: (f) => f.cozinhas_equipa.length > 0,
  },
];

/** Menu: só os ecrãs que as permissões do organograma deixam usar */
export default function Inicio() {
  const router = useRouter();
  const { carregado, sessao, funcionario, pode, sair } = useSessao();
  const [procura, setProcura] = useState('');
  const [novas, setNovas] = useState(0);
  // Enquanto o ecrã está aberto, reconta as notificações a cada 15 s (quase instantâneo,
  // sem gastar bateria a mais) — senão o badge só mudava ao sair e voltar.
  useFocusEffect(
    useCallback(() => {
      let activo = true;
      const ler = () => contarNotificacoesNovas().then((n) => activo && setNovas(n)).catch(() => undefined);
      void ler();
      const t = setInterval(ler, 15000);
      return () => {
        activo = false;
        clearInterval(t);
      };
    }, []),
  );
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!funcionario) return <Redirect href="/sem-acesso" />;

  const visiveis = ecras.filter((e) => e.permissoes.some(pode) || e.permitir?.(funcionario));
  // Só vale a pena pesquisar quando há muitos atalhos (ex.: administrador)
  const mostrarPesquisa = visiveis.length > 6;
  const termo = normalizar(procura.trim());
  const filtrados = termo
    ? visiveis.filter((e) => normalizar(`${e.titulo} ${e.descricao}`).includes(termo))
    : visiveis;
  return (
    <Ecra>
      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
        <Paragrafo suave>
          {funcionario.nome}
          {funcionario.cargo ? ` · ${funcionario.cargo}` : ''}
        </Paragrafo>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Notificações${novas > 0 ? `, ${novas} novas` : ''}`}
          onPress={() => {
            setNovas(0);
            router.push('/notificacoes');
          }}
          style={{ padding: 6 }}>
          <Text style={{ fontSize: 22 }}>🔔</Text>
          {novas > 0 && (
            <View
              style={{
                position: 'absolute',
                top: 0,
                right: 0,
                minWidth: 18,
                height: 18,
                paddingHorizontal: 4,
                borderRadius: 9,
                backgroundColor: cores.marca,
                alignItems: 'center',
                justifyContent: 'center',
              }}>
              <Text style={{ color: '#fff', fontSize: 11, fontWeight: '800' }}>{novas > 99 ? '99+' : novas}</Text>
            </View>
          )}
        </Pressable>
      </View>
      {pode('entregas.registar') && (
        <Pressable onPress={() => router.push('/entregas?meu=1')}>
          <Cartao estilo={{ backgroundColor: cores.marca }}>
            <Text style={{ fontSize: 18, fontWeight: '800', color: '#fff' }}>As minhas entregas de hoje</Text>
            <Text style={{ color: '#fff' }}>Ver só o que tens para entregar e marcar como entregue</Text>
          </Cartao>
        </Pressable>
      )}
      {mostrarPesquisa && (
        <Campo
          rotulo="Procurar funcionalidade"
          value={procura}
          onChangeText={setProcura}
          placeholder="Ex.: caixa, feira, estafetas"
        />
      )}
      {visiveis.length === 0 && (
        <Paragrafo>Ainda não tens permissões nesta app. Fala com o administrador.</Paragrafo>
      )}
      {visiveis.length > 0 && filtrados.length === 0 && <Paragrafo suave>Nada encontrado para “{procura.trim()}”.</Paragrafo>}
      {filtrados.map((e) => (
        <Pressable key={e.titulo} onPress={() => router.push(e.rota)}>
          <Cartao>
            <Text style={{ fontSize: 17, fontWeight: '700', color: cores.texto }}>{e.titulo}</Text>
            <Text style={{ color: cores.textoSuave }}>{e.descricao}</Text>
          </Cartao>
        </Pressable>
      ))}
      <Botao
        titulo="Sair"
        variante="texto"
        aoCarregar={async () => {
          await sair();
          router.replace('/entrar');
        }}
      />
    </Ecra>
  );
}
