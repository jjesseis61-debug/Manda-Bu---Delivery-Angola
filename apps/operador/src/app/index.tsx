import { Redirect } from 'expo-router';

import { ACarregar } from '@/components/ui';
import { useSessao } from '@/lib/sessao';

export default function Entrada() {
  const { carregado, sessao, funcionario } = useSessao();
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!funcionario) return <Redirect href="/sem-acesso" />;
  return <Redirect href="/inicio" />;
}
