import { Redirect } from 'expo-router';
import type { ReactNode } from 'react';

import { useSessao } from '@/lib/sessao';
import type { Funcionario, Permissao } from '@/lib/tipos';

import { ACarregar } from './ui';

/**
 * Só mostra o ecrã a quem tem pelo menos uma das permissões, ou a quem `permitir` aceita
 * (por exemplo, membros da cozinha no O8). O servidor volta a verificar.
 */
export function Guarda({
  permissoes,
  permitir,
  children,
}: {
  permissoes: Permissao[];
  permitir?: (f: Funcionario) => boolean;
  children: ReactNode;
}) {
  const { carregado, sessao, funcionario, pode } = useSessao();
  if (!carregado) return <ACarregar />;
  if (!sessao) return <Redirect href="/entrar" />;
  if (!funcionario) return <Redirect href="/sem-acesso" />;
  if (!permissoes.some(pode) && !permitir?.(funcionario)) return <Redirect href="/inicio" />;
  return <>{children}</>;
}
