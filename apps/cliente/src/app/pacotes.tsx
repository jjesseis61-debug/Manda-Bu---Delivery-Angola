import { Redirect, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text } from 'react-native';

import { ACarregar, Aviso, Botao, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { aderirPacote, cancelarAdesaoPacote, lerPacotes, meuPacote, pacotesAMinhaVolta, pausarPacote } from '@/lib/api';
import { EMPRESA } from '@/lib/empresa';
import { beneficiosPacote, formatarData, formatarKz, mensagemErro, nomeMetodoPacote } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { MeuPacote, MetodoPacote, Pacote, PacotesAMinhaVolta } from '@/lib/tipos';

const metodos: { valor: MetodoPacote; rotulo: string }[] = [
  { valor: 'multicaixa_express', rotulo: nomeMetodoPacote.multicaixa_express },
  { valor: 'unitel_money', rotulo: nomeMetodoPacote.unitel_money },
  { valor: 'loja', rotulo: nomeMetodoPacote.loja },
];

/** I12. Pacotes pré-pagos: catálogo, adesão, pagamento pendente e pacote em curso */
export default function Pacotes() {
  const { carregado, ligada } = useSessao();
  const [catalogo, setCatalogo] = useState<Pacote[] | null>(null);
  const [meu, setMeu] = useState<MeuPacote | null>(null);
  const [volta, setVolta] = useState<PacotesAMinhaVolta | null>(null);
  const [metodo, setMetodo] = useState<MetodoPacote>('multicaixa_express');
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(async () => {
    const [c, m, v] = await Promise.all([lerPacotes(), meuPacote(), pacotesAMinhaVolta().catch(() => null)]);
    setCatalogo(c);
    setMeu(m);
    setVolta(v);
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (!ligada('pacotes')) return;
      carregar().catch((e) => setErro(mensagemErro(e)));
    }, [ligada, carregar]),
  );

  const accao = async (f: () => Promise<unknown>, sucesso: string) => {
    setOcupado(true);
    setErro(null);
    setAviso(null);
    try {
      await f();
      await carregar();
      setAviso(sucesso);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  };

  if (!carregado) return <ACarregar />;
  if (!ligada('pacotes')) return <Redirect href="/inicio" />;
  if (!catalogo && !erro) return <ACarregar />;

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}

      {meu?.estado === 'activa' && (
        <Cartao>
          <Subtitulo>{meu.pacote}</Subtitulo>
          <Text style={{ fontSize: 28, fontWeight: '800', color: cores.sucesso }}>
            {meu.refeicoes_restantes} {meu.refeicoes_restantes === 1 ? 'refeição' : 'refeições'}
          </Text>
          <Paragrafo suave>
            por usar, de {meu.refeicoes_total} · até {formatarData(meu.fim)}
          </Paragrafo>
          {meu.poupanca > 0 && <Linha esquerda="Já poupaste" direita={formatarKz(meu.poupanca)} forte />}
          {meu.entrega_gratis && <Paragrafo>Entrega grátis nos pedidos pagos com o pacote.</Paragrafo>}
          {!meu.em_vigor && <Aviso>O pacote já não está em vigor. Fala connosco para o reembolso das refeições que sobraram.</Aviso>}
          {meu.em_vigor && meu.pausa_restante > 0 && (
            <>
              <Paragrafo suave>
                Vais estar fora? Pausa o pacote e a validade estica. Ainda podes pausar {meu.pausa_restante}{' '}
                {meu.pausa_restante === 1 ? 'dia' : 'dias'}.
              </Paragrafo>
              <Botao
                titulo="Pausar 1 dia"
                variante="secundario"
                desactivado={ocupado}
                aoCarregar={() => accao(() => pausarPacote(1), 'Pacote pausado: ganhaste mais 1 dia de validade.')}
              />
            </>
          )}
        </Cartao>
      )}

      {meu?.estado === 'pendente' && (
        <Cartao>
          <Subtitulo>{meu.pacote}: à espera do pagamento</Subtitulo>
          <Linha esquerda="A pagar" direita={formatarKz(meu.preco)} forte />
          <Linha esquerda="Forma de pagamento" direita={nomeMetodoPacote[meu.metodo]} />
          <Paragrafo>
            {EMPRESA.instrucoesPagamento ||
              'Paga e mostra o comprovativo na loja ou envia-o por mensagem. O pacote começa no dia em que confirmarmos o pagamento.'}
          </Paragrafo>
          <Botao
            titulo="Cancelar a adesão"
            variante="texto"
            desactivado={ocupado}
            aoCarregar={() => accao(() => cancelarAdesaoPacote(meu.adesao_id), 'Adesão cancelada.')}
          />
        </Cartao>
      )}

      {/* Efeito vicário: pessoas como tu que já pagam o almoço com um pacote */}
      {volta && (volta.no_meu_local || volta.na_minha_zona) && (
        <Cartao estilo={{ backgroundColor: cores.avisoFundo }}>
          {volta.no_meu_local ? (
            <Paragrafo>
              {volta.no_meu_local} {volta.no_meu_local === 1 ? 'colega do teu local de trabalho já almoça' : 'colegas do teu local de trabalho já almoçam'} com um pacote.
            </Paragrafo>
          ) : (
            <Paragrafo>
              {volta.na_minha_zona} {volta.na_minha_zona === 1 ? 'pessoa da tua zona já almoça' : 'pessoas da tua zona já almoçam'} com um pacote.
            </Paragrafo>
          )}
          {volta.poupanca_media_mes ? (
            <Paragrafo suave>Em média, poupam {formatarKz(volta.poupanca_media_mes)} por mês.</Paragrafo>
          ) : null}
        </Cartao>
      )}

      {!meu && (
        <>
          <Subtitulo>Paga o mês, almoça sem preocupações</Subtitulo>
          {catalogo?.length === 0 && <Paragrafo suave>Ainda não há pacotes disponíveis.</Paragrafo>}
          {catalogo && catalogo.length > 0 && (
            <>
              <Paragrafo suave>Forma de pagamento</Paragrafo>
              <Escolha opcoes={metodos} valor={metodo} aoMudar={setMetodo} />
            </>
          )}
          {catalogo?.map((p) => (
            <Cartao key={p.id}>
              <Subtitulo>{p.nome}</Subtitulo>
              {p.descricao && <Paragrafo suave>{p.descricao}</Paragrafo>}
              {beneficiosPacote(p).map((b) => (
                <Paragrafo key={b}>✓ {b}</Paragrafo>
              ))}
              <Linha esquerda="Preço" direita={formatarKz(p.preco)} forte />
              <Botao
                titulo={`Aderir com ${nomeMetodoPacote[metodo]}`}
                desactivado={ocupado}
                aoCarregar={() => accao(() => aderirPacote(p.id, metodo), 'Adesão registada. Falta só o pagamento.')}
              />
            </Cartao>
          ))}
        </>
      )}
    </Ecra>
  );
}
