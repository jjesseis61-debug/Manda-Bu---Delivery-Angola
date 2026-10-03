import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { abrirCaixa, caixasRecentes, fecharCaixa, lerCozinhas, registarSangria, resumoCaixa } from '@/lib/api';
import { formatarData, formatarKz, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { CaixaGestao, Cozinha, ResumoCaixa } from '@/lib/tipos';

type Accao = { caixaId: string; tipo: 'sangria' | 'fecho' } | null;

const soDigitos = (t: string) => t.replace(/\D/g, '');

/** Caixa: abrir (posto e troco), sangrias e fecho com a contagem do dinheiro (regras 7 e 8) */
export default function CaixaEcra() {
  const { funcionario, pode } = useSessao();
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
            <Botao
              titulo="Fechar caixa"
              desactivado={valor === ''}
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
