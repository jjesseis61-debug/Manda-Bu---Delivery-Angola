import * as Location from 'expo-location';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text } from 'react-native';

import { MapaPin, type Coordenadas } from '@/components/MapaPin';
import { PesquisaMorada } from '@/components/PesquisaMorada';
import { Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { criarEndereco, lerEnderecos, lerZonas, pontosProximos, type PontoProximo } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { HA_MAPA } from '@/lib/mapaNativo';
import { pinoLongeDaZona } from '@/lib/pinZona';
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
  const [centrarEm, setCentrarEm] = useState<Coordenadas | undefined>(undefined);
  const [tipo, setTipo] = useState<'residencial' | 'empresa'>(empresa ? 'empresa' : 'residencial');
  const [zonas, setZonas] = useState<Zona[]>([]);
  const [zonaId, setZonaId] = useState<string>('');
  const [zonasLidas, setZonasLidas] = useState(false);
  const [referencia, setReferencia] = useState('');
  const [proximo, setProximo] = useState<PontoProximo | null>(null);
  const [usarProximo, setUsarProximo] = useState(false);
  const [primeiro, setPrimeiro] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aGuardar, setAGuardar] = useState(false);
  const [aLocalizar, setALocalizar] = useState(false);
  const [pesquisado, setPesquisado] = useState(false);
  // Pino longe do bairro: o cliente confirma que está certo (ex.: bairro novo sem centro rigoroso)
  const [pinoConfirmado, setPinoConfirmado] = useState<string | null>(null);

  useEffect(() => {
    lerZonas()
      .then((z) => {
        setZonas(z);
        setZonasLidas(true);
        // Com um só bairro, fica escolhido
        if (z.length === 1) setZonaId(z[0].id);
      })
      .catch((e) => setErro(mensagemErro(e)));
    lerEnderecos(perfil?.cliente_id)
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
    if (aLocalizar) return;
    setErro(null);
    setALocalizar(true);
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setErro(
          HA_MAPA
            ? 'Sem autorização para usar a localização. Marca o ponto no mapa.'
            : 'Sem autorização para usar a localização. Autoriza a localização nas definições do telemóvel para marcar o ponto.',
        );
        return;
      }
      // GPS desligado é a causa mais comum de "não responde": avisa em vez de ficar à espera
      const servicos = await Location.hasServicesEnabledAsync();
      if (!servicos) {
        setErro('A localização do telemóvel está desligada. Liga-a nas definições e tenta de novo, ou marca o ponto no mapa.');
        return;
      }
      // Posição já conhecida entra logo; uma leitura nova pode demorar vários segundos
      const conhecida = await Location.getLastKnownPositionAsync();
      if (conhecida) {
        const p = { latitude: conhecida.coords.latitude, longitude: conhecida.coords.longitude };
        setPonto(p);
        setCentrarEm(p);
        setMarcado(true);
      }
      const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      const p = { latitude: pos.coords.latitude, longitude: pos.coords.longitude };
      setPonto(p);
      setCentrarEm(p);
      setMarcado(true);
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setALocalizar(false);
    }
  }

  function escolherZona(id: string) {
    setZonaId(id);
    const z = zonas.find((x) => x.id === id);
    // Centra o mapa no bairro escolhido (se tiver centro) enquanto o cliente ainda não marcou o ponto
    if (z?.centro_lat != null && z.centro_lng != null && !marcado) {
      const p = { latitude: z.centro_lat, longitude: z.centro_lng };
      setPonto(p);
      setCentrarEm(p);
    }
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
  // O pino e o bairro têm de bater certo: senão a distância aos balcões e o estafeta vão ao sítio errado
  const longe = precisaZona && marcado && zonaId ? pinoLongeDaZona({ lat: ponto.latitude, lng: ponto.longitude }, zonaId, zonas) : null;
  const chaveLonge = `${zonaId}|${ponto.latitude.toFixed(4)}|${ponto.longitude.toFixed(4)}`;
  const longePorResolver = !!longe && pinoConfirmado !== chaveLonge;

  return (
    <Ecra>
      <PesquisaMorada
        zonas={zonas}
        perto={marcado ? { lat: ponto.latitude, lng: ponto.longitude } : undefined}
        aoEscolher={(r) => {
          const p = { latitude: r.lat, longitude: r.lng };
          setPonto(p);
          setCentrarEm(p);
          setMarcado(true);
          setPesquisado(true);
          // Escolheu um bairro onde entregamos: fica já seleccionado
          if (r.zonaId) setZonaId(r.zonaId);
        }}
      />
      {pesquisado && <Paragrafo suave>Confirma o pino: arrasta-o ou toca no mapa na porta exacta.</Paragrafo>}
      <MapaPin
        ponto={ponto}
        centrarEm={centrarEm}
        aoMudar={(p) => {
          setPonto(p);
          setMarcado(true);
        }}
      />
      <Botao
        titulo={aLocalizar ? 'A localizar…' : 'Usar a minha localização'}
        variante="secundario"
        aoCarregar={aMinhaLocalizacao}
        aCarregar={aLocalizar}
      />
      {!marcado && HA_MAPA && <Paragrafo suave>Toca no mapa para marcar o sítio exacto da entrega.</Paragrafo>}

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
          {zonasLidas && zonas.length === 0 ? (
            <Aviso>Ainda não entregamos em nenhum bairro. Volta a tentar mais tarde ou fala connosco.</Aviso>
          ) : (
            <Escolha opcoes={zonas.map((z) => ({ valor: z.id, rotulo: z.nome }))} valor={zonaId} aoMudar={escolherZona} />
          )}
          <Campo
            rotulo="Referência (ex.: prédio azul, 2.º andar, porta 12)"
            value={referencia}
            onChangeText={setReferencia}
            maxLength={200}
          />
        </>
      )}

      {longePorResolver && longe && (
        <Cartao>
          <Text style={{ fontSize: 15, fontWeight: '700' }}>
            {`📍 O pino está a ${Math.round(longe.km)} km do bairro ${longe.zona}${longe.maisPerto ? ` (fica mais perto de ${longe.maisPerto.nome})` : ''}.`}
          </Text>
          <Paragrafo suave>Onde é a entrega? Se registaste a morada a partir de outro sítio, o mapa pôs o pino onde estás agora.</Paragrafo>
          {longe.maisPerto && (
            <Botao titulo={`O bairro é ${longe.maisPerto.nome}`} variante="secundario" aoCarregar={() => setZonaId(longe.maisPerto!.id)} />
          )}
          <Botao
            titulo={`Pôr o pino em ${longe.zona}`}
            variante="secundario"
            aoCarregar={() => {
              const z = zonas.find((x) => x.id === zonaId);
              if (z?.centro_lat == null || z.centro_lng == null) return;
              const p = { latitude: z.centro_lat, longitude: z.centro_lng };
              setPonto(p);
              setCentrarEm(p);
              setMarcado(false);
            }}
          />
          <Botao titulo="Está certo assim" variante="texto" aoCarregar={() => setPinoConfirmado(chaveLonge)} />
        </Cartao>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao
        titulo="Guardar endereço"
        aoCarregar={guardar}
        aCarregar={aGuardar}
        desactivado={!marcado || longePorResolver || (precisaZona && (!zonaId || !referencia.trim()))}
      />
    </Ecra>
  );
}
