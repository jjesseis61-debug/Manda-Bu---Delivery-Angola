import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  criarFeira,
  feiraAdicionarItem,
  feiraFechar,
  feiraResumo,
  feiraVender,
  lerCardapio,
  lerCozinhas,
  listarFeiras,
  listarPessoal,
} from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Cozinha, Feira, FeiraItem, FeiraResumo, PessoalItem, PratoCardapio } from '@/lib/tipos';

type Metodo = 'dinheiro' | 'transferencia';

/** Feira (consignação): o feirante leva pratos de preço fixo, vende no local e acerta no regresso. */
export default function Feiras() {
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [cozinhaId, setCozinhaId] = useState<string | null>(null);
  const [vendedores, setVendedores] = useState<PessoalItem[]>([]);
  const [cardapio, setCardapio] = useState<PratoCardapio[]>([]);
  const [feiras, setFeiras] = useState<Feira[] | null>(null);
  const [aberta, setAberta] = useState<FeiraResumo | null>(null);

  const [nova, setNova] = useState<{ vendedor: string; nome: string } | null>(null);
  const [novoItem, setNovoItem] = useState<{ cardapio: string; qtd: string } | null>(null);
  const [venda, setVenda] = useState<{ item: FeiraItem; qtd: string; metodo: Metodo; referencia: string } | null>(null);
  const [acerto, setAcerto] = useState<Record<string, { devolvida: string; perda: string }> | null>(null);

  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [aGuardar, setAGuardar] = useState(false);

  const carregarFeiras = useCallback((coz: string) => {
    listarFeiras(coz)
      .then(setFeiras)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);

  useFocusEffect(
    useCallback(() => {
      Promise.all([lerCozinhas(), listarPessoal()])
        .then(([cs, ps]) => {
          setCozinhas(cs);
          setVendedores(ps.filter((p) => p.activo));
          const coz = cozinhaId ?? cs[0]?.id ?? null;
          setCozinhaId(coz);
          if (coz) carregarFeiras(coz);
        })
        .catch((e) => setErro(mensagemErro(e)));
    }, [cozinhaId, carregarFeiras]),
  );

  function escolherCozinha(id: string) {
    setCozinhaId(id);
    setAberta(null);
    setFeiras(null);
    carregarFeiras(id);
  }

  async function abrir(id: string) {
    setErro(null);
    try {
      const r = await feiraResumo(id);
      setAberta(r);
      setNovoItem(null);
      setVenda(null);
      setAcerto(null);
      if (cozinhaId) lerCardapio(cozinhaId).then(setCardapio).catch(() => setCardapio([]));
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  async function acao(fn: () => Promise<void>, ok: string) {
    setErro(null);
    setSucesso(null);
    setAGuardar(true);
    try {
      await fn();
      setSucesso(ok);
      if (aberta) await abrir(aberta.id);
      if (cozinhaId) carregarFeiras(cozinhaId);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  const pratos = cardapio.filter((p) => p.disponivel !== false);

  return (
    <Guarda permissoes={['feira.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}

        {cozinhas.length > 1 && !aberta && (
          <Escolha
            opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome }))}
            valor={cozinhaId ?? ''}
            aoMudar={escolherCozinha}
          />
        )}

        {aberta ? (
          <>
            <Botao titulo="← Voltar às feiras" variante="texto" aoCarregar={() => setAberta(null)} />
            <Subtitulo>{aberta.nome}</Subtitulo>
            <Cartao>
              <Paragrafo suave>{aberta.estado === 'aberta' ? 'Aberta' : 'Fechada'}</Paragrafo>
              <Text style={{ color: cores.texto }}>
                Esperado {formatarKz(aberta.esperado)} · Recebido {formatarKz(aberta.recebido)}
              </Text>
              <Text style={{ color: cores.textoSuave }}>
                Dinheiro {formatarKz(aberta.recebido_dinheiro)} · Transferência {formatarKz(aberta.recebido_transferencia)}
              </Text>
              {aberta.diferenca !== 0 && (
                <Text style={{ color: cores.aviso, fontWeight: '700' }}>
                  Diferença {formatarKz(aberta.diferenca)}
                </Text>
              )}
            </Cartao>

            {aberta.itens.map((it) => (
              <Cartao key={it.item_id}>
                <Text style={{ fontWeight: '700', color: cores.texto }}>
                  {it.nome} · {formatarKz(it.preco_unit)}
                </Text>
                <Text style={{ color: cores.textoSuave }}>
                  Levou {it.levada} · vendeu {it.vendida} · restam {it.restante}
                  {it.devolvida > 0 ? ` · devolveu ${it.devolvida}` : ''}
                  {it.perda > 0 ? ` · perda ${it.perda}` : ''}
                </Text>
                {aberta.estado === 'aberta' && it.restante > 0 && (
                  <Botao
                    titulo="Registar venda"
                    variante="secundario"
                    aoCarregar={() => setVenda({ item: it, qtd: '1', metodo: 'dinheiro', referencia: '' })}
                  />
                )}
              </Cartao>
            ))}

            {venda && (
              <Cartao>
                <Subtitulo>Vender: {venda.item.nome}</Subtitulo>
                <Campo
                  rotulo={`Quantidade (restam ${venda.item.restante})`}
                  value={venda.qtd}
                  onChangeText={(t) => setVenda({ ...venda, qtd: t.replace(/\D/g, '') })}
                  keyboardType="numeric"
                />
                <Escolha
                  opcoes={[
                    { valor: 'dinheiro', rotulo: 'Dinheiro' },
                    { valor: 'transferencia', rotulo: 'Transferência' },
                  ]}
                  valor={venda.metodo}
                  aoMudar={(v) => setVenda({ ...venda, metodo: v as Metodo })}
                />
                {venda.metodo === 'transferencia' && (
                  <Campo
                    rotulo="Referência da transferência"
                    value={venda.referencia}
                    onChangeText={(t) => setVenda({ ...venda, referencia: t })}
                  />
                )}
                <Botao
                  titulo="Confirmar venda"
                  aCarregar={aGuardar}
                  desactivado={!(Number(venda.qtd) > 0)}
                  aoCarregar={() =>
                    acao(
                      () =>
                        feiraVender(
                          venda.item.item_id,
                          Math.round(Number(venda.qtd)),
                          venda.metodo,
                          venda.metodo === 'transferencia' ? venda.referencia.trim() : null,
                        ).then(() => undefined),
                      'Venda registada.',
                    ).then(() => setVenda(null))
                  }
                />
                <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setVenda(null)} />
              </Cartao>
            )}

            {aberta.estado === 'aberta' && (
              <>
                {novoItem ? (
                  <Cartao>
                    <Subtitulo>Carregar prato</Subtitulo>
                    <Escolha
                      opcoes={pratos.map((p) => ({ valor: p.id, rotulo: `${p.nome} · ${formatarKz(p.preco)}` }))}
                      valor={novoItem.cardapio}
                      aoMudar={(v) => setNovoItem({ ...novoItem, cardapio: v })}
                    />
                    <Campo
                      rotulo="Quantidade a levar"
                      value={novoItem.qtd}
                      onChangeText={(t) => setNovoItem({ ...novoItem, qtd: t.replace(/\D/g, '') })}
                      keyboardType="numeric"
                    />
                    <Botao
                      titulo="Adicionar"
                      aCarregar={aGuardar}
                      desactivado={!novoItem.cardapio || !(Number(novoItem.qtd) > 0)}
                      aoCarregar={() =>
                        acao(
                          () => feiraAdicionarItem(aberta.id, novoItem.cardapio, Math.round(Number(novoItem.qtd))).then(() => undefined),
                          'Prato carregado.',
                        ).then(() => setNovoItem(null))
                      }
                    />
                    <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setNovoItem(null)} />
                  </Cartao>
                ) : (
                  <Botao
                    titulo="Carregar prato"
                    variante="secundario"
                    aoCarregar={() => setNovoItem({ cardapio: pratos[0]?.id ?? '', qtd: '' })}
                  />
                )}

                {acerto ? (
                  <Cartao>
                    <Subtitulo>Acerto e fecho</Subtitulo>
                    <Paragrafo suave>Para cada prato: quantos voltaram e quantos se perderam.</Paragrafo>
                    {aberta.itens.map((it) => (
                      <View key={it.item_id} style={{ gap: 4 }}>
                        <Text style={{ fontWeight: '600', color: cores.texto }}>
                          {it.nome} (vendeu {it.vendida} de {it.levada})
                        </Text>
                        <View style={{ flexDirection: 'row', gap: espaco.s }}>
                          <View style={{ flex: 1 }}>
                            <Campo
                              rotulo="Devolvidos"
                              value={acerto[it.item_id]?.devolvida ?? ''}
                              onChangeText={(t) =>
                                setAcerto({ ...acerto, [it.item_id]: { devolvida: t.replace(/\D/g, ''), perda: acerto[it.item_id]?.perda ?? '' } })
                              }
                              keyboardType="numeric"
                            />
                          </View>
                          <View style={{ flex: 1 }}>
                            <Campo
                              rotulo="Perdas"
                              value={acerto[it.item_id]?.perda ?? ''}
                              onChangeText={(t) =>
                                setAcerto({ ...acerto, [it.item_id]: { devolvida: acerto[it.item_id]?.devolvida ?? '', perda: t.replace(/\D/g, '') } })
                              }
                              keyboardType="numeric"
                            />
                          </View>
                        </View>
                      </View>
                    ))}
                    <Botao
                      titulo="Fechar feira"
                      aCarregar={aGuardar}
                      aoCarregar={() =>
                        acao(
                          () =>
                            feiraFechar(
                              aberta.id,
                              aberta.itens.map((it) => ({
                                item_id: it.item_id,
                                devolvida: Math.round(Number(acerto[it.item_id]?.devolvida) || 0),
                                perda: Math.round(Number(acerto[it.item_id]?.perda) || 0),
                              })),
                            ),
                          'Feira fechada.',
                        ).then(() => setAcerto(null))
                      }
                    />
                    <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setAcerto(null)} />
                  </Cartao>
                ) : (
                  <Botao
                    titulo="Acerto e fechar"
                    aoCarregar={() =>
                      setAcerto(Object.fromEntries(aberta.itens.map((it) => [it.item_id, { devolvida: '', perda: '' }])))
                    }
                  />
                )}
              </>
            )}
          </>
        ) : (
          <>
            {nova ? (
              <Cartao>
                <Subtitulo>Nova feira</Subtitulo>
                <Campo rotulo="Nome/local da feira" value={nova.nome} onChangeText={(t) => setNova({ ...nova, nome: t })} />
                <Escolha
                  opcoes={vendedores.map((v) => ({ valor: v.id, rotulo: v.nome }))}
                  valor={nova.vendedor}
                  aoMudar={(v) => setNova({ ...nova, vendedor: v })}
                />
                <Botao
                  titulo="Criar feira"
                  aCarregar={aGuardar}
                  desactivado={nova.nome.trim().length === 0 || !nova.vendedor}
                  aoCarregar={() =>
                    acao(() => criarFeira(cozinhaId ?? '', nova.vendedor, nova.nome.trim()).then(() => undefined), 'Feira criada.').then(() =>
                      setNova(null),
                    )
                  }
                />
                <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setNova(null)} />
              </Cartao>
            ) : (
              <Botao
                titulo="Nova feira"
                desactivado={!cozinhaId || vendedores.length === 0}
                aoCarregar={() => setNova({ vendedor: vendedores[0]?.id ?? '', nome: '' })}
              />
            )}

            {!feiras && !erro && <ACarregar />}
            {feiras?.map((f) => (
              <Cartao key={f.id} estilo={f.estado === 'fechada' ? { opacity: 0.7 } : undefined}>
                <Text style={{ fontWeight: '700', color: cores.texto }}>{f.nome}</Text>
                <Text style={{ color: cores.textoSuave }}>
                  {f.vendedor ?? 'Sem feirante'} · {f.estado === 'aberta' ? 'Aberta' : 'Fechada'} · vendido {formatarKz(f.esperado)}
                </Text>
                <Botao titulo="Abrir" variante="texto" aoCarregar={() => abrir(f.id)} />
              </Cartao>
            ))}
            {feiras && feiras.length === 0 && <Paragrafo suave>Ainda não há feiras nesta cozinha.</Paragrafo>}
            <Paragrafo suave>
              Os pratos de feira têm preço fixo e não aparecem aos clientes online. Com rede, regista-se cada venda na
              hora; sem rede, lançam-se os totais no acerto do regresso.
            </Paragrafo>
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
