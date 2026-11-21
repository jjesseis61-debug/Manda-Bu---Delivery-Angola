import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Share, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { acertosSemana, definirFaturaAcerto, fecharAcerto, registarPagamentoAcerto } from '@/lib/api';
import { escolherFoto, enviarComprovativoAcerto } from '@/lib/fotos';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { AcertoCozinha, AcertosSemana } from '@/lib/tipos';

const METODOS = ['Dinheiro', 'Transferência', 'Multicaixa Express', 'Unitel Money'] as const;
type Metodo = (typeof METODOS)[number];

const MESES = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/** "2026-11-16" → Date ao meio-dia (sem saltos de fuso) */
function dia(iso: string): Date {
  return new Date(`${iso}T12:00:00`);
}
function isoDe(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
/** "16–22 nov 2026" (ou "28 out – 3 nov 2026") */
export function nomeSemana(inicio: string, fim: string): string {
  const a = dia(inicio);
  const b = dia(fim);
  return a.getMonth() === b.getMonth()
    ? `${a.getDate()}–${b.getDate()} ${MESES[b.getMonth()]} ${b.getFullYear()}`
    : `${a.getDate()} ${MESES[a.getMonth()]} – ${b.getDate()} ${MESES[b.getMonth()]} ${b.getFullYear()}`;
}

/** "A cozinha paga 1.800 Kz" / "A plataforma paga 1.700 Kz" / "Nada a acertar" */
export function textoSaldo(saldo: number): string {
  if (saldo > 0) return `A cozinha paga ${formatarKz(saldo)}`;
  if (saldo < 0) return `A plataforma paga ${formatarKz(-saldo)}`;
  return 'Nada a acertar';
}

/** Nota do acerto para enviar à cozinha (WhatsApp/partilhar) */
export function notaAcerto(c: AcertoCozinha, inicio: string, fim: string): string {
  const t = c.totais;
  const linhas = [
    `*Manda Bué · Acerto da semana ${nomeSemana(inicio, fim)}*`,
    c.cozinha_nome,
    '',
    `Pedidos entregues: ${t.pedidos}`,
    `Vendas de comida: ${formatarKz(t.vendas)}`,
    '',
    'A cozinha deve à plataforma:',
    `• Taxas de entrega: ${formatarKz(t.taxas_entrega)}`,
    `• Comissão (${c.comissao_percent}%): ${formatarKz(t.comissao)}`,
    ...(t.compensacoes ? [`• Compensações a clientes: ${formatarKz(t.compensacoes)}`] : []),
    '',
    'A plataforma deve à cozinha:',
    `• Convida (descontos e saldo): ${formatarKz(t.convida_plataforma)}`,
    `• Refeições de pacotes: ${formatarKz(t.pago_pacote)}`,
    `• Parte das empresas: ${formatarKz(t.valor_empresa)}`,
    '',
    `*Saldo: ${textoSaldo(t.saldo)}*`,
  ];
  if (c.pago > 0) linhas.push(`Já pago: ${formatarKz(c.pago)}`);
  if (c.estado === 'fechado') linhas.push(`Falta pagar: ${formatarKz(c.por_pagar)}`);
  if (c.numero_fatura) linhas.push(`Fatura: ${c.numero_fatura}`);
  return linhas.join('\n');
}

/**
 * Acertos com as cozinhas (semana a semana). A cozinha fica com o dinheiro das entregas: deve à
 * plataforma a taxa de entrega e a comissão; a plataforma deve-lhe o Convida (na parte dela), as
 * refeições de pacotes e a parte das empresas. Fechar a semana guarda os valores; depois regista-se
 * o pagamento e o número da fatura do software certificado.
 */
export default function Acertos() {
  const [semana, setSemana] = useState<string | null>(null);
  const [dados, setDados] = useState<AcertosSemana | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<{ id: string; accao: 'pagar' | 'fatura' } | null>(null);
  const [valor, setValor] = useState('');
  const [metodo, setMetodo] = useState<Metodo>('Transferência');
  const [texto, setTexto] = useState('');
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [foto, setFoto] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setDados(null);
    setErro(null);
    acertosSemana(semana)
      .then(setDados)
      .catch((e) => setErro(mensagemErro(e)));
  }, [semana]);
  useFocusEffect(carregar);

  function mudarSemana(dias: number) {
    if (!dados) return;
    const d = dia(dados.semana_inicio);
    d.setDate(d.getDate() + dias);
    setAberto(null);
    setSemana(isoDe(d));
  }

  async function accao(id: string, f: () => Promise<unknown>) {
    setErro(null);
    setOcupado(id);
    try {
      await f();
      setAberto(null);
      setTexto('');
      setValor('');
      setFoto(null);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  const fechadas = dados?.cozinhas.filter((c) => c.estado !== 'aberto') ?? [];
  const aReceber = fechadas.filter((c) => c.totais.saldo > 0).reduce((s, c) => s + c.por_pagar, 0);
  const aPagar = fechadas.filter((c) => c.totais.saldo < 0).reduce((s, c) => s + c.por_pagar, 0);

  return (
    <Guarda permissoes={['financas.acertos', 'relatorios.exportar']}>
      <Ecra>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
          <Botao titulo="‹ Anterior" variante="texto" aoCarregar={() => mudarSemana(-7)} desactivado={!dados} />
          <Text style={{ fontWeight: '700', fontSize: 16, color: cores.texto }}>
            {dados ? nomeSemana(dados.semana_inicio, dados.semana_fim) : '…'}
          </Text>
          <Botao titulo="Seguinte ›" variante="texto" aoCarregar={() => mudarSemana(7)} desactivado={!dados} />
        </View>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!dados && !erro && <ACarregar />}
        {dados && (
          <>
            {!dados.pode_fechar && <Aviso>Semana em curso: os valores ainda vão mudar. Fecha-se a partir de segunda-feira.</Aviso>}
            {fechadas.length > 0 && (
              <Cartao>
                <Linha esquerda="A receber das cozinhas" direita={formatarKz(aReceber)} forte />
                <Linha esquerda="A pagar às cozinhas" direita={formatarKz(aPagar)} forte />
              </Cartao>
            )}
            {dados.cozinhas.length === 0 && <Paragrafo suave>Nenhuma cozinha com vendas nesta semana.</Paragrafo>}
            {dados.cozinhas.map((c) => (
              <CartaoCozinha
                key={c.cozinha_id}
                c={c}
                podeFechar={dados.pode_fechar}
                podeGerir={dados.pode_gerir !== false}
                aoPartilhar={() => void Share.share({ message: notaAcerto(c, dados.semana_inicio, dados.semana_fim) }).catch(() => undefined)}
                foto={foto}
                aoFoto={async () => {
                  const uri = await escolherFoto('camera', false).catch(() => null);
                  if (uri) setFoto(uri);
                }}
                aberto={aberto && aberto.id === c.acerto_id ? aberto.accao : null}
                ocupado={ocupado === (c.acerto_id ?? c.cozinha_id)}
                aoFechar={() => accao(c.cozinha_id, () => fecharAcerto(c.cozinha_id, dados.semana_inicio))}
                aoAbrir={(a) => {
                  setAberto({ id: c.acerto_id!, accao: a });
                  setTexto(a === 'fatura' ? (c.numero_fatura ?? '') : '');
                  setValor(String(c.por_pagar));
                }}
                aoVoltar={() => setAberto(null)}
                valor={valor}
                setValor={setValor}
                metodo={metodo}
                setMetodo={setMetodo}
                texto={texto}
                setTexto={setTexto}
                aoPagar={() =>
                  accao(c.acerto_id!, async () => {
                    const caminho = foto ? await enviarComprovativoAcerto(c.acerto_id!, foto) : null;
                    return registarPagamentoAcerto(c.acerto_id!, Number(valor.replace(/\D/g, '')), metodo, texto.trim() || null, caminho);
                  })
                }
                aoGuardarFatura={() => accao(c.acerto_id!, () => definirFaturaAcerto(c.acerto_id!, texto.trim()))}
              />
            ))}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}

function CartaoCozinha(p: {
  c: AcertoCozinha;
  podeFechar: boolean;
  podeGerir: boolean;
  aoPartilhar: () => void;
  foto: string | null;
  aoFoto: () => void;
  aberto: 'pagar' | 'fatura' | null;
  ocupado: boolean;
  aoFechar: () => void;
  aoAbrir: (a: 'pagar' | 'fatura') => void;
  aoVoltar: () => void;
  valor: string;
  setValor: (v: string) => void;
  metodo: Metodo;
  setMetodo: (m: Metodo) => void;
  texto: string;
  setTexto: (t: string) => void;
  aoPagar: () => void;
  aoGuardarFatura: () => void;
}) {
  const { c } = p;
  const t = c.totais;
  const etiqueta = c.estado === 'aberto' ? 'Aberto' : c.estado === 'pago' ? 'Pago' : 'Por pagar';
  const corEtiqueta = c.estado === 'pago' ? cores.sucesso : c.estado === 'aberto' ? cores.textoSuave : cores.aviso;
  return (
    <Cartao>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Subtitulo>{c.cozinha_nome}</Subtitulo>
        <Text style={{ color: corEtiqueta, fontWeight: '700' }}>{etiqueta}</Text>
      </View>
      <Linha esquerda={`Pedidos entregues`} direita={String(t.pedidos)} />
      <Linha esquerda="Vendas de comida" direita={formatarKz(t.vendas)} />
      <Text style={{ color: cores.textoSuave, marginTop: espaco.xs }}>A cozinha deve à plataforma</Text>
      <Linha esquerda="Taxas de entrega" direita={formatarKz(t.taxas_entrega)} />
      <Linha esquerda={`Comissão (${c.comissao_percent}%)`} direita={formatarKz(t.comissao)} />
      {!!t.compensacoes && <Linha esquerda="Compensações a clientes" direita={formatarKz(t.compensacoes)} />}
      <Text style={{ color: cores.textoSuave, marginTop: espaco.xs }}>A plataforma deve à cozinha</Text>
      <Linha esquerda="Convida (descontos e saldo)" direita={formatarKz(t.convida_plataforma)} />
      <Linha esquerda="Refeições de pacotes" direita={formatarKz(t.pago_pacote)} />
      <Linha esquerda="Parte das empresas" direita={formatarKz(t.valor_empresa)} />
      <Linha esquerda="Saldo" direita={textoSaldo(t.saldo)} forte />
      {c.estado !== 'aberto' && c.pago > 0 && <Linha esquerda="Já pago" direita={formatarKz(c.pago)} />}
      {c.estado === 'fechado' && <Linha esquerda="Falta pagar" direita={formatarKz(c.por_pagar)} forte />}
      {c.numero_fatura && <Text style={{ color: cores.textoSuave }}>Fatura: {c.numero_fatura}</Text>}
      {!!c.sem_fatura && (
        <Text style={{ color: cores.aviso, fontWeight: '700' }}>
          {c.sem_fatura === 1 ? '1 venda sem fatura' : `${c.sem_fatura} vendas sem fatura`} nesta semana
        </Text>
      )}

      {c.estado === 'aberto' && p.podeFechar && p.podeGerir && (
        <Botao titulo="Fechar a semana" aCarregar={p.ocupado} aoCarregar={p.aoFechar} />
      )}

      {p.aberto === 'pagar' && (
        <>
          <Campo rotulo="Valor (Kz)" keyboardType="number-pad" value={p.valor} onChangeText={p.setValor} />
          <Escolha opcoes={METODOS.map((m) => ({ valor: m, rotulo: m }))} valor={p.metodo} aoMudar={p.setMetodo} />
          <Campo
            rotulo={p.metodo === 'Dinheiro' ? 'Referência (opcional)' : 'Referência (obrigatória)'}
            value={p.texto}
            onChangeText={p.setTexto}
          />
          <Botao
            titulo={p.foto ? '✓ Foto do comprovativo (tirar outra)' : 'Foto do comprovativo (opcional)'}
            variante="secundario"
            aoCarregar={p.aoFoto}
          />
          <Botao titulo={t.saldo > 0 ? 'Registar o que a cozinha pagou' : 'Registar o que a plataforma pagou'} aCarregar={p.ocupado} aoCarregar={p.aoPagar} />
          <Botao titulo="Voltar" variante="texto" aoCarregar={p.aoVoltar} />
        </>
      )}
      {p.aberto === 'fatura' && (
        <>
          <Campo rotulo="Número da fatura (software certificado)" value={p.texto} onChangeText={p.setTexto} />
          <Botao titulo="Guardar o número" desactivado={!p.texto.trim()} aCarregar={p.ocupado} aoCarregar={p.aoGuardarFatura} />
          <Botao titulo="Voltar" variante="texto" aoCarregar={p.aoVoltar} />
        </>
      )}
      {!p.aberto && <Botao titulo="Enviar a nota à cozinha" variante="texto" aoCarregar={p.aoPartilhar} />}
      {!p.aberto && c.estado !== 'aberto' && p.podeGerir && (
        <View style={{ flexDirection: 'row', gap: espaco.s, flexWrap: 'wrap' }}>
          {c.estado === 'fechado' && (
            <View style={{ flex: 1 }}>
              <Botao titulo="Registar pagamento" aoCarregar={() => p.aoAbrir('pagar')} />
            </View>
          )}
          <View style={{ flex: 1 }}>
            <Botao titulo={c.numero_fatura ? 'Mudar a fatura' : 'Número da fatura'} variante="secundario" aoCarregar={() => p.aoAbrir('fatura')} />
          </View>
        </View>
      )}
    </Cartao>
  );
}
