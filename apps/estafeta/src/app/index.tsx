import { Redirect } from 'expo-router';

import { ACarregar } from '@/components/ui';
import { useSessao } from '@/lib/sessao';

/** Só entra quem é funcionário COM a permissão de estafeta (entregas.registar). */
export default function Entrada() {
  const { carregado, sessao, funcionario, pode } = useSessao();
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!funcionario || !pode('entregas.registar')) return <Redirect href="/sem-acesso" />;
  return <Redirect href="/inicio" />;
}
