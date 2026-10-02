import { Redirect } from 'expo-router';

import { ACarregar, Ecra, Paragrafo } from '@/components/ui';
import { textoRegras } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';

/** Texto das regras (4.13), com os valores de parametros */
export default function ComoFunciona() {
  const { carregado, parametros, ligada } = useSessao();
  // Aberto por link ou notificação: espera pelos interruptores antes de decidir
  if (!carregado) return <ACarregar />;
  if (!ligada('indicacao') || !parametros) return <Redirect href="/inicio" />;
  return (
    <Ecra>
      {textoRegras(parametros).map((frase) => (
        <Paragrafo key={frase}>{frase}</Paragrafo>
      ))}
    </Ecra>
  );
}
