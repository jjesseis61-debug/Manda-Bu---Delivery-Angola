import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo } from '@/components/ui';
import {
  adesoesPacote,
  caixasAbertas,
  confirmarPagamentoPacote,
  guardarPacote,
  lerCatalogoPacotes,
  reembolsarPacote,
} from '@/lib/api';
import { formatarData, formatarKz, mensagemErro, nomeMetodo } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { AdesaoOperador, Caixa, PacoteCatalogo } from '@/lib/tipos';

type Separador = 'pendente' | 'activa' | 'catalogo';

const nomeMetodoPacote: Record<string, string> = { ...nomeMetodo, loja: 'Na loja' };

const novoPacote: Omit<PacoteCatalogo, 'id'> = {
  nome: 'Almoço do Mês',
  descricao: null,
  refeicoes: 20,
  refeicoes_oferta: 2,
  valor_refeicao: 2500,
  preco: 50000,
  validade_dias: 30,
  pausa_max_dias: 5,
  entrega_gratis: true,
  activo: true,
  ordem: 0,
};

const camposNumero: { chave: keyof PacoteCatalogo; rotulo: string }[] = [
  { chave: 'refeicoes', rotulo: 'Refeições pagas' },
  { chave: 'refeicoes_oferta', rotulo: 'Refeições de oferta' },
  { chave: 'valor_refeicao', rotulo: 'Valor máximo por refeição (Kz)' },
  { chave: 'preco', rotulo: 'Preço do pacote (Kz)' },
  { chave: 'validade_dias', rotulo: 'Validade (dias)' },
  { chave: 'pausa_max_dias', rotulo: 'Pausa máxima (dias)' },
  { chave: 'ordem', rotulo: 'Ordem no catálogo' },
];

/** I12. Pacotes pré-pagos: confirmar pagamentos, reembolsar e gerir o catálogo */
export default function Pacotes() {
  const [separador, setSeparador] = useState<Separador>('pendente');
  const [adesoes, setAdesoes] = useState<AdesaoOperador[] | null>(null);
  const [catalogo, setCatalogo] = useState<PacoteCatalogo[] | null>(null);
  const [caixas, setCaixas] = useState<Caixa[]>([]);
  const [caixaId, setCaixaId] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [texto, setTexto] = useState('');
  const [edicao, setEdicao] = useState<(Omit<PacoteCatalogo, 'id'> & { id?: string }) | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    setErro(null);
    if (separador === 'catalogo') {
      setCatalogo(null);
      lerCatalogoPacotes().then(setCatalogo).catch((e) => setErro(mensagemErro(e)));
    } else {
      setAdesoes(null);
      adesoesPacote(separador).then(setAdesoes).catch((e) => setErro(mensagemErro(e)));
      if (separador === 'pendente') {
        caixasAbertas()
          .then((c) => {
            setCaixas(c);
            setCaixaId((actual) => actual ?? c[0]?.id ?? null);
          })
          .catch(() => setCaixas([]));
      }
    }
  }, [separador]);
  useFocusEffect(carregar);

  async function accao(f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(true);
    try {
      await f();
      setAberto(null);
      setTexto('');
      setEdicao(null);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  function cartaoAdesao(a: AdesaoOperador) {
    const loja = a.metodo === 'loja';
    return (
      <Cartao key={a.adesao_id}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{formatarKz(a.preco)}</Text>
          <Text style={{ fontWeight: '700' }}>{nomeMetodoPacote[a.metodo] ?? a.metodo}</Text>
        </View>
        <Text>
          {a.cliente_nome} · {a.pacote}
        </Text>
        {a.cliente_telefone && (
          <Text style={{ color: cores.marca }} onPress={() => Linking.openURL(`tel:+244${a.cliente_telefone}`)}>
            Ligar {a.cliente_telefone}
          </Text>
        )}
        {a.estado === 'pendente' && <Text style={{ color: cores.textoSuave }}>Pedido em {formatarData(a.criado_em, true)}</Text>}
        {a.estado === 'activa' && (
          <Text style={{ color: cores.textoSuave }}>
            {a.refeicoes_usadas} de {a.refeicoes_total} refeições usadas · {formatarData(a.inicio)} a {formatarData(a.fim)}
          </Text>
        )}
        {a.referencia && <Text>Referência: {a.referencia}</Text>}

        {aberto === a.adesao_id ? (
          <>
            {a.estado === 'pendente' && loja ? (
              caixas.length === 0 ? (
                <Aviso>Abre o caixa antes de receber o pagamento na loja.</Aviso>
              ) : (
                <Escolha
                  opcoes={caixas.map((c) => ({ valor: c.id, rotulo: `${c.posto} · ${formatarData(c.data)}` }))}
                  valor={caixaId ?? ''}
                  aoMudar={setCaixaId}
                />
              )
            ) : (
              <Campo
                rotulo={a.estado === 'pendente' ? 'Referência do pagamento (obrigatória)' : 'Referência da devolução'}
                value={texto}
                onChangeText={setTexto}
              />
            )}
            {a.estado === 'activa' && (
              <Paragrafo>Devolver {formatarKz(a.reembolso_previsto)} (refeições pagas que não foram usadas).</Paragrafo>
            )}
            <Botao
              titulo={a.estado === 'pendente' ? 'Confirmar pagamento' : 'Reembolsar'}
              desactivado={a.estado === 'pendente' ? (loja ? !caixaId : !texto.trim()) : false}
              aCarregar={ocupado}
              aoCarregar={() =>
                accao(() =>
                  a.estado === 'pendente'
                    ? confirmarPagamentoPacote(a.adesao_id, loja ? null : texto.trim(), loja ? caixaId : null)
                    : reembolsarPacote(a.adesao_id, texto.trim()),
                )
              }
            />
            <Botao titulo="Voltar" variante="texto" aoCarregar={() => setAberto(null)} />
          </>
        ) : (
          <Botao
            titulo={a.estado === 'pendente' ? 'Confirmar pagamento' : 'Reembolsar'}
            variante={a.estado === 'pendente' ? 'principal' : 'secundario'}
            aoCarregar={() => {
              setTexto('');
              setAberto(a.adesao_id);
            }}
          />
        )}
      </Cartao>
    );
  }

  return (
    <Guarda permissoes={['pacotes.gerir']}>
      <Ecra>
        <Escolha
          opcoes={[
            { valor: 'pendente', rotulo: 'Por confirmar' },
            { valor: 'activa', rotulo: 'Activos' },
            { valor: 'catalogo', rotulo: 'Catálogo' },
          ]}
          valor={separador}
          aoMudar={(s) => {
            setAberto(null);
            setEdicao(null);
            setSeparador(s);
          }}
        />
        {erro && <Aviso tipo="erro">{erro}</Aviso>}

        {separador !== 'catalogo' && (
          <>
            {!adesoes && !erro && <ACarregar />}
            {adesoes?.length === 0 && <Paragrafo suave>Nada nesta lista.</Paragrafo>}
            {adesoes?.map(cartaoAdesao)}
          </>
        )}

        {separador === 'catalogo' && !edicao && (
          <>
            {!catalogo && !erro && <ACarregar />}
            {catalogo?.map((p) => (
              <Cartao key={p.id}>
                <Text style={{ fontWeight: '700', fontSize: 16 }}>
                  {p.nome}
                  {p.activo ? '' : ' (inactivo)'}
                </Text>
                <Text style={{ color: cores.textoSuave }}>
                  {p.refeicoes} + {p.refeicoes_oferta} refeições · {formatarKz(p.preco)} · {p.validade_dias} dias
                </Text>
                <Botao titulo="Editar" variante="secundario" aoCarregar={() => setEdicao(p)} />
              </Cartao>
            ))}
            <Botao titulo="Novo pacote" aoCarregar={() => setEdicao(novoPacote)} />
          </>
        )}

        {separador === 'catalogo' && edicao && (
          <Cartao>
            <Campo rotulo="Nome" value={edicao.nome} onChangeText={(v) => setEdicao({ ...edicao, nome: v })} />
            <Campo
              rotulo="Descrição (opcional)"
              value={edicao.descricao ?? ''}
              onChangeText={(v) => setEdicao({ ...edicao, descricao: v || null })}
            />
            {camposNumero.map((c) => (
              <Campo
                key={c.chave}
                rotulo={c.rotulo}
                keyboardType="number-pad"
                value={String(edicao[c.chave] ?? '')}
                onChangeText={(v) => setEdicao({ ...edicao, [c.chave]: Number(v.replace(/\D/g, '')) || 0 })}
              />
            ))}
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
              <Text style={{ flex: 1 }}>Entrega grátis</Text>
              <Switch value={edicao.entrega_gratis} onValueChange={(v) => setEdicao({ ...edicao, entrega_gratis: v })} />
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
              <Text style={{ flex: 1 }}>Visível para os clientes</Text>
              <Switch value={edicao.activo} onValueChange={(v) => setEdicao({ ...edicao, activo: v })} />
            </View>
            <Botao
              titulo="Guardar"
              desactivado={!edicao.nome.trim() || edicao.refeicoes < 1 || edicao.preco < 1}
              aCarregar={ocupado}
              aoCarregar={() => accao(() => guardarPacote({ ...edicao, nome: edicao.nome.trim() }))}
            />
            <Botao titulo="Voltar" variante="texto" aoCarregar={() => setEdicao(null)} />
          </Cartao>
        )}
      </Ecra>
    </Guarda>
  );
}
