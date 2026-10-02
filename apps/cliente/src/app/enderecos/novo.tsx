import * as Location from 'expo-location';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text } from 'react-native';

import { MapaPin, type Coordenadas } from '@/components/MapaPin';
import { Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarEndereco, lerEnderecos, lerZonas, pontosProximos, type PontoProximo } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import type { Zona } from '@/lib/tipos';

// Centro de Luanda, até o cliente marcar o ponto
const LUANDA: Coordenadas = { latitude: -8.8383, longitude: 13.2344 };

/** C11. Novo endereço: pin no mapa, tipo Casa/Trabalho, bairro (zona de entrega) e referência */
export default function NovoEndereco() {
  const router = useRouter();
  const { perfil } = useSessao();
  const empresa = perfil?.tipo === 'Empresa';
  const [ponto, setPonto] = useState<Coordenadas>(LUANDA);
  const [marcado, setMarcado] = useState(false);
  const [tipo, setTipo] = useState<'residencial' | 'empresa'>(empresa ? 'empresa' : 'residencial');
  const [zonas, setZonas] = useState<Zona[]>([]);
  const [zonaId, setZonaId] = useState<string>('');
  const [referencia, setReferencia] = useState('');
  const [proximo, setProximo] = useState<PontoProximo | null>(null);
  const [usarProximo, setUsarProximo] = useState(false);
  const [primeiro, setPrimeiro] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aGuardar, setAGuardar] = useState(false);

  useEffect(() => {
    lerZonas().then(setZonas).catch((e) => setErro(mensagemErro(e)));
    lerEnderecos()
      .then((e) => setPrimeiro(e.length === 0))
      .catch(() => undefined);
  }, []);

  // Sugere um ponto existente dentro do raio (sem mostrar a referência de pontos residenciais de outros)
  useEffect(() => {
    if (!marcado) return;
    setUsarProximo(false);
    pontosProximos(ponto.latitude, ponto.longitude, tipo)
      .then((lista) => setProximo(lista[0] ?? null))
      .catch(() => setProximo(null));
  }, [ponto, tipo, marcado]);

  async function aMinhaLocalizacao() {
    setErro(null);
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      setErro('Sem autorização para usar a localização. Marca o ponto no mapa.');
      return;
    }
    const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
    setPonto({ latitude: pos.coords.latitude, longitude: pos.coords.longitude });
    setMarcado(true);
  }

  async function guardar() {
    if (!perfil) return;
    setErro(null);
    setAGuardar(true);
    try {
      await criarEndereco({
        clienteId: perfil.cliente_id,
        nome: tipo === 'empresa' ? 'Trabalho' : 'Casa',
        principal: primeiro,
        pontoExistente: usarProximo && proximo ? proximo.ponto_entrega_id : null,
        novoPonto:
          usarProximo && proximo
            ? null
            : { tipo, lat: ponto.latitude, lng: ponto.longitude, zonaId, referencia: referencia.trim() },
      });
      router.back();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAGuardar(false);
    }
  }

  const precisaZona = !(usarProximo && proximo);

  return (
    <Ecra>
      <MapaPin
        ponto={ponto}
        aoMudar={(p) => {
          setPonto(p);
          setMarcado(true);
        }}
      />
      <Botao titulo="Usar a minha localização" variante="secundario" aoCarregar={aMinhaLocalizacao} />
      {!marcado && <Paragrafo suave>Toca no mapa ou arrasta o pin para o sítio exacto da entrega.</Paragrafo>}

      {!empresa && (
        <Escolha
          opcoes={[
            { valor: 'residencial', rotulo: 'Casa' },
            { valor: 'empresa', rotulo: 'Trabalho' },
          ]}
          valor={tipo}
          aoMudar={setTipo}
        />
      )}

      {proximo && (
        <Cartao>
          <Text style={{ fontSize: 15 }}>
            Já existe um ponto de entrega a {Math.round(proximo.distancia_m)} m daqui
            {proximo.referencia ? `: ${proximo.referencia}` : ''}. Usar o mesmo ponto evita entregas no sítio errado.
          </Text>
          <Escolha
            opcoes={[
              { valor: 'sim', rotulo: 'Usar este ponto' },
              { valor: 'nao', rotulo: 'Criar novo' },
            ]}
            valor={usarProximo ? 'sim' : 'nao'}
            aoMudar={(v) => setUsarProximo(v === 'sim')}
          />
        </Cartao>
      )}

      {precisaZona && (
        <>
          <Subtitulo>Bairro (zona de entrega)</Subtitulo>
          <Escolha opcoes={zonas.map((z) => ({ valor: z.id, rotulo: z.nome }))} valor={zonaId} aoMudar={setZonaId} />
          <Campo
            rotulo="Referência (ex.: prédio azul, 2.º andar, porta 12)"
            value={referencia}
            onChangeText={setReferencia}
            maxLength={200}
          />
        </>
      )}

      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao
        titulo="Guardar endereço"
        aoCarregar={guardar}
        aCarregar={aGuardar}
        desactivado={!marcado || (precisaZona && (!zonaId || !referencia.trim()))}
      />
    </Ecra>
  );
}
