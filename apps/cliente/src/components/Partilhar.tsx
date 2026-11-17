import { useState } from 'react';
import { Modal, Pressable, Text, View } from 'react-native';

import { LoginNecessario } from '@/components/LoginNecessario';
import { Botao, Paragrafo } from '@/components/ui';
import { formatarKz } from '@/lib/formatar';
import { convitePartilhaDe, partilharPrato } from '@/lib/partilha';
import { guardarPartilhaPendente, marcarAvisoPartilha, podeMostrarAvisoPartilha, type PartilhaPendente } from '@/lib/partilhaPendente';
import { useSessao } from '@/lib/sessao';
import { cores, espaco } from '@/lib/tema';
import { lerRegrasConvida } from '@/lib/visitante';

type Ganhos = { amigo: number; tu: number; aPartirDoSegundo: boolean };

/**
 * Partilhar um prato. Com conta: abre o WhatsApp com o código de convite. Sem conta: antes de
 * partilhar, a folha «🎁 Partilha e ganha» (no máximo 1× por 24 h) propõe entrar para o link levar
 * o código — «Entrar e partilhar» (depois de entrar a partilha continua sozinha) ou «Partilhar sem
 * código». Nunca bloqueia a partilha.
 */
export function usePartilhar() {
  const { perfil, parametros, ligada } = useSessao();
  const [aviso, setAviso] = useState<(PartilhaPendente & Ganhos) | null>(null);
  const [login, setLogin] = useState<PartilhaPendente | null>(null);
  const convite = convitePartilhaDe(perfil, parametros, ligada('indicacao'));

  async function partilhar(nome: string, id: string) {
    if (perfil) return partilharPrato(nome, id, convite);
    // Visitante: o aviso só com o Convida ligado (regras públicas) e no máximo uma vez por dia
    const [regras, pode] = await Promise.all([lerRegrasConvida().catch(() => null), podeMostrarAvisoPartilha()]);
    if (!regras || regras.desconto_indicado <= 0 || !pode) return partilharPrato(nome, id, null);
    await marcarAvisoPartilha();
    setAviso({ nome, id, amigo: regras.desconto_indicado, tu: regras.ganho_por_pedido, aPartirDoSegundo: !regras.comissao_primeiro_pedido });
  }

  const folhas = (
    <>
      <Modal visible={aviso !== null} transparent animationType="slide" onRequestClose={() => setAviso(null)}>
        <Pressable accessibilityLabel="Fechar" onPress={() => setAviso(null)} style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.45)' }} />
        {aviso && (
          <View
            style={{ backgroundColor: cores.fundo, borderTopLeftRadius: 20, borderTopRightRadius: 20, padding: espaco.l, paddingBottom: espaco.xl, gap: espaco.m }}>
            <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: espaco.m }}>
              <Text style={{ flex: 1, fontSize: 20, fontWeight: '800', color: cores.texto }}>🎁 Partilha e ganha</Text>
              <Pressable accessibilityRole="button" accessibilityLabel="Fechar" onPress={() => setAviso(null)} hitSlop={12}>
                <Text style={{ fontSize: 22, color: cores.textoSuave }}>✕</Text>
              </Pressable>
            </View>
            <Paragrafo>
              Entra na tua conta para o link levar o teu código: o teu amigo ganha{' '}
              <Text style={{ fontWeight: '800' }}>{formatarKz(aviso.amigo)}</Text> no 1.º pedido e tu ganhas{' '}
              <Text style={{ fontWeight: '800' }}>{formatarKz(aviso.tu)}</Text> por cada pedido dele
              {aviso.aPartirDoSegundo ? ' (a partir do 2.º)' : ''}.
            </Paragrafo>
            <Botao
              titulo="Entrar e partilhar"
              aoCarregar={async () => {
                const p = { nome: aviso.nome, id: aviso.id };
                setAviso(null);
                await guardarPartilhaPendente(p);
                setLogin(p);
              }}
            />
            <Botao
              titulo="Partilhar sem código"
              variante="texto"
              aoCarregar={() => {
                const p = aviso;
                setAviso(null);
                void partilharPrato(p.nome, p.id, null);
              }}
            />
            <Text style={{ color: cores.textoSuave, fontSize: 12, textAlign: 'center' }}>Só usamos o teu número para os teus pedidos.</Text>
          </View>
        )}
      </Modal>
      <LoginNecessario
        visivel={login !== null}
        titulo="Entra para partilhar com o teu código"
        motivo="Recebes um código por SMS ou WhatsApp para confirmar. Depois, a partilha abre sozinha com o teu código."
        aoFechar={() => setLogin(null)}
      />
    </>
  );

  return { partilhar, convite, folhas };
}
