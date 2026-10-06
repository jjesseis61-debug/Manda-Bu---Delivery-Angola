import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import {
  criarEmpresa,
  editarEmpresa,
  empresaAdicionarMembro,
  empresaMembrosLista,
  empresaRemoverMembro,
  listarEmpresas,
  relatorioEmpresa,
} from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { Empresa, EmpresaMembro, RelatorioEmpresa } from '@/lib/tipos';

/** Contas de empresa (B2B): criar, membros (pelo código do cliente) e total do mês a faturar. */
export default function Empresas() {
  const [empresas, setEmpresas] = useState<Empresa[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [nova, setNova] = useState<{ nome: string; limite: string } | null>(null);
  const [aberta, setAberta] = useState<Empresa | null>(null);
  const [membros, setMembros] = useState<EmpresaMembro[]>([]);
  const [relatorio, setRelatorio] = useState<RelatorioEmpresa | null>(null);
  const [codigo, setCodigo] = useState('');
  const [edicao, setEdicao] = useState<{ nome: string; limite: string; activa: boolean } | null>(null);
  const [aGuardar, setAGuardar] = useState(false);

  const carregar = useCallback(() => {
    listarEmpresas()
      .then(setEmpresas)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  const abrir = useCallback((e: Empresa) => {
    setAberta(e);
    setEdicao(null);
    setCodigo('');
    const agora = new Date();
    empresaMembrosLista(e.id).then(setMembros).catch(() => setMembros([]));
    relatorioEmpresa(e.id, agora.getFullYear(), agora.getMonth() + 1)
      .then(setRelatorio)
      .catch(() => setRelatorio(null));
  }, []);

  async function guardarNova() {
    if (!nova) return;
    setErro(null);
    setAGuardar(true);
    try {
      await criarEmpresa(nova.nome.trim(), Math.max(0, Math.round(Number(nova.limite) || 0)));
      setNova(null);
      setSucesso('Empresa criada.');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  async function acao(fn: () => Promise<void>, ok: string) {
    setErro(null);
    setSucesso(null);
    setAGuardar(true);
    try {
      await fn();
      setSucesso(ok);
      if (aberta) abrir(aberta);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  return (
    <Guarda permissoes={['clientes.gerir']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}

        {aberta ? (
          <>
            <Botao titulo="← Voltar às empresas" variante="texto" aoCarregar={() => setAberta(null)} />
            <Subtitulo>{aberta.nome}</Subtitulo>

            {edicao ? (
              <Cartao>
                <Campo rotulo="Nome" value={edicao.nome} onChangeText={(t) => setEdicao({ ...edicao, nome: t })} />
                <Campo
                  rotulo="Limite por refeição (Kz)"
                  value={edicao.limite}
                  onChangeText={(t) => setEdicao({ ...edicao, limite: t.replace(/\D/g, '') })}
                  keyboardType="numeric"
                />
                <Escolha
                  opcoes={[
                    { valor: 'sim', rotulo: 'Activa' },
                    { valor: 'nao', rotulo: 'Suspensa' },
                  ]}
                  valor={edicao.activa ? 'sim' : 'nao'}
                  aoMudar={(v) => setEdicao({ ...edicao, activa: v === 'sim' })}
                />
                <Botao
                  titulo="Guardar"
                  aCarregar={aGuardar}
                  aoCarregar={() =>
                    acao(
                      () => editarEmpresa(aberta.id, edicao.nome.trim(), Math.max(0, Math.round(Number(edicao.limite) || 0)), edicao.activa),
                      'Empresa actualizada.',
                    ).then(() => setEdicao(null))
                  }
                />
                <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setEdicao(null)} />
              </Cartao>
            ) : (
              <Cartao>
                <Paragrafo>
                  Limite por refeição: {formatarKz(aberta.limite_refeicao)} · {aberta.activa ? 'Activa' : 'Suspensa'}
                </Paragrafo>
                {relatorio && (
                  <Paragrafo suave>
                    Este mês ({relatorio.mes}): {formatarKz(relatorio.total)} a faturar · {relatorio.pedidos.length}{' '}
                    {relatorio.pedidos.length === 1 ? 'pedido' : 'pedidos'}
                  </Paragrafo>
                )}
                <Botao
                  titulo="Editar empresa"
                  variante="texto"
                  aoCarregar={() => setEdicao({ nome: aberta.nome, limite: String(aberta.limite_refeicao), activa: aberta.activa })}
                />
              </Cartao>
            )}

            <Cartao>
              <Subtitulo>Membros ({membros.length})</Subtitulo>
              <Paragrafo suave>Adiciona pelo código que o funcionário partilha na app (ex.: MB-1234).</Paragrafo>
              <View style={{ flexDirection: 'row', gap: espaco.s, alignItems: 'flex-end' }}>
                <View style={{ flex: 1 }}>
                  <Campo rotulo="Código do cliente" value={codigo} onChangeText={setCodigo} autoCapitalize="characters" />
                </View>
                <Botao
                  titulo="Adicionar"
                  desactivado={codigo.trim().length < 3}
                  aCarregar={aGuardar}
                  aoCarregar={() => acao(() => empresaAdicionarMembro(aberta.id, codigo.trim()), 'Membro adicionado.').then(() => setCodigo(''))}
                />
              </View>
              {membros.map((m) => (
                <View key={m.cliente_id} style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: espaco.s }}>
                  <Text style={{ color: cores.texto, flex: 1 }}>
                    {m.nome}
                    {m.codigo ? ` · ${m.codigo}` : ''}
                  </Text>
                  <Botao titulo="Remover" variante="texto" aoCarregar={() => acao(() => empresaRemoverMembro(aberta.id, m.cliente_id), 'Membro removido.')} />
                </View>
              ))}
              {membros.length === 0 && <Paragrafo suave>Sem membros ainda.</Paragrafo>}
            </Cartao>
          </>
        ) : (
          <>
            {nova ? (
              <Cartao>
                <Subtitulo>Nova empresa</Subtitulo>
                <Campo rotulo="Nome da empresa" value={nova.nome} onChangeText={(t) => setNova({ ...nova, nome: t })} />
                <Campo
                  rotulo="Limite por refeição (Kz)"
                  value={nova.limite}
                  onChangeText={(t) => setNova({ ...nova, limite: t.replace(/\D/g, '') })}
                  keyboardType="numeric"
                  placeholder="Ex.: 3000"
                />
                <Botao titulo="Criar" desactivado={nova.nome.trim().length === 0} aCarregar={aGuardar} aoCarregar={guardarNova} />
                <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setNova(null)} />
              </Cartao>
            ) : (
              <Botao titulo="Nova empresa" aoCarregar={() => setNova({ nome: '', limite: '' })} />
            )}

            {!empresas && !erro && <ACarregar />}
            {empresas?.map((e) => (
              <Cartao key={e.id} estilo={e.activa ? undefined : { opacity: 0.6 }}>
                <Text style={{ fontWeight: '700', color: cores.texto }}>{e.nome}</Text>
                <Text style={{ color: cores.textoSuave }}>
                  Limite {formatarKz(e.limite_refeicao)} · {e.membros} {e.membros === 1 ? 'membro' : 'membros'}
                  {e.activa ? '' : ' · suspensa'}
                </Text>
                <Botao titulo="Gerir" variante="texto" aoCarregar={() => abrir(e)} />
              </Cartao>
            ))}
            {empresas && empresas.length === 0 && <Paragrafo suave>Ainda não há empresas. Cria a primeira conta B2B.</Paragrafo>}
            <Paragrafo suave>
              A empresa paga até ao limite por refeição de cada funcionário; o funcionário paga só a diferença na
              entrega. O total do mês é a base da fatura (emitida na cozinha).
            </Paragrafo>
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
