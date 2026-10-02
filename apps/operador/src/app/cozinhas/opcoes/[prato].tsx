import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { apagarGrupoOpcoes, apagarOpcao, guardarGrupoOpcoes, guardarOpcao, lerGruposOpcoes } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { GrupoOpcoesPrato } from '@/lib/tipos';

type GrupoEditado = { id?: string; nome: string; minimo: string; maximo: string; ordem: string };
type OpcaoEditada = { id?: string; grupo_id: string; nome: string; preco_extra: string; disponivel: boolean; ordem: string };

const numero = (t: string) => t.replace(/\D/g, '');

/** I9. Opções de um prato montável: grupos (Base, Acompanhamentos, Extras) com mínimo e máximo, e as opções com preço extra */
export default function OpcoesPrato() {
  const { prato, nome } = useLocalSearchParams<{ prato: string; nome?: string }>();
  const [grupos, setGrupos] = useState<GrupoOpcoesPrato[] | null>(null);
  const [grupo, setGrupo] = useState<GrupoEditado | null>(null);
  const [opcao, setOpcao] = useState<OpcaoEditada | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    lerGruposOpcoes(String(prato))
      .then(setGrupos)
      .catch((e) => setErro(mensagemErro(e)));
  }, [prato]);
  useEffect(carregar, [carregar]);

  async function correr(f: () => Promise<void>) {
    setErro(null);
    setOcupado(true);
    try {
      await f();
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const minimo = Number(grupo?.minimo || 0);
  const maximo = Number(grupo?.maximo || 0);
  const grupoValido = grupo !== null && grupo.nome.trim() !== '' && maximo >= 1 && maximo <= 20 && minimo <= maximo;

  return (
    <Guarda permissoes={['cozinhas.gerir']}>
      <Ecra>
        {nome && <Subtitulo>{nome}</Subtitulo>}
        <Paragrafo suave>
          O cliente monta o prato escolhendo opções em cada grupo. Com mínimo 1 o grupo é obrigatório; o preço extra soma ao
          preço do prato. Só aparece aos clientes com o interruptor &quot;pratos_montaveis&quot; ligado.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {grupos === null && !erro && <ACarregar />}
        {grupos?.length === 0 && <Paragrafo suave>Este prato ainda não tem opções.</Paragrafo>}

        {grupos?.map((g) => (
          <Cartao key={g.id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <Text style={{ fontWeight: '700', fontSize: 16, flex: 1 }}>{g.nome}</Text>
              <Text style={{ color: cores.textoSuave }}>
                {g.minimo === 0 ? 'opcional' : `mín. ${g.minimo}`} · máx. {g.maximo}
              </Text>
            </View>
            {g.opcoes.map((o) => (
              <View key={o.id} style={{ flexDirection: 'row', alignItems: 'center', gap: espaco.s }}>
                <Text style={{ flex: 1, color: o.disponivel ? cores.texto : cores.textoSuave }}>
                  {o.nome}
                  {o.preco_extra > 0 ? ` · +${formatarKz(o.preco_extra)}` : ''}
                  {o.disponivel ? '' : ' · esgotada'}
                </Text>
                <Botao
                  titulo="Editar"
                  variante="texto"
                  aoCarregar={() =>
                    setOpcao({ ...o, preco_extra: String(o.preco_extra), ordem: String(o.ordem) })
                  }
                />
              </View>
            ))}
            <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
              <Botao
                titulo="Nova opção"
                variante="secundario"
                aoCarregar={() => setOpcao({ grupo_id: g.id, nome: '', preco_extra: '0', disponivel: true, ordem: '0' })}
              />
              <Botao
                titulo="Editar grupo"
                variante="texto"
                aoCarregar={() =>
                  setGrupo({ id: g.id, nome: g.nome, minimo: String(g.minimo), maximo: String(g.maximo), ordem: String(g.ordem) })
                }
              />
            </View>
          </Cartao>
        ))}

        {opcao && (
          <Cartao>
            <Subtitulo>{opcao.id ? 'Editar opção' : 'Nova opção'}</Subtitulo>
            <Campo rotulo="Nome (ex.: Funge, Ovo estrelado)" value={opcao.nome} onChangeText={(t) => setOpcao({ ...opcao, nome: t })} />
            <Campo
              rotulo="Preço extra (Kz, 0 se não acrescenta)"
              value={opcao.preco_extra}
              keyboardType="number-pad"
              onChangeText={(t) => setOpcao({ ...opcao, preco_extra: numero(t) })}
            />
            <Campo rotulo="Ordem" value={opcao.ordem} keyboardType="number-pad" onChangeText={(t) => setOpcao({ ...opcao, ordem: numero(t) })} />
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <Text>Disponível (desligar quando esgotar)</Text>
              <Switch
                value={opcao.disponivel}
                onValueChange={(v) => setOpcao({ ...opcao, disponivel: v })}
                trackColor={{ true: cores.marca, false: cores.linha }}
              />
            </View>
            <Botao
              titulo="Guardar opção"
              aCarregar={ocupado}
              desactivado={!opcao.nome.trim()}
              aoCarregar={() =>
                correr(async () => {
                  await guardarOpcao({
                    ...opcao,
                    nome: opcao.nome.trim(),
                    preco_extra: Number(opcao.preco_extra || 0),
                    ordem: Number(opcao.ordem || 0),
                  });
                  setOpcao(null);
                })
              }
            />
            {opcao.id && (
              <Botao
                titulo="Apagar opção"
                variante="texto"
                aoCarregar={() =>
                  correr(async () => {
                    await apagarOpcao(opcao.id as string);
                    setOpcao(null);
                  })
                }
              />
            )}
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setOpcao(null)} />
          </Cartao>
        )}

        {grupo ? (
          <Cartao>
            <Subtitulo>{grupo.id ? 'Editar grupo' : 'Novo grupo'}</Subtitulo>
            <Campo rotulo="Nome do grupo (ex.: Base, Acompanhamentos, Extras)" value={grupo.nome} onChangeText={(t) => setGrupo({ ...grupo, nome: t })} />
            <Campo
              rotulo="Mínimo de escolhas (0 = opcional)"
              value={grupo.minimo}
              keyboardType="number-pad"
              onChangeText={(t) => setGrupo({ ...grupo, minimo: numero(t) })}
            />
            <Campo
              rotulo="Máximo de escolhas"
              value={grupo.maximo}
              keyboardType="number-pad"
              onChangeText={(t) => setGrupo({ ...grupo, maximo: numero(t) })}
            />
            <Campo rotulo="Ordem" value={grupo.ordem} keyboardType="number-pad" onChangeText={(t) => setGrupo({ ...grupo, ordem: numero(t) })} />
            {!grupoValido && grupo.nome.trim() !== '' && <Aviso>O máximo tem de ser de 1 a 20 e não pode ser menor que o mínimo.</Aviso>}
            <Botao
              titulo="Guardar grupo"
              aCarregar={ocupado}
              desactivado={!grupoValido}
              aoCarregar={() =>
                correr(async () => {
                  await guardarGrupoOpcoes({
                    id: grupo.id,
                    cardapio_id: String(prato),
                    nome: grupo.nome.trim(),
                    minimo,
                    maximo,
                    ordem: Number(grupo.ordem || 0),
                  });
                  setGrupo(null);
                })
              }
            />
            {grupo.id && (
              <Botao
                titulo="Apagar grupo"
                variante="texto"
                aoCarregar={() =>
                  correr(async () => {
                    await apagarGrupoOpcoes(grupo.id as string);
                    setGrupo(null);
                  })
                }
              />
            )}
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setGrupo(null)} />
          </Cartao>
        ) : (
          <Botao
            titulo="Novo grupo de opções"
            variante="secundario"
            aoCarregar={() => setGrupo({ nome: '', minimo: '1', maximo: '1', ordem: String(grupos?.length ?? 0) })}
          />
        )}
      </Ecra>
    </Guarda>
  );
}
