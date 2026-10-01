import { Redirect } from 'expo-router';

import { Ecra, Paragrafo } from '@/components/ui';
import { textoRegras } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

/** Texto das regras (4.13), com os valores de parametros */
export default function ComoFunciona() {
  const { parametros, ligada } = useSessao();
  if (!ligada('indicacao') || !parametros) return <Redirect href="/inicio" />;
  return (
    <Ecra>
      {textoRegras(parametros).map((frase) => (
        <Paragrafo key={frase}>{frase}</Paragrafo>
      ))}
    </Ecra>
  );
}
