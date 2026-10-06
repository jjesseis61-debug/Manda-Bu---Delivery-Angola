import { Redirect, useRouter, type Href } from 'expo-router';
import { Pressable, Text } from 'react-native';

import { ACarregar, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Funcionario, Permissao } from '@/lib/tipos';

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
  { rota: '/cozinhas', titulo: 'Cozinhas e cardápio', descricao: 'Perfil, consentimento e pratos (O6)', permissoes: ['cozinhas.gerir'] },
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
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!funcionario) return <Redirect href="/sem-acesso" />;

  const visiveis = ecras.filter((e) => e.permissoes.some(pode) || e.permitir?.(funcionario));
  return (
    <Ecra>
      <Paragrafo suave>
        {funcionario.nome}
        {funcionario.cargo ? ` · ${funcionario.cargo}` : ''}
      </Paragrafo>
      {visiveis.length === 0 && (
        <Paragrafo>Ainda não tens permissões nesta app. Fala com o administrador.</Paragrafo>
      )}
      {visiveis.map((e) => (
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
