import { Redirect, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text } from 'react-native';

import { CampoConvite } from '@/components/CampoConvite';
import { ACarregar, Aviso, Botao, Campo, Cartao, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { descontoGarantido, ligarIndicacao, meuPerfil, registarCliente } from '@/lib/api';
import { lerCodigoPendente, limparCodigoPendente } from '@/lib/convite';
import { formatarKz, mensagemCodigo, mensagemErro, normalizarCodigo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';

/** Registo do cliente, com o campo do código de convite (C2) */
export default function Registo() {
  const router = useRouter();
  const { sessao, perfil, ligada, actualizar, parametros } = useSessao();
  // Código vindo de um link (prato ou convite): aparece aplicado e não se troca (é justo para quem
  // partilhou). Sem link, o campo fica livre. «Continuar sem convite» tira-o (sem pôr outro).
  const [doLink, setDoLink] = useState<string | null>(null);
  const [semConvite, setSemConvite] = useState(false);
  // O servidor recusou o código (inválido/expirado): só então se pode escrever outro
  const [recusado, setRecusado] = useState(false);
  const [outro, setOutro] = useState('');
  const [nome, setNome] = useState('');
  const [tipo, setTipo] = useState<'Particular' | 'Empresa'>('Particular');
  const [nif, setNif] = useState('');
  const [codigo, setCodigo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  // Antes de mostrar o formulário, confirma no servidor que a conta ainda não existe: quem já é
  // cliente nunca deve ver «Criar conta» (vai logo para onde ia)
  const [verificado, setVerificado] = useState(false);
  useEffect(() => {
    lerCodigoPendente().then((c) => {
      if (c) {
        setDoLink(c);
        setCodigo(c);
      }
    });
  }, []);
  useEffect(() => {
    if (!sessao || perfil) return;
    let vivo = true;
    meuPerfil()
      .then(async (p) => {
        if (p) await actualizar();
      })
      .catch(() => undefined)
      .finally(() => vivo && setVerificado(true));
    return () => {
      vivo = false;
    };
  }, [sessao, perfil, actualizar]);

  if (!sessao) return <Redirect href="/inicio" />;
  if (perfil && !aviso) return <Redirect href="/" />;
  if (!verificado) return <ACarregar />;

  /** A porta de entrada decide: o início ou, se veio de um link com o carrinho montado, o carrinho */
  const seguir = () => router.replace('/');

  async function criar() {
    setErro(null);
    const efectivo = doLink ? (semConvite ? '' : doLink) : codigo;
    const codigoNormalizado = efectivo.trim() ? normalizarCodigo(efectivo) : null;
    if (codigo.trim() && !codigoNormalizado) {
      setErro(mensagemCodigo('codigo_inexistente'));
      return;
    }
    setAEnviar(true);
    try {
      await registarCliente(nome, tipo, tipo === 'Empresa' ? nif : null);
      // «Continuar sem convite»: o código do link deixa de valer neste telemóvel
      if (semConvite) await limparCodigoPendente().catch(() => undefined);
      if (codigoNormalizado && ligada('indicacao')) {
        const resultado = await ligarIndicacao(codigoNormalizado);
        const novo = await meuPerfil();
        if (resultado === 'ok') {
          await limparCodigoPendente();
          const desconto = novo ? await descontoGarantido(novo.cliente_id) : null;
          setAviso(desconto ? `Código aceite: −${formatarKz(desconto)} no teu primeiro pedido.` : 'Código aceite.');
        } else {
          setRecusado(true);
          await limparCodigoPendente().catch(() => undefined);
          setAviso(`Conta criada. ${mensagemCodigo(resultado)} Podes continuar sem código.`);
        }
      }
      await actualizar();
      if (!codigoNormalizado || !ligada('indicacao')) seguir();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  /** Depois de o servidor recusar o código: tenta outro (só nesta situação o código se escreve à mão) */
  async function usarOutro() {
    const c = normalizarCodigo(outro);
    if (!c) {
      setErro(mensagemCodigo('codigo_inexistente'));
      return;
    }
    setErro(null);
    setAEnviar(true);
    try {
      const resultado = await ligarIndicacao(c);
      if (resultado === 'ok') {
        const novo = await meuPerfil();
        const desconto = novo ? await descontoGarantido(novo.cliente_id) : null;
        setRecusado(false);
        setAviso(desconto ? `Código aceite: −${formatarKz(desconto)} no teu primeiro pedido.` : 'Código aceite.');
      } else setErro(mensagemCodigo(resultado));
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  if (aviso) {
    return (
      <Ecra>
        <Aviso tipo={aviso.startsWith('Código aceite') ? 'sucesso' : 'aviso'}>{aviso}</Aviso>
        {recusado && (
          <>
            <CampoConvite rotulo="Outro código de convite (opcional)" valor={outro} aoMudar={setOutro} />
            {erro && <Aviso tipo="erro">{erro}</Aviso>}
            <Botao titulo="Usar este código" variante="secundario" aoCarregar={usarOutro} aCarregar={aEnviar} desactivado={!outro.trim()} />
          </>
        )}
        <Botao titulo="Continuar" aoCarregar={seguir} />
      </Ecra>
    );
  }

  return (
    <Ecra>
      <Paragrafo>Só falta o teu nome para começares a pedir.</Paragrafo>
      <Campo rotulo="Nome" placeholder="O teu nome" autoComplete="name" value={nome} onChangeText={setNome} />
      <Escolha
        opcoes={[
          { valor: 'Particular', rotulo: 'Particular' },
          { valor: 'Empresa', rotulo: 'Empresa' },
        ]}
        valor={tipo}
        aoMudar={setTipo}
      />
      {tipo === 'Empresa' && <Campo rotulo="NIF" value={nif} onChangeText={setNif} autoCapitalize="characters" />}
      {ligada('indicacao') && doLink && !semConvite && (
        <Cartao estilo={{ backgroundColor: cores.marcaClara }}>
          <Text style={{ color: cores.marca, fontWeight: '800', fontSize: 16 }}>🎁 Convite aplicado ✓</Text>
          <Text style={{ color: cores.texto }}>
            Código <Text style={{ fontWeight: '800' }}>{doLink}</Text>
            {parametros?.desconto_indicado
              ? ` · ganhas ${formatarKz(parametros.desconto_indicado)} no 1.º pedido${
                  parametros.desconto_subtotal_minimo ? ` (a partir de ${formatarKz(parametros.desconto_subtotal_minimo)})` : ''
                }.`
              : '.'}
          </Text>
          <Text accessibilityRole="button" onPress={() => setSemConvite(true)} style={{ color: cores.textoSuave, fontSize: 13, marginTop: 4 }}>
            Continuar sem convite
          </Text>
        </Cartao>
      )}
      {ligada('indicacao') && !doLink && (
        <>
          <Subtitulo>Tens um código de convite?</Subtitulo>
          <CampoConvite rotulo="Código (opcional)" valor={codigo} aoMudar={setCodigo} />
        </>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Criar conta" aoCarregar={criar} aCarregar={aEnviar} desactivado={!nome.trim()} />
    </Ecra>
  );
}
