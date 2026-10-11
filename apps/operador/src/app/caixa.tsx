import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useState } from 'react';
import { Image, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { abrirCaixa, caixasRecentes, conferirComprovativo, fecharCaixa, lerCozinhas, pedirNovaLeitura, registarSangria, resumoCaixa } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro, textoLeitura } from '@/lib/formatar';
import { enderecoComprovativo } from '@/lib/fotos';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import type { CaixaGestao, ComprovativoCaixa, Cozinha, ResumoCaixa } from '@/lib/tipos';

type Accao = { caixaId: string; tipo: 'sangria' | 'fecho' } | null;

const soDigitos = (t: string) => t.replace(/\D/g, '');

/** Caixa: abrir (posto e troco), sangrias e fecho com a contagem do dinheiro (regras 7 e 8) */
export default function CaixaEcra() {
  const { funcionario, pode } = useSessao();
  const router = useRouter();
  const [caixas, setCaixas] = useState<CaixaGestao[] | null>(null);
  const [resumos, setResumos] = useState<Record<string, ResumoCaixa>>({});
  const [cozinhas, setCozinhas] = useState<Cozinha[]>([]);
  const [abrir, setAbrir] = useState<{ cozinhaId: string; posto: string; troco: string } | null>(null);
  const [accao, setAccao] = useState<Accao>(null);
  const [valor, setValor] = useState('');
  const [texto, setTexto] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [fotos, setFotos] = useState<Record<string, string>>({});
  const [rejeitar, setRejeitar] = useState<{ id: string; nota: string } | null>(null);

  const carregar = useCallback(() => {
    Promise.all([caixasRecentes(), lerCozinhas()])
      .then(async ([lista, todas]) => {
        // Só as cozinhas onde pode abrir caixa: todas com cozinhas.gerir, senão as dos seus turnos
        setCozinhas(pode('cozinhas.gerir') ? todas : todas.filter((c) => funcionario?.cozinhas_equipa.includes(c.id)));
        const abertas = lista.filter((c) => !c.fechamento);
        const r = await Promise.all(abertas.map((c) => resumoCaixa(c.id)));
        setResumos(Object.fromEntries(r.map((x) => [x.caixa_id, x])));
        setCaixas(lista);
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [funcionario, pode]);
  useFocusEffect(carregar);

  async function correr(f: () => Promise<unknown>, mensagem: string) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      setAbrir(null);
      setAccao(null);
      setRejeitar(null);
      setValor('');
      setTexto('');
      setSucesso(mensagem);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const nomeCozinha = (id: string) => cozinhas.find((c) => c.id === id)?.nome.trim() ?? '';
  const abertas = caixas?.filter((c) => !c.fechamento) ?? [];
  const fechadas = caixas?.filter((c) => c.fechamento).slice(0, 10) ?? [];

  async function verFoto(k: ComprovativoCaixa) {
    const url = await enderecoComprovativo(k.caminho).catch(() => null);
    if (url) setFotos((f) => ({ ...f, [k.id]: url }));
    else setErro('Não foi possível abrir a foto do comprovativo.');
  }

  /** Pagamento electrónico: referência, foto e conferência (antes de fechar a caixa) */
  function comprovativo(k: ComprovativoCaixa) {
    const aRejeitar = rejeitar?.id === k.id;
    return (
      <View key={k.id} style={{ gap: espaco.xs, borderTopWidth: 1, borderTopColor: cores.contorno, paddingTop: espaco.s }}>
        <Linha esquerda={`${k.metodo} · ${k.cliente_nome}`} direita={formatarKz(k.valor)} />
        <Text>Referência: {k.referencia}</Text>
        {k.ia_estado && (
          <Text style={{ color: textoLeitura(k.ia_estado).alerta ? cores.erro : cores.textoSuave, fontWeight: textoLeitura(k.ia_estado).alerta ? '700' : '400' }}>
            {textoLeitura(k.ia_estado, k.ia_valor, k.ia_referencia).texto}
          </Text>
        )}
        <Text style={{ color: cores.textoSuave }}>
          {formatarData(k.criado_em, true)}
          {k.registado_por ? ` · ${k.registado_por}` : ''}
        </Text>
        {k.estado !== 'por_conferir' && (
          <Text style={{ fontWeight: '700', color: k.estado === 'conferido' ? cores.sucesso : cores.erro }}>
            {k.estado === 'conferido' ? 'Conferido' : `Rejeitado: ${k.nota ?? ''}`}
          </Text>
        )}
        {fotos[k.id] ? (
          <Image
            source={{ uri: fotos[k.id] }}
            accessibilityLabel={`Comprovativo ${k.referencia}`}
            style={{ width: '100%', height: 260, borderRadius: 8, backgroundColor: cores.contorno }}
            resizeMode="contain"
          />
        ) : (
          <Botao titulo="Ver foto do comprovativo" variante="texto" aoCarregar={() => verFoto(k)} />
        )}
        <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
          <Botao
            titulo="Histórico do pedido"
            variante="texto"
            aoCarregar={() => router.push({ pathname: '/pedido/[id]', params: { id: k.pedido_id } })}
          />
          {(k.ia_estado === 'ilegivel' || k.ia_estado === 'indisponivel') && k.estado === 'por_conferir' && (
            <Botao
              titulo="Ler de novo"
              variante="texto"
              aoCarregar={() => correr(() => pedirNovaLeitura('comprovativo', k.id), 'Nova leitura pedida.')}
            />
          )}
        </View>
        {k.estado === 'por_conferir' &&
          (aRejeitar ? (
            <>
              <Campo
                rotulo="Porque rejeitas? (ex.: não aparece no extracto)"
                value={rejeitar.nota}
                maxLength={300}
                onChangeText={(t) => setRejeitar({ id: k.id, nota: t })}
              />
              <Botao
                titulo="Rejeitar pagamento"
                variante="secundario"
                desactivado={!rejeitar.nota.trim()}
                aCarregar={ocupado}
                aoCarregar={() => correr(() => conferirComprovativo(k.id, false, rejeitar.nota.trim()), 'Pagamento rejeitado.')}
              />
              <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setRejeitar(null)} />
            </>
          ) : (
            <View style={{ flexDirection: 'row', gap: espaco.s }}>
              <Botao
                titulo="Confere"
                variante="leve"
                aCarregar={ocupado}
                aoCarregar={() => correr(() => conferirComprovativo(k.id, true), 'Pagamento conferido.')}
              />
              <Botao titulo="Rejeitar…" variante="texto" aoCarregar={() => setRejeitar({ id: k.id, nota: '' })} />
            </View>
          ))}
      </View>
    );
  }

  function cartaoAberta(c: CaixaGestao) {
    const r = resumos[c.id];
    const minha = accao?.caixaId === c.id ? accao.tipo : null;
    const diferenca = r && minha === 'fecho' && valor !== '' ? Number(valor) - r.esperado : null;
    return (
      <Cartao key={c.id}>
        <Text style={{ fontWeight: '700', fontSize: 16 }}>
          {c.posto} · {nomeCozinha(c.cozinha_id)}
        </Text>
        <Text style={{ color: cores.textoSuave }}>
          Aberta em {formatarData(c.data)}
          {c.funcionario_nome ? ` por ${c.funcionario_nome}` : ''}
        </Text>
        {r ? (
          <>
            <Linha esquerda="Troco inicial" direita={formatarKz(r.troco_inicial)} />
            <Linha esquerda={`Dinheiro das entregas (${r.pedidos})`} direita={formatarKz(r.dinheiro_vendas)} />
            <Linha esquerda={`Pacotes pagos na loja (${r.pacotes})`} direita={formatarKz(r.dinheiro_pacotes)} />
            <Linha esquerda="Sangrias" direita={`− ${formatarKz(r.sangrias)}`} />
            <Linha esquerda="Deve estar na caixa" direita={formatarKz(r.esperado)} forte />
            {r.lista_sangrias.map((s, i) => (
              <Text key={i} style={{ color: cores.textoSuave }}>
                Sangria {formatarKz(s.valor)}: {s.motivo}
              </Text>
            ))}
            {r.comprovativos.length > 0 && (
              <>
                <Linha esquerda={`Pagamentos electrónicos (${r.comprovativos.length})`} direita={formatarKz(r.electronico)} />
                <Text style={{ color: cores.textoSuave }}>
                  Não entram na caixa: confere cada um com o extracto (Multicaixa, TPA, Unitel Money) antes de fechar.
                </Text>
                {r.por_conferir > 0 && <Aviso>Faltam conferir {r.por_conferir}.</Aviso>}
                {r.comprovativos.map(comprovativo)}
              </>
            )}
          </>
        ) : (
          <ACarregar />
        )}

        {minha === 'sangria' && (
          <>
            <Campo rotulo="Valor retirado (Kz)" value={valor} keyboardType="number-pad" onChangeText={(t) => setValor(soDigitos(t))} />
            <Campo rotulo="Motivo (ex.: compra de gás)" value={texto} onChangeText={setTexto} maxLength={120} />
            <Botao
              titulo="Registar sangria"
              desactivado={!Number(valor) || !texto.trim()}
              aCarregar={ocupado}
              aoCarregar={() => correr(() => registarSangria(c.id, Number(valor), texto.trim()), 'Sangria registada.')}
            />
          </>
        )}
        {minha === 'fecho' && (
          <>
            <Campo rotulo="Dinheiro contado na caixa (Kz)" value={valor} keyboardType="number-pad" onChangeText={(t) => setValor(soDigitos(t))} />
            {diferenca !== null && (
              <Aviso tipo={diferenca === 0 ? 'sucesso' : 'aviso'}>
                {diferenca === 0
                  ? 'A caixa bate certo.'
                  : diferenca > 0
                    ? `Sobram ${formatarKz(diferenca)}.`
                    : `Faltam ${formatarKz(-diferenca)}.`}
              </Aviso>
            )}
            <Campo rotulo="Observação (opcional)" value={texto} onChangeText={setTexto} maxLength={300} />
            {!!r?.por_conferir && <Aviso tipo="erro">Confere os pagamentos electrónicos antes de fechar a caixa.</Aviso>}
            <Botao
              titulo="Fechar caixa"
              desactivado={valor === '' || !!r?.por_conferir}
              aCarregar={ocupado}
              aoCarregar={() => correr(() => fecharCaixa(c.id, Number(valor), texto.trim() || null), 'Caixa fechada.')}
            />
          </>
        )}
        {minha ? (
          <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setAccao(null)} />
        ) : (
          <>
            <Botao
              titulo="Sangria"
              variante="leve"
              aoCarregar={() => {
                setValor('');
                setTexto('');
                setAccao({ caixaId: c.id, tipo: 'sangria' });
              }}
            />
            <Botao
              titulo="Fechar caixa"
              variante="secundario"
              aoCarregar={() => {
                setValor('');
                setTexto('');
                setAccao({ caixaId: c.id, tipo: 'fecho' });
              }}
            />
          </>
        )}
      </Cartao>
    );
  }

  return (
    <Guarda permissoes={['vendas.registar']}>
      <Ecra>
        <Paragrafo suave>
          Sem caixa aberta não se marcam entregas pagas em dinheiro nem pacotes pagos na loja. O caixa conta só a parte paga em
          dinheiro.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {caixas === null && !erro && <ACarregar />}

        {caixas !== null && abertas.length === 0 && <Aviso>Não há nenhuma caixa aberta.</Aviso>}
        {abertas.map(cartaoAberta)}

        {abrir ? (
          <Cartao>
            <Subtitulo>Abrir caixa</Subtitulo>
            {cozinhas.length > 1 && (
              <Escolha
                opcoes={cozinhas.map((c) => ({ valor: c.id, rotulo: c.nome.trim() }))}
                valor={abrir.cozinhaId}
                aoMudar={(v) => setAbrir({ ...abrir, cozinhaId: v })}
              />
            )}
            <Campo rotulo="Posto (ex.: Balcão, Estafeta)" value={abrir.posto} onChangeText={(t) => setAbrir({ ...abrir, posto: t })} maxLength={40} />
            <Campo
              rotulo="Troco inicial (Kz)"
              value={abrir.troco}
              keyboardType="number-pad"
              onChangeText={(t) => setAbrir({ ...abrir, troco: soDigitos(t) })}
            />
            <Botao
              titulo="Abrir caixa"
              desactivado={!abrir.cozinhaId || !abrir.posto.trim()}
              aCarregar={ocupado}
              aoCarregar={() => correr(() => abrirCaixa(abrir.cozinhaId, abrir.posto.trim(), Number(abrir.troco || 0)), 'Caixa aberta.')}
            />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setAbrir(null)} />
          </Cartao>
        ) : (
          caixas !== null &&
          (cozinhas.length === 0 ? (
            <Aviso>Só abre caixa quem tem turnos numa cozinha.</Aviso>
          ) : (
            <Botao titulo="Abrir caixa" aoCarregar={() => setAbrir({ cozinhaId: cozinhas[0].id, posto: 'Balcão', troco: '' })} />
          ))
        )}

        {fechadas.length > 0 && <Subtitulo>Caixas fechadas</Subtitulo>}
        {fechadas.map((c) => {
          const f = c.fechamento!;
          return (
            <Cartao key={c.id}>
              <Text style={{ fontWeight: '700' }}>
                {c.posto} · {formatarData(c.data)}
              </Text>
              <Linha esquerda="Devia estar" direita={formatarKz(f.esperado)} />
              <Linha esquerda="Contado" direita={formatarKz(f.contado)} />
              {!!f.rejeitados && (
                <Text style={{ color: cores.erro }}>
                  {f.rejeitados} pagamento{f.rejeitados > 1 ? 's' : ''} electrónico{f.rejeitados > 1 ? 's' : ''} rejeitado
                  {f.rejeitados > 1 ? 's' : ''} ({formatarKz(f.valor_rejeitado ?? 0)})
                </Text>
              )}
              <Text style={{ fontWeight: '700', color: f.diferenca === 0 ? cores.sucesso : cores.erro }}>
                {f.diferenca === 0
                  ? 'Caixa certa'
                  : f.diferenca > 0
                    ? `Sobraram ${formatarKz(f.diferenca)}`
                    : `Faltaram ${formatarKz(-f.diferenca)}`}
              </Text>
              <Text style={{ color: cores.textoSuave }}>
                Fechada {formatarData(f.fechado_em, true)}
                {f.funcionario_nome ? ` por ${f.funcionario_nome}` : ''}
                {f.observacao ? ` · ${f.observacao}` : ''}
              </Text>
            </Cartao>
          );
        })}
      </Ecra>
    </Guarda>
  );
}
