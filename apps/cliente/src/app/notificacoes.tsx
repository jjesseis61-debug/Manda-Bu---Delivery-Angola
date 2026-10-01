import { Redirect, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { ACarregar, Aviso, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { alterarPreferenciasNotificacao, lerPreferenciasNotificacao } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { cores } from '@/lib/tema';
import type { PreferenciasNotificacao } from '@/lib/tipos';

/** C14. Definições de notificações: desligar N5 (lembrete do almoço) e N7 (destaques) */
export default function Notificacoes() {
  const { ligada, perfil } = useSessao();
  const [prefs, setPrefs] = useState<PreferenciasNotificacao | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const visivel = ligada('indicacao') || ligada('destaques');

  useFocusEffect(
    useCallback(() => {
      if (!perfil || !visivel) return;
      lerPreferenciasNotificacao(perfil.cliente_id)
        .then(setPrefs)
        .catch((e) => setErro(mensagemErro(e)));
    }, [perfil, visivel]),
  );

  if (!visivel) return <Redirect href="/conta" />;
  if (!prefs && !erro) return <ACarregar />;

  async function mudar(chave: keyof PreferenciasNotificacao, valor: boolean) {
    if (!perfil || !prefs) return;
    const anterior = prefs;
    setPrefs({ ...prefs, [chave]: valor });
    setErro(null);
    try {
      await alterarPreferenciasNotificacao(perfil.cliente_id, { [chave]: valor });
    } catch (e) {
      setPrefs(anterior);
      setErro(mensagemErro(e));
    }
  }

  return (
    <Ecra>
      {erro && <Aviso tipo="erro">{erro}</Aviso>}
      {prefs && (
        <Cartao>
          {ligada('indicacao') && (
            <Interruptor
              rotulo="Lembrete do almoço"
              detalhe="Nos dias úteis, antes do almoço, com o prato do dia. No máximo 2 por semana."
              valor={prefs.lembrete_almoco}
              aoMudar={(v) => mudar('lembrete_almoco', v)}
            />
          )}
          {ligada('destaques') && (
            <Interruptor
              rotulo="Destaques"
              detalhe="Uma vez por semana, quando estás perto do top do mês."
              valor={prefs.destaques}
              aoMudar={(v) => mudar('destaques', v)}
            />
          )}
        </Cartao>
      )}
      <Paragrafo suave>Os avisos sobre os teus pedidos, ganhos e pagamentos chegam sempre.</Paragrafo>
    </Ecra>
  );
}

function Interruptor({
  rotulo,
  detalhe,
  valor,
  aoMudar,
}: {
  rotulo: string;
  detalhe: string;
  valor: boolean;
  aoMudar: (v: boolean) => void;
}) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 6 }}>
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 15, fontWeight: '600' }}>{rotulo}</Text>
        <Text style={{ fontSize: 13, color: cores.textoSuave }}>{detalhe}</Text>
      </View>
      <Switch value={valor} onValueChange={aoMudar} trackColor={{ true: cores.marca, false: cores.linha }} />
    </View>
  );
}
