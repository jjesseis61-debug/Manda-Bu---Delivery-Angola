import { digitosCodigo } from '@/lib/formatar';

import { Campo } from './ui';

/**
 * Campo do código de convite com o «MB» fixo (como o +244 do telefone): escreve-se só o número
 * (4812), com o teclado numérico. Colar o código inteiro (MB4812 ou o antigo MB-4812) também dá.
 */
export function CampoConvite({
  rotulo,
  valor,
  aoMudar,
}: {
  rotulo: string;
  /** Só os dígitos */
  valor: string;
  aoMudar: (digitos: string) => void;
}) {
  return (
    <Campo
      rotulo={rotulo}
      prefixo="MB"
      placeholder="1234"
      keyboardType="number-pad"
      autoCorrect={false}
      maxLength={9}
      value={valor}
      onChangeText={(t) => aoMudar(digitosCodigo(t))}
    />
  );
}
