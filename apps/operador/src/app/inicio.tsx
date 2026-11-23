import { Redirect, useFocusEffect, useRouter, type Href } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { contarNotificacoesNovas, sairDeTodosOsDispositivos } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { guardarFavoritos, guardarGruposAbertos, lerFavoritos, lerGruposAbertos } from '@/lib/preferencias';
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

export const GRUPOS = [
  { id: 'operacao', nome: 'Operação do dia' },
  { id: 'logistica', nome: 'Logística' },
  { id: 'cozinhas', nome: 'Cozinhas e cardápio' },
  { id: 'financas', nome: 'Finanças' },
  { id: 'clientes', nome: 'Clientes e vendas' },
  { id: 'convida', nome: 'Programa Convida' },
  { id: 'equipa', nome: 'Recursos humanos' },
  { id: 'controlo', nome: 'Relatórios e controlo' },
] as const;
export type GrupoId = (typeof GRUPOS)[number]['id'];

export type EntradaMenu = {
  rota: Href;
  /** Um ecrã pode estar em mais de um grupo (ex.: serviço de entregas: Logística e Finanças) */
  grupos: GrupoId[];
  titulo: string;
  descricao: string;
  permissoes: Permissao[];
  permitir?: (f: Funcionario) => boolean;
};

/** Até este número de atalhos o menu fica numa lista simples (estafeta, cozinheira) */
export const LIMITE_LISTA_SIMPLES = 6;

/** Grupos com as entradas visíveis, pela ordem do menu; os grupos vazios não aparecem */
export function agruparMenu(visiveis: EntradaMenu[]): { id: GrupoId; nome: string; entradas: EntradaMenu[] }[] {
  return GRUPOS.map((g) => ({ id: g.id, nome: g.nome, entradas: visiveis.filter((e) => e.grupos.includes(g.id)) })).filter(
    (g) => g.entradas.length > 0,
  );
}

export const ecras: EntradaMenu[] = [
  { rota: '/entregas', grupos: ['operacao'], titulo: 'Pedidos e entregas', descricao: 'Fila de pedidos, saída e entrega (E1)', permissoes: ['entregas.registar', 'pedidos.gerir'] },
  { rota: '/turno', grupos: ['operacao'], titulo: 'Gerente de turno', descricao: 'Sugestões do agente para o turno (aceitar ou recusar)', permissoes: ['pedidos.gerir'] },
  { rota: '/estafetas', grupos: ['logistica'], titulo: 'Estafetas e despacho', descricao: 'Mapa dos estafetas ao vivo e sugestão de quem leva cada pedido', permissoes: ['pedidos.gerir'] },
  { rota: '/compras', grupos: ['logistica'], titulo: 'Stock e compras', descricao: 'Plano de compras do agente e alertas do stock', permissoes: ['stock.gerir'] },
  { rota: '/atendimento', grupos: ['operacao'], titulo: 'Atendimento', descricao: 'Conversas dos clientes que o assistente passou para uma pessoa', permissoes: ['atendimento.responder'] },
  { rota: '/caixa', grupos: ['operacao'], titulo: 'Caixa', descricao: 'Abrir, sangrias e fecho com a contagem do dinheiro', permissoes: ['vendas.registar'] },
  { rota: '/analista', grupos: ['controlo'], titulo: 'Analista', descricao: 'Pergunta sobre o negócio e lê o relatório do mês', permissoes: ['analista.usar'] },
  { rota: '/teste-fotos', grupos: ['controlo'], titulo: 'Teste das fotografias', descricao: 'Fotografia grande ou média no Início do cliente: qual dá mais pedidos', permissoes: ['analista.usar'] },
  { rota: '/teste-balcao', grupos: ['controlo'], titulo: 'Teste do balcão de panelas', descricao: 'Servir o prato: lista ou balcão de panelas, qual dá mais pedidos (com grupo de controlo)', permissoes: ['analista.usar'] },
  { rota: '/teste-compromisso', grupos: ['controlo'], titulo: 'Teste do compromisso', descricao: 'Agendados: «Vais estar em … às …?» reduz as ausências? (com grupo de controlo)', permissoes: ['analista.usar'] },
  { rota: '/reclamacoes', grupos: ['operacao'], titulo: 'Reclamações', descricao: 'Análise automática, resposta ao cliente e resumo do mês', permissoes: ['pedidos.gerir', 'clientes.gerir'] },
  { rota: '/empresas', grupos: ['clientes'], titulo: 'Empresas (B2B)', descricao: 'Contas de empresa: almoços dos funcionários e fatura mensal', permissoes: ['clientes.gerir'] },
  { rota: '/feiras', grupos: ['cozinhas'], titulo: 'Feiras', descricao: 'Vendas por consignação em feiras (preço fixo, fora da app)', permissoes: ['feira.gerir'] },
  { rota: '/avisos', grupos: ['clientes'], titulo: 'Avisos', descricao: 'Enviar notificações a clientes e à equipa (por zona, cozinha, função)', permissoes: ['avisos.enviar'] },
  { rota: '/receitas', grupos: ['cozinhas'], titulo: 'Receitas', descricao: 'Cozinha de casa: receitas angolanas com botão de pedir (conteúdo para o cliente)', permissoes: ['receitas.gerir'] },
  { rota: '/reconquista', grupos: ['clientes'], titulo: 'Reconquista', descricao: 'Clientes que pararam de comprar: lista, telefones e campanha de regresso', permissoes: ['clientes.reconquista'] },
  { rota: '/utilizadores', grupos: ['equipa'], titulo: 'Utilizadores', descricao: 'Procurar clientes, equipa e contas de login por nome ou número; bloquear um número', permissoes: ['utilizadores.ver'] },
  { rota: '/otp-codigos', grupos: ['equipa'], titulo: 'Códigos de login', descricao: 'Entregar os códigos de OTP manual aos clientes (WhatsApp/SMS)', permissoes: ['otp.entregar'] },
  { rota: '/rh', grupos: ['equipa'], titulo: 'Fichas e contratos', descricao: 'Dados pessoais, documentos com validade, contratos e equipamento entregue', permissoes: ['rh.gerir'] },
  { rota: '/rh-folha', grupos: ['equipa', 'financas'], titulo: 'Folha de salários', descricao: 'Salários do mês com Segurança Social e IRT; fechar e pagar', permissoes: ['rh.salarios', 'financas.salarios'] },
  { rota: '/rh-parametros', grupos: ['equipa'], titulo: 'Tabela do IRT e Segurança Social', descricao: 'Taxas, isenções e escalões do IRT (editáveis quando a lei mudar)', permissoes: ['rh.salarios'] },
  { rota: '/estimulos', grupos: ['equipa'], titulo: 'Estímulos do mês', descricao: 'Desempenho, metas e bónus da equipa e dos melhores clientes', permissoes: ['equipa.gerir'] },
  { rota: '/acertos', grupos: ['financas'], titulo: 'Acertos com as cozinhas', descricao: 'Semana a semana: comissão e entregas a receber, Convida e pacotes a pagar', permissoes: ['financas.acertos', 'relatorios.exportar'] },
  { rota: '/pagamentos-antes', grupos: ['financas'], titulo: 'Pagamentos antes', descricao: 'Grupos em que cada um paga a sua parte: confirmar, rejeitar ou devolver', permissoes: ['financas.acertos'] },
  { rota: '/faturas', grupos: ['financas'], titulo: 'Faturas das vendas', descricao: 'Vendas entregues sem número de fatura (plataforma ou cozinha)', permissoes: ['financas.faturas', 'pedidos.gerir'] },
  { rota: '/compensacoes', grupos: ['financas'], titulo: 'Compensações', descricao: 'Pagar aos clientes o que se decidiu nas reclamações; a cargo de quem', permissoes: ['financas.compensacoes'] },
  { rota: '/contas-empresas', grupos: ['financas'], titulo: 'Contas das empresas', descricao: 'Fatura do mês de cada empresa (B2B), vencimento e pagamento', permissoes: ['financas.empresas'] },
  { rota: '/estafetas-pagamentos', grupos: ['financas'], titulo: 'Pagamento dos estafetas', descricao: 'Salário, valor por dia e por entrega; dias trabalhados e pagamento do mês', permissoes: ['financas.estafetas'] },
  { rota: '/servico-entregas', grupos: ['logistica', 'financas'], titulo: 'Serviço de entregas contratado', descricao: 'Valor por entrega e/ou mensal, zonas que serve e pagamento do mês', permissoes: ['financas.servico_entregas'] },
  { rota: '/resultados', grupos: ['financas'], titulo: 'Resultados do mês', descricao: 'Receitas, custos e resultado da plataforma', permissoes: ['financas.resultados'] },
  { rota: '/obrigacoes', grupos: ['financas'], titulo: 'Obrigações e tesouraria', descricao: 'O que a plataforma deve e tem a receber, num só sítio', permissoes: ['financas.obrigacoes'] },
  { rota: '/conferencia', grupos: ['financas'], titulo: 'Conferência', descricao: 'Fecho do dia e do mês, extratos e comprovativos', permissoes: ['financas.conferir'] },
  { rota: '/encomendas', grupos: ['operacao'], titulo: 'Encomendas', descricao: 'Receitas encomendadas com 24 h: escolher a cozinha, preço da cozinha, aprovar', permissoes: ['pedidos.gerir', 'cozinhas.gerir', 'vendas.registar'] },
  { rota: '/grupos', grupos: ['operacao'], titulo: 'Grupos do dia', descricao: 'Pedidos de grupo juntos para preparar e expedir (O10)', permissoes: ['pedidos.gerir', 'entregas.registar'] },
  { rota: '/condominios', grupos: ['cozinhas'], titulo: 'Condomínios', descricao: 'Cozinha só para moradores: área no mapa, lista com vagas, abrir/fechar', permissoes: ['cozinhas.gerir', 'pedidos.gerir'] },
  { rota: '/campanhas', grupos: ['clientes'], titulo: 'Campanhas', descricao: 'Promoções por condomínio, zona ou para todos, com resultados', permissoes: ['cozinhas.gerir', 'pedidos.gerir', 'cardapio.gerir'] },
  { rota: '/zonas-vendas', grupos: ['clientes'], titulo: 'O que se compra em cada zona', descricao: 'Pratos mais pedidos por zona, em todas as cozinhas, e o que está a crescer', permissoes: ['relatorios.exportar'] },
  { rota: '/painel', grupos: ['convida'], titulo: 'Painel do programa', descricao: 'Custo, vendas por indicação, retenção (O1)', permissoes: ['indicacoes.ver'] },
  { rota: '/verificacao', grupos: ['convida'], titulo: 'Verificação', descricao: 'Ganhos em verificação (O2)', permissoes: ['indicacoes.verificar'] },
  { rota: '/vigilancia', grupos: ['convida'], titulo: 'Vigilância do Convida', descricao: 'Redes de contas e abusos, investigados pelo agente', permissoes: ['indicacoes.verificar'] },
  { rota: '/saldos-expirados', grupos: ['convida'], titulo: 'Saldos expirados', descricao: 'Saldo do Convida que expirou (12 meses) e o que vai expirar', permissoes: ['indicacoes.verificar'] },
  { rota: '/levantamentos', grupos: ['financas'], titulo: 'Levantamentos', descricao: 'Aprovar e pagar (O3)', permissoes: ['indicacoes.aprovar_pagamentos'] },
  { rota: '/pacotes', grupos: ['clientes'], titulo: 'Pacotes do mês', descricao: 'Confirmar pagamentos, reembolsos e catálogo (I12)', permissoes: ['pacotes.gerir'] },
  { rota: '/embaixadores', grupos: ['convida'], titulo: 'Embaixadores', descricao: 'Elegíveis e actuais (O4)', permissoes: ['plataforma.parametros'] },
  { rota: '/zonas', grupos: ['logistica'], titulo: 'Zonas de entrega', descricao: 'Bairros onde se entrega e a taxa de cada um', permissoes: ['plataforma.parametros'] },
  { rota: '/parametros', grupos: ['controlo'], titulo: 'Parâmetros e interruptores', descricao: 'Valores do programa e funcionalidades (O5)', permissoes: ['plataforma.parametros'] },
  { rota: { pathname: '/cozinhas', params: { foco: 'cardapio' } }, grupos: ['cozinhas'], titulo: 'Cardápio', descricao: 'Pratos, doses e opções de cada cozinha (O6)', permissoes: ['cozinhas.gerir', 'cardapio.gerir'] },
  { rota: '/cozinhas', grupos: ['cozinhas'], titulo: 'Cozinhas', descricao: 'Perfil, consentimento, contactos e localização (O6)', permissoes: ['cozinhas.gerir', 'cozinha.perfil'] },
  { rota: '/pessoal', grupos: ['equipa'], titulo: 'Pessoal', descricao: 'Cadastrar estafetas e funcionários, telefone de login e permissões', permissoes: [], permitir: (f) => f.administrador_principal },
  { rota: '/relatorios', grupos: ['controlo'], titulo: 'Relatórios de cozinha', descricao: 'Por período, com exportação (O9)', permissoes: ['relatorios.exportar'] },
  { rota: '/moderacao', grupos: ['cozinhas'], titulo: 'Moderação', descricao: 'Comentários das avaliações e palavras filtradas (O7)', permissoes: ['avaliacoes.moderar'] },
  { rota: '/auditoria', grupos: ['controlo'], titulo: 'Auditoria', descricao: 'Registo de tudo o que aconteceu: logins, cardápio, caixa, configuração (quem, o quê e quando)', permissoes: ['auditoria.ver'] },
  {
    rota: '/equipa', grupos: ['equipa'],
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
  const [protegerConfirmar, setProtegerConfirmar] = useState(false);
  const [ocupado, setOcupado] = useState(false);
  const [erroSeguranca, setErroSeguranca] = useState<string | null>(null);
  const [favoritos, setFavoritos] = useState<string[]>([]);
  const [abertos, setAbertos] = useState<string[]>([]);
  const idFuncionario = funcionario?.funcionario_id;
  useEffect(() => {
    if (!idFuncionario) return;
    let activo = true;
    void lerFavoritos(idFuncionario).then((l) => activo && setFavoritos(l));
    void lerGruposAbertos().then((l) => activo && setAbertos(l));
    return () => {
      activo = false;
    };
  }, [idFuncionario]);
  // Enquanto o ecrã está aberto, reconta as notificações a cada 15 s (quase instantâneo,
  // sem gastar bateria a mais): senão o badge só mudava ao sair e voltar.
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
  // Só vale a pena pesquisar e agrupar quando há muitos atalhos (ex.: administrador)
  const comGrupos = visiveis.length > LIMITE_LISTA_SIMPLES;
  const termo = normalizar(procura.trim());
  const filtrados = termo
    ? visiveis.filter((e) => normalizar(`${e.titulo} ${e.descricao}`).includes(termo))
    : visiveis;
  const grupos = agruparMenu(visiveis);
  const meusFavoritos = visiveis.filter((e) => favoritos.includes(e.titulo));
  const nomeGrupos = (e: EntradaMenu) => GRUPOS.filter((g) => e.grupos.includes(g.id)).map((g) => g.nome).join(' · ');

  function alternarFavorito(titulo: string) {
    if (!idFuncionario) return;
    const l = favoritos.includes(titulo) ? favoritos.filter((t) => t !== titulo) : [...favoritos, titulo];
    setFavoritos(l);
    void guardarFavoritos(idFuncionario, l);
  }
  function alternarGrupo(id: string) {
    const l = abertos.includes(id) ? abertos.filter((g) => g !== id) : [...abertos, id];
    setAbertos(l);
    void guardarGruposAbertos(l);
  }
  const cartao = (e: EntradaMenu, grupo?: string, chave?: string) => {
    const fav = favoritos.includes(e.titulo);
    return (
      <Pressable key={chave ?? e.titulo} onPress={() => router.push(e.rota)}>
        <Cartao>
          <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: espaco.s }}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 17, fontWeight: '700', color: cores.texto }}>{e.titulo}</Text>
              {grupo && <Text style={{ color: cores.marca, fontSize: 12, fontWeight: '700' }}>{grupo}</Text>}
              <Text style={{ color: cores.textoSuave }}>{e.descricao}</Text>
            </View>
            {comGrupos && (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel={fav ? `Tirar ${e.titulo} dos favoritos` : `Marcar ${e.titulo} como favorito`}
                hitSlop={10}
                onPress={() => alternarFavorito(e.titulo)}>
                <Text style={{ fontSize: 22, color: fav ? cores.aviso : cores.textoSuave }}>{fav ? '★' : '☆'}</Text>
              </Pressable>
            )}
          </View>
        </Cartao>
      </Pressable>
    );
  };
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
      {comGrupos && (
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
      {termo ? (
        <>
          {filtrados.length === 0 && <Paragrafo suave>Nada encontrado para “{procura.trim()}”.</Paragrafo>}
          {filtrados.map((e) => cartao(e, comGrupos ? nomeGrupos(e) : undefined))}
        </>
      ) : !comGrupos ? (
        visiveis.map((e) => cartao(e))
      ) : (
        <>
          {meusFavoritos.length > 0 && (
            <>
              <Text style={{ fontSize: 16, fontWeight: '800', color: cores.texto }}>★ Favoritos</Text>
              {meusFavoritos.map((e) => cartao(e, undefined, `fav-${e.titulo}`))}
            </>
          )}
          {meusFavoritos.length === 0 && (
            <Paragrafo suave>Toca na ☆ de um ecrã para o pôr nos favoritos, aqui no topo.</Paragrafo>
          )}
          {grupos.map((g) => {
            const aberto = abertos.includes(g.id);
            return (
              <View key={g.id} style={{ gap: espaco.s }}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityState={{ expanded: aberto }}
                  accessibilityLabel={`${g.nome}, ${g.entradas.length} ${g.entradas.length === 1 ? 'ecrã' : 'ecrãs'}`}
                  onPress={() => alternarGrupo(g.id)}>
                  <Cartao estilo={{ backgroundColor: aberto ? cores.fundoSuave : undefined }}>
                    <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                      <Text style={{ fontSize: 17, fontWeight: '800', color: cores.texto }}>
                        {g.nome} ({g.entradas.length})
                      </Text>
                      <Text style={{ fontSize: 18, color: cores.textoSuave }}>{aberto ? '⌄' : '›'}</Text>
                    </View>
                  </Cartao>
                </Pressable>
                {aberto && (
                  <View style={{ gap: espaco.s, paddingLeft: espaco.m }}>
                    {g.entradas.map((e) => cartao(e, undefined, `${g.id}-${e.titulo}`))}
                  </View>
                )}
              </View>
            );
          })}
        </>
      )}
      {erroSeguranca && <Aviso tipo="erro">{erroSeguranca}</Aviso>}
      {protegerConfirmar ? (
        <>
          <Aviso>Sais em todos os dispositivos, incluindo este. Para voltar a entrar precisas do código SMS do teu número.</Aviso>
          <Botao
            titulo="Sim, sair em todos os dispositivos"
            aCarregar={ocupado}
            aoCarregar={async () => {
              setErroSeguranca(null);
              setOcupado(true);
              try {
                await sairDeTodosOsDispositivos();
                router.replace('/entrar');
              } catch (e) {
                setErroSeguranca(mensagemErro(e));
                setOcupado(false);
              }
            }}
          />
          <Botao titulo="Cancelar" variante="texto" desactivado={ocupado} aoCarregar={() => setProtegerConfirmar(false)} />
        </>
      ) : (
        <Botao
          titulo="Proteger a conta: sair em todos os dispositivos"
          variante="secundario"
          aoCarregar={() => setProtegerConfirmar(true)}
        />
      )}
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
