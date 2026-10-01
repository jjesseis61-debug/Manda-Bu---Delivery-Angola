import { Redirect, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { lerLevantamentos, lerSaldo, pedirLevantamento } from '@/lib/api';
import { formatarKz, mensagemErro, nomeMetodo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { Levantamento } from '@/lib/tipos';

const nomeEstado: Record<Levantamento['estado'], string> = {
  pedido: 'Pedido',
  aprovado: 'Aprovado',
  pago: 'Pago',
  rejeitado: 'Rejeitado',
};

/** C4. Levantar saldo */
export default function Levantar() {
  const { perfil, parametros, ligada } = useSessao();
  const [saldo, setSaldo] = useState<number | null>(null);
  const [historico, setHistorico] = useState<Levantamento[]>([]);
  const [modo, setModo] = useState<'refeicoes' | 'dinheiro'>('dinheiro');
  const [metodo, setMetodo] = useState<'multicaixa_express' | 'unitel_money'>('multicaixa_express');
  const [numero, setNumero] = useState('');
  const [valor, setValor] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState(false);
  const [aEnviar, setAEnviar] = useState(false);

  const carregar = useCallback(() => {
    if (!perfil) return;
    Promise.all([lerSaldo(perfil.cliente_id), lerLevantamentos(perfil.cliente_id)])
      .then(([s, h]) => {
        setSaldo(s?.saldo_disponivel ?? 0);
        setHistorico(h);
        setValor((v) => v || String(s?.saldo_disponivel ?? ''));
      })
      .catch((e) => setErro(mensagemErro(e)));
  }, [perfil]);
  useFocusEffect(carregar);

  if (!ligada('indicacao')) return <Redirect href="/inicio" />;
  if (saldo === null || !parametros) return erro ? <Ecra><Aviso tipo="erro">{erro}</Aviso></Ecra> : <ACarregar />;

  const minimo = parametros.levantamento_minimo;
  const pedido = Math.floor(Number(valor.replace(/\D/g, '')) || 0);
  const faltam = minimo - saldo;

  async function pedir() {
    setErro(null);
    setAEnviar(true);
    try {
      await pedirLevantamento(pedido, metodo, numero);
      setSucesso(true);
      setValor('');
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  return (
    <Ecra>
      <Cartao>
        <Linha esquerda="Saldo disponível" direita={formatarKz(saldo)} forte />
        <Linha esquerda="Mínimo para levantar" direita={formatarKz(minimo)} />
      </Cartao>

      <Escolha
        opcoes={[
          { valor: 'dinheiro', rotulo: 'Receber em dinheiro' },
          { valor: 'refeicoes', rotulo: 'Usar em refeições' },
        ]}
        valor={modo}
        aoMudar={setModo}
      />

      {modo === 'refeicoes' ? (
        <Paragrafo>
          Ao confirmar um pedido, liga "Usar saldo do Convida e Ganha". O valor é descontado na hora, sem mínimo.
        </Paragrafo>
      ) : (
        <>
          <Escolha
            opcoes={[
              { valor: 'multicaixa_express', rotulo: nomeMetodo.multicaixa_express },
              { valor: 'unitel_money', rotulo: nomeMetodo.unitel_money },
            ]}
            valor={metodo}
            aoMudar={setMetodo}
          />
          <Campo rotulo="Número para receber" placeholder="923 456 789" keyboardType="phone-pad" value={numero} onChangeText={setNumero} />
          <Campo rotulo="Valor (Kz)" keyboardType="number-pad" value={valor} onChangeText={setValor} />
          {pedido > parametros.limite_parcelamento && (
            <Aviso>Acima de {formatarKz(parametros.limite_parcelamento)}, pagamos em 2 parcelas na mesma semana.</Aviso>
          )}
          {erro && <Aviso tipo="erro">{erro}</Aviso>}
          {sucesso && <Aviso tipo="sucesso">Pedido de levantamento enviado. Avisamos-te quando for pago.</Aviso>}
          <Botao
            titulo={faltam > 0 ? `Faltam ${formatarKz(faltam)}` : 'Pedir levantamento'}
            aoCarregar={pedir}
            aCarregar={aEnviar}
            desactivado={faltam > 0 || pedido < minimo || pedido > saldo || numero.replace(/\D/g, '').length < 9}
          />
        </>
      )}

      {historico.length > 0 && <Subtitulo>Levantamentos</Subtitulo>}
      {historico.map((h) => (
        <Cartao key={h.id}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
            <Text style={{ fontWeight: '700' }}>
              {formatarKz(h.valor)}
              {h.total_parcelas && h.total_parcelas > 1 ? ` (parcela ${h.parcela}/${h.total_parcelas})` : ''}
            </Text>
            <Text style={{ fontWeight: '700', color: h.estado === 'pago' ? cores.sucesso : h.estado === 'rejeitado' ? cores.erro : cores.aviso }}>
              {nomeEstado[h.estado]}
            </Text>
          </View>
          <Text style={{ color: cores.textoSuave }}>
            {nomeMetodo[h.metodo ?? ''] ?? h.metodo} · {new Date(h.criado_em).toLocaleDateString('pt-PT')}
          </Text>
          {h.referencia && <Text>Referência: {h.referencia}</Text>}
          {h.motivo_rejeicao && <Text style={{ color: cores.erro }}>{h.motivo_rejeicao}</Text>}
        </Cartao>
      ))}
    </Ecra>
  );
}
