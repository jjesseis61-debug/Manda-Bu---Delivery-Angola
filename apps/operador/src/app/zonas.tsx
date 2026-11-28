import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Text, View } from 'react-native';

import { CapturarPonto } from '@/components/CapturarPonto';
import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { apagarZonaEntrega, guardarZonaEntrega, lerZonasEntrega } from '@/lib/api';
import { formatarKz, mensagemErro, textoGratisZona } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { ZonaEntrega } from '@/lib/tipos';

type Gratis = 'geral' | 'nunca' | 'propria';
type ZonaEditada = {
  id?: string;
  nome: string;
  taxa: string;
  tipo: 'Própria' | 'Terceirizada';
  lat: string;
  lng: string;
  gratis: Gratis;
  gratisValor: string;
};

const coordenada = (t: string, limite: number): number | null => {
  const n = Number(t.replace(',', '.'));
  return t.trim() !== '' && Number.isFinite(n) && Math.abs(n) <= limite ? n : null;
};

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

  const valido =
    edicao !== null &&
    edicao.nome.trim().length >= 2 &&
    /^\d+$/.test(edicao.taxa) &&
    (edicao.gratis !== 'propria' || (/^\d+$/.test(edicao.gratisValor) && Number(edicao.gratisValor) > 0));

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
                <Text style={{ color: cores.textoSuave }}>{textoGratisZona(z.entrega_gratis_acima)}</Text>
              </View>
              <Text style={{ fontWeight: '700' }}>{formatarKz(z.taxa)}</Text>
            </View>
            <Botao
              titulo="Editar"
              variante="texto"
              aoCarregar={() =>
                setEdicao({
                  id: z.id,
                  nome: z.nome,
                  taxa: String(z.taxa),
                  tipo: z.tipo ?? 'Própria',
                  lat: z.centro_lat != null ? String(z.centro_lat) : '',
                  lng: z.centro_lng != null ? String(z.centro_lng) : '',
                  gratis: z.entrega_gratis_acima === null ? 'geral' : z.entrega_gratis_acima === 0 ? 'nunca' : 'propria',
                  gratisValor: z.entrega_gratis_acima ? String(z.entrega_gratis_acima) : '',
                })
              }
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
            <Subtitulo>Entrega grátis nesta zona</Subtitulo>
            <Paragrafo suave>Conta o valor do pedido depois dos descontos, sem a taxa de entrega.</Paragrafo>
            <Escolha
              opcoes={[
                { valor: 'geral' as Gratis, rotulo: 'Valor geral' },
                { valor: 'propria' as Gratis, rotulo: 'Valor próprio' },
                { valor: 'nunca' as Gratis, rotulo: 'Nunca' },
              ]}
              valor={edicao.gratis}
              aoMudar={(v) => setEdicao({ ...edicao, gratis: v })}
            />
            {edicao.gratis === 'propria' && (
              <Campo
                rotulo="Entrega grátis a partir de (Kz)"
                value={edicao.gratisValor}
                keyboardType="number-pad"
                onChangeText={(t) => setEdicao({ ...edicao, gratisValor: t.replace(/\D/g, '') })}
              />
            )}
            <Subtitulo>Centro da zona (opcional)</Subtitulo>
            <Paragrafo suave>
              Marca um ponto de referência do bairro. Centra o mapa do cliente aqui e ajuda o GPS; não define a fronteira do
              bairro.
            </Paragrafo>
            <CapturarPonto lat={edicao.lat} lng={edicao.lng} aoMudar={(la, lo) => setEdicao({ ...edicao, lat: la, lng: lo })} />
            <Botao
              titulo="Guardar zona"
              desactivado={!valido}
              aCarregar={ocupado}
              aoCarregar={() => {
                const cLat = coordenada(edicao.lat, 90);
                const cLng = coordenada(edicao.lng, 180);
                // O centro é tudo-ou-nada: só guarda com os dois válidos (a BD exige o par completo)
                const completo = cLat !== null && cLng !== null;
                return correr(
                  () =>
                    guardarZonaEntrega({
                      id: edicao.id,
                      nome: edicao.nome.trim(),
                      taxa: Number(edicao.taxa),
                      tipo: edicao.tipo,
                      centro_lat: completo ? cLat : null,
                      centro_lng: completo ? cLng : null,
                      entrega_gratis_acima:
                        edicao.gratis === 'geral' ? null : edicao.gratis === 'nunca' ? 0 : Number(edicao.gratisValor),
                    }),
                  'Zona guardada.',
                );
              }}
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
          <Botao titulo="Nova zona de entrega" aoCarregar={() => setEdicao({ nome: '', taxa: '', tipo: 'Própria', lat: '', lng: '', gratis: 'geral', gratisValor: '' })} />
        )}
      </Ecra>
    </Guarda>
  );
}
