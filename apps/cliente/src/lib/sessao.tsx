import type { Session } from '@supabase/supabase-js';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
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

  // Só a leitura mais recente conta: uma leitura antiga (ex.: ainda sem sessão) que acabe depois
  // de uma mais nova não pode apagar o perfil acabado de carregar (era o que mandava quem já tinha
  // conta para «Criar conta» logo depois de escrever o código).
  const ultimaLeitura = useRef(0);

  const carregarDados = useCallback(async (s: Session | null) => {
    const minha = ++ultimaLeitura.current;
    const actual = () => minha === ultimaLeitura.current;
    if (!s) {
      setPerfil(null);
      setParametros(null);
      // Sem conta a app abre na mesma (Início do visitante): os interruptores vêm da leitura pública
      try {
        const r = await supabase.rpc('funcionalidades_publicas');
        if (actual()) setFuncionalidades(r.error ? {} : ((r.data as Funcionalidades | null) ?? {}));
      } catch {
        if (actual()) setFuncionalidades({});
      }
      return;
    }
    try {
      const [p, config] = await Promise.all([meuPerfil(), lerConfiguracao()]);
      if (!actual()) return;
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
      // A sessão de agora (não a deste render): voltar de ler o SMS a meio do login não a perde
      if (estado === 'active') void supabase.auth.getSession().then(({ data }) => carregarDados(data.session));
    });
    return () => sub.remove();
  }, [carregarDados]);

  const valor = useMemo<Sessao>(
    () => ({
      carregado,
      sessao,
      perfil,
      parametros,
      funcionalidades,
      ligada: (chave) => funcionalidades[chave] === true,
      // Sempre com a sessão de agora: quem chama pode ter sido desenhado antes do login
      actualizar: async () => {
        const { data } = await supabase.auth.getSession();
        await carregarDados(data.session);
      },
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
