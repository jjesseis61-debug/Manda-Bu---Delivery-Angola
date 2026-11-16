import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Titulo } from '@/components/ui';
import { condominioPeloCodigo, pedirEntradaCondominio, type CondominioLink } from '@/lib/condominio';
import { formatarData, mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { espaco } from '@/lib/tema';

/** Link de inscrição no condomínio (…/condominio/CODIGO): o morador pede para entrar na lista */
export default function EntrarCondominio() {
  const { codigo } = useLocalSearchParams<{ codigo: string }>();
  const router = useRouter();
  const { carregado, sessao, perfil } = useSessao();
  const [info, setInfo] = useState<CondominioLink | null | undefined>(undefined);
  const [bloco, setBloco] = useState('');
  const [casa, setCasa] = useState('');
  const [resultado, setResultado] = useState<'activo' | 'pendente' | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    if (!perfil) return;
    condominioPeloCodigo(String(codigo ?? ''))
      .then(setInfo)
      .catch((e) => {
        setErro(mensagemErro(e));
        setInfo(null);
      });
  }, [codigo, perfil]);

  async function pedir() {
    setErro(null);
    setOcupado(true);
    try {
      setResultado(await pedirEntradaCondominio(String(codigo ?? ''), bloco, casa));
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(false);
    }
  }

  if (!carregado) return <ACarregar />;
  if (!sessao || !perfil) {
    return (
      <Ecra>
        <Titulo>Cozinha do condomínio</Titulo>
        <Paragrafo>Para entrares na lista de moradores, primeiro entra na tua conta (ou cria uma) e volta a abrir o link.</Paragrafo>
        <Botao titulo="Entrar ou criar conta" aoCarregar={() => router.replace('/entrar')} />
      </Ecra>
    );
  }
  if (info === undefined) return <ACarregar />;

  const estado = resultado ?? info?.meu_estado ?? null;
  return (
    <Ecra>
      <Titulo>🏘️ {info?.nome ?? 'Condomínio'}</Titulo>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {info === null && !erro && <Aviso>Este link de condomínio já não é válido.</Aviso>}
      {info && (
        <Cartao>
          <Paragrafo>
            A {info.cozinha} cozinha só para os moradores da lista. Quando estiveres no condomínio, ela aparece na app e podes pedir
            para a tua casa.
          </Paragrafo>
          {estado === 'activo' && <Aviso tipo="sucesso">Já estás na lista. Abre a app no condomínio e pede à vontade.</Aviso>}
          {estado === 'pendente' && <Aviso>O teu pedido está à espera de aprovação da cozinha. Avisamos-te quando entrares.</Aviso>}
          {!estado && !info.lista_aberta && <Aviso>A lista está fechada (completa ou fora do prazo).</Aviso>}
          {!estado && info.lista_aberta && (
            <View style={{ gap: espaco.s }}>
              <Paragrafo suave>
                {info.vagas_livres} {info.vagas_livres === 1 ? 'vaga livre' : 'vagas livres'}
                {info.inscricoes_ate ? ` · inscrições até ${formatarData(info.inscricoes_ate)}` : ''}
                {info.aprovacao_manual ? ' · a cozinha aprova cada morador' : ''}
              </Paragrafo>
              <Campo rotulo="Bloco / prédio" value={bloco} onChangeText={setBloco} maxLength={40} />
              <Campo rotulo="Casa / apartamento" value={casa} onChangeText={setCasa} maxLength={40} />
              <Botao
                titulo="Pedir para entrar"
                desactivado={(bloco + casa).trim().length === 0}
                aCarregar={ocupado}
                aoCarregar={pedir}
              />
            </View>
          )}
        </Cartao>
      )}
      <Botao titulo="Ir para o início" variante="texto" aoCarregar={() => router.replace('/inicio')} />
    </Ecra>
  );
}
