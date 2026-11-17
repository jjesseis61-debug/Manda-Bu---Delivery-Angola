import { Redirect, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';

import { ACarregar, Aviso, Botao, Campo, Ecra, Escolha, Paragrafo, Subtitulo } from '@/components/ui';
import { descontoGarantido, ligarIndicacao, meuPerfil, registarCliente } from '@/lib/api';
import { lerCodigoPendente, limparCodigoPendente } from '@/lib/convite';
import { formatarKz, mensagemCodigo, mensagemErro, normalizarCodigo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

/** Registo do cliente, com o campo do código de convite (C2) */
export default function Registo() {
  const router = useRouter();
  const { sessao, perfil, ligada, actualizar } = useSessao();
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
    lerCodigoPendente().then((c) => c && setCodigo(c));
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
    const codigoNormalizado = codigo.trim() ? normalizarCodigo(codigo) : null;
    if (codigo.trim() && !codigoNormalizado) {
      setErro(mensagemCodigo('codigo_inexistente'));
      return;
    }
    setAEnviar(true);
    try {
      await registarCliente(nome, tipo, tipo === 'Empresa' ? nif : null);
      if (codigoNormalizado && ligada('indicacao')) {
        const resultado = await ligarIndicacao(codigoNormalizado);
        const novo = await meuPerfil();
        if (resultado === 'ok') {
          await limparCodigoPendente();
          const desconto = novo ? await descontoGarantido(novo.cliente_id) : null;
          setAviso(desconto ? `Código aceite: −${formatarKz(desconto)} no teu primeiro pedido.` : 'Código aceite.');
        } else {
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

  if (aviso) {
    return (
      <Ecra>
        <Aviso tipo={aviso.startsWith('Código aceite') ? 'sucesso' : 'aviso'}>{aviso}</Aviso>
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
      {ligada('indicacao') && (
        <>
          <Subtitulo>Tens um código de convite?</Subtitulo>
          <Campo
            rotulo="Código (opcional)"
            placeholder="MB-1234"
            autoCapitalize="characters"
            autoCorrect={false}
            value={codigo}
            onChangeText={setCodigo}
          />
        </>
      )}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Criar conta" aoCarregar={criar} aCarregar={aEnviar} desactivado={!nome.trim()} />
    </Ecra>
  );
}
