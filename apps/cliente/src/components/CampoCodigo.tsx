import { useEffect, useState } from 'react';
import { View } from 'react-native';

import { descontoGarantido, ligarIndicacao } from '@/lib/api';
import { lerCodigoPendente, limparCodigoPendente } from '@/lib/convite';
import { formatarKz, mensagemCodigo, mensagemErro, normalizarCodigo } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

import { Aviso, Botao, Campo, Subtitulo } from './ui';

/**
 * C2. Campo "Tens um código de convite?" (registo e checkout do 1.º pedido).
 * Pré-preenchido pelo link de convite. Desaparece quando já há ligação ou o cliente já comprou.
 */
export function CampoCodigo({ aoLigar }: { aoLigar?: () => void }) {
  const { perfil, ligada, actualizar } = useSessao();
  const [codigo, setCodigo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aceite, setAceite] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  useEffect(() => {
    lerCodigoPendente().then((c) => c && setCodigo(c));
  }, []);

  if (!ligada('indicacao') || !perfil || perfil.tem_ligacao || !perfil.cliente_novo) {
    return aceite ? <Aviso tipo="sucesso">{aceite}</Aviso> : null;
  }

  async function usar() {
    const normalizado = normalizarCodigo(codigo);
    setErro(null);
    if (!normalizado) {
      setErro(mensagemCodigo('codigo_inexistente'));
      return;
    }
    setAEnviar(true);
    try {
      const resultado = await ligarIndicacao(normalizado);
      if (resultado !== 'ok') {
        setErro(mensagemCodigo(resultado));
        return;
      }
      await limparCodigoPendente();
      // O valor só aparece depois de o servidor confirmar a ligação
      const desconto = perfil ? await descontoGarantido(perfil.cliente_id) : null;
      setAceite(
        desconto
          ? `Código aceite: −${formatarKz(desconto)} no teu primeiro pedido.`
          : 'Código aceite.',
      );
      await actualizar();
      aoLigar?.();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setAEnviar(false);
    }
  }

  return (
    <View style={{ gap: 8 }}>
      <Subtitulo>Tens um código de convite?</Subtitulo>
      <Campo
        rotulo="Código"
        placeholder="MB-1234"
        autoCapitalize="characters"
        autoCorrect={false}
        value={codigo}
        onChangeText={setCodigo}
      />
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      <Botao titulo="Usar código" variante="secundario" aoCarregar={usar} aCarregar={aEnviar} desactivado={!codigo.trim()} />
    </View>
  );
}
