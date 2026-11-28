import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Linha, Paragrafo, Subtitulo } from '@/components/ui';
import { resultadosMes } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores } from '@/lib/tema';
import type { ResultadosMes } from '@/lib/tipos';

import { mesAoLado, nomeMes } from './contas-empresas';
import { mesActual } from './estafetas-pagamentos';

/**
 * Resultados do mês da plataforma: o que fica para a plataforma (comissões, taxas de entrega,
 * saldos Convida expirados) menos o que custa (estafetas, serviço contratado, Convida, compensações
 * e despesas gerais). As vendas da comida são das cozinhas: aparecem só como referência.
 */
export default function Resultados() {
  const [mes, setMes] = useState<string>(mesActual());
  const [r, setR] = useState<ResultadosMes | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(() => {
    setR(null);
    setErro(null);
    resultadosMes(mes)
      .then(setR)
      .catch((e) => setErro(mensagemErro(e)));
  }, [mes]);
  useFocusEffect(carregar);

  return (
    <Guarda permissoes={['financas.resultados']}>
      <Ecra>
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
          <Botao titulo="‹ Anterior" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, -1))} />
          <Text style={{ fontWeight: '700', fontSize: 16 }}>{nomeMes(mes)}</Text>
          <Botao titulo="Seguinte ›" variante="texto" aoCarregar={() => setMes(mesAoLado(mes, 1))} />
        </View>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!r && !erro && <ACarregar />}
        {r && (
          <>
            {!r.fechado && <Aviso>Mês em curso: os valores ainda vão mudar.</Aviso>}
            <Cartao>
              <Linha esquerda="Pedidos entregues" direita={String(r.pedidos)} />
              <Linha esquerda="Vendas das cozinhas (referência)" direita={formatarKz(r.vendas_cozinhas)} />
            </Cartao>
            <Cartao>
              <Subtitulo>Receitas da plataforma</Subtitulo>
              <Linha esquerda="Comissões das cozinhas" direita={formatarKz(r.receitas.comissoes)} />
              <Linha esquerda="Taxas de entrega" direita={formatarKz(r.receitas.taxas_entrega)} />
              <Linha esquerda="Saldos Convida expirados" direita={formatarKz(r.receitas.saldos_expirados)} />
              <Linha esquerda="Total" direita={formatarKz(r.receitas.total)} forte />
            </Cartao>
            <Cartao>
              <Subtitulo>Custos</Subtitulo>
              <Linha esquerda="Estafetas próprios" direita={formatarKz(r.custos.estafetas)} />
              <Linha esquerda="Serviço de entregas contratado" direita={formatarKz(r.custos.servico_entregas)} />
              <Linha esquerda="Convida: descontos e saldo usados" direita={formatarKz(r.custos.convida_descontos)} />
              <Linha esquerda="Convida: ganhos dos padrinhos" direita={formatarKz(r.custos.convida_ganhos)} />
              <Linha esquerda="Compensações a clientes" direita={formatarKz(r.custos.compensacoes)} />
              <Linha esquerda="Pessoal (salários e Segurança Social)" direita={formatarKz(r.custos.pessoal ?? 0)} />
              <Linha esquerda="Despesas gerais" direita={formatarKz(r.custos.despesas_gerais)} />
              <Linha esquerda="Total" direita={formatarKz(r.custos.total)} forte />
            </Cartao>
            <Cartao estilo={{ borderWidth: 2, borderColor: r.resultado >= 0 ? cores.sucesso : cores.erro }}>
              <Linha esquerda={r.resultado >= 0 ? 'Lucro do mês' : 'Prejuízo do mês'} direita={formatarKz(Math.abs(r.resultado))} forte />
              {r.custo_por_entrega !== null && (
                <Linha esquerda="Custo das entregas por pedido" direita={formatarKz(r.custo_por_entrega)} />
              )}
            </Cartao>
            <Paragrafo suave>
              Os custos dos estafetas usam os valores definidos em «Pagamento dos estafetas» (ou o que já foi pago). Despesas gerais são as
              lançadas sem cozinha.
            </Paragrafo>
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
