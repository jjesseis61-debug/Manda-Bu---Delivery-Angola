import type { Session } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { AppState } from 'react-native';

import { lerConfiguracao, meuPerfil } from './api';
import { supabase } from './supabase';
import type { ChaveFuncionalidade, Funcionalidades, Parametros, Perfil } from './tipos';

type Sessao = {
  carregado: boolean;
  sessao: Session | null;
  perfil: Perfil | null;
  parametros: Parametros | null;
  funcionalidades: Funcionalidades;
  /** Interruptor ligado? Uma funcionalidade desligada não mostra ecrãs, botões nem notificações */
  ligada: (chave: ChaveFuncionalidade) => boolean;
  actualizar: () => Promise<void>;
  sair: () => Promise<void>;
};

const Contexto = createContext<Sessao | null>(null);

export function SessaoProvider({ children, aoSair }: { children: ReactNode; aoSair?: () => Promise<void> }) {
  const [sessao, setSessao] = useState<Session | null>(null);
  const [perfil, setPerfil] = useState<Perfil | null>(null);
  const [parametros, setParametros] = useState<Parametros | null>(null);
  const [funcionalidades, setFuncionalidades] = useState<Funcionalidades>({});
  const [carregado, setCarregado] = useState(false);

  const carregarDados = useCallback(async (s: Session | null) => {
    if (!s) {
      setPerfil(null);
      setParametros(null);
      setFuncionalidades({});
      return;
    }
    try {
      const [p, config] = await Promise.all([meuPerfil(), lerConfiguracao()]);
      setPerfil(p);
      setParametros(config.parametros);
      setFuncionalidades(config.funcionalidades);
    } catch {
      // Sem rede: mantém o que já tinha; o próximo regresso à app volta a tentar
    }
  }, []);

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      setSessao(data.session);
      await carregarDados(data.session);
      setCarregado(true);
    });
    const { data } = supabase.auth.onAuthStateChange((_evento, nova) => {
      setSessao(nova);
      void carregarDados(nova);
    });
    return () => data.subscription.unsubscribe();
  }, [carregarDados]);

  // Interruptores e parâmetros: ao arrancar e sempre que a app volta ao primeiro plano
  useEffect(() => {
    const sub = AppState.addEventListener('change', (estado) => {
      if (estado === 'active') void carregarDados(sessao);
    });
    return () => sub.remove();
  }, [sessao, carregarDados]);

  const valor = useMemo<Sessao>(
    () => ({
      carregado,
      sessao,
      perfil,
      parametros,
      funcionalidades,
      ligada: (chave) => funcionalidades[chave] === true,
      actualizar: () => carregarDados(sessao),
      sair: async () => {
        if (aoSair) await aoSair().catch(() => undefined);
        await supabase.auth.signOut();
      },
    }),
    [carregado, sessao, perfil, parametros, funcionalidades, carregarDados, aoSair],
  );

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useSessao(): Sessao {
  const s = useContext(Contexto);
  if (!s) throw new Error('useSessao fora de SessaoProvider');
  return s;
}
