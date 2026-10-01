import { Redirect } from 'expo-router';
import type { ReactNode } from 'react';

import { useSessao } from '@/lib/sessao';
import type { Permissao } from '@/lib/tipos';

import { ACarregar } from './ui';

/** Só mostra o ecrã a quem tem pelo menos uma das permissões (o servidor volta a verificar) */
export function Guarda({ permissoes, children }: { permissoes: Permissao[]; children: ReactNode }) {
  const { carregado, sessao, funcionario, pode } = useSessao();
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!funcionario) return <Redirect href="/sem-acesso" />;
  if (!permissoes.some(pode)) return <Redirect href="/inicio" />;
  return <>{children}</>;
}
