import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { apagarZonaEntrega, guardarZonaEntrega, lerZonasEntrega } from '@/lib/api';
import { formatarKz, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { ZonaEntrega } from '@/lib/tipos';

type ZonaEditada = { id?: string; nome: string; taxa: string; tipo: 'Própria' | 'Terceirizada' };

/** Zonas de entrega (bairros): sem pelo menos uma, os clientes não conseguem guardar endereços */
export default function Zonas() {
  const [zonas, setZonas] = useState<ZonaEntrega[] | null>(null);
  const [edicao, setEdicao] = useState<ZonaEditada | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const carregar = useCallback(() => {
    lerZonasEntrega()
      .then(setZonas)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);
  useFocusEffect(carregar);

  async function correr(f: () => Promise<void>, mensagem: string) {
    setErro(null);
    setSucesso(null);
    setOcupado(true);
    try {
      await f();
      setEdicao(null);
      setSucesso(mensagem);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  const valido = edicao !== null && edicao.nome.trim().length >= 2 && /^\d+$/.test(edicao.taxa);

  return (
    <Guarda permissoes={['plataforma.parametros']}>
      <Ecra>
        <Paragrafo suave>
          O cliente escolhe o bairro ao guardar um endereço e a taxa de entrega soma ao pedido. Sem zonas, ninguém consegue
          guardar endereços.
        </Paragrafo>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {sucesso && <Aviso tipo="sucesso">{sucesso}</Aviso>}
        {zonas === null && !erro && <ACarregar />}
        {zonas?.length === 0 && <Aviso>Ainda não há zonas de entrega. Cria a primeira para os clientes poderem guardar endereços.</Aviso>}
        {zonas?.map((z) => (
          <Cartao key={z.id}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: espaco.s }}>
              <View style={{ flex: 1 }}>
                <Text style={{ fontWeight: '700', fontSize: 16 }}>{z.nome}</Text>
                <Text style={{ color: cores.textoSuave }}>{z.tipo === 'Terceirizada' ? 'Entrega por parceiro' : 'Entrega própria'}</Text>
              </View>
              <Text style={{ fontWeight: '700' }}>{formatarKz(z.taxa)}</Text>
            </View>
            <Botao
              titulo="Editar"
              variante="texto"
              aoCarregar={() => setEdicao({ id: z.id, nome: z.nome, taxa: String(z.taxa), tipo: z.tipo ?? 'Própria' })}
            />
          </Cartao>
        ))}

        {edicao ? (
          <Cartao>
            <Subtitulo>{edicao.id ? 'Editar zona' : 'Nova zona'}</Subtitulo>
            <Campo rotulo="Bairro (ex.: Talatona, Kilamba, Maianga)" value={edicao.nome} onChangeText={(t) => setEdicao({ ...edicao, nome: t })} />
            <Campo
              rotulo="Taxa de entrega (Kz)"
              value={edicao.taxa}
              keyboardType="number-pad"
              onChangeText={(t) => setEdicao({ ...edicao, taxa: t.replace(/\D/g, '') })}
            />
            <Escolha
              opcoes={[
                { valor: 'Própria', rotulo: 'Entrega própria' },
                { valor: 'Terceirizada', rotulo: 'Por parceiro' },
              ]}
              valor={edicao.tipo}
              aoMudar={(v) => setEdicao({ ...edicao, tipo: v })}
            />
            <Botao
              titulo="Guardar zona"
              desactivado={!valido}
              aCarregar={ocupado}
              aoCarregar={() =>
                correr(
                  () => guardarZonaEntrega({ id: edicao.id, nome: edicao.nome.trim(), taxa: Number(edicao.taxa), tipo: edicao.tipo }),
                  'Zona guardada.',
                )
              }
            />
            {edicao.id && (
              <Botao
                titulo="Apagar zona"
                variante="texto"
                desactivado={ocupado}
                aoCarregar={() => correr(() => apagarZonaEntrega(edicao.id as string), 'Zona apagada.')}
              />
            )}
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setEdicao(null)} />
          </Cartao>
        ) : (
          <Botao titulo="Nova zona de entrega" aoCarregar={() => setEdicao({ nome: '', taxa: '', tipo: 'Própria' })} />
        )}
      </Ecra>
    </Guarda>
  );
}
