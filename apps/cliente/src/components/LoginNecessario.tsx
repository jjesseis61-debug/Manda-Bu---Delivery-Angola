import { usePathname, useRouter, type Href } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { KeyboardAvoidingView, Modal, Platform, Pressable, Text, View } from 'react-native';

import { CodigoOtp } from '@/components/CodigoOtp';
import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { meuPerfil } from '@/lib/api';
import { minutosSegundos, telefoneInternacional } from '@/lib/formatar';
import { useSessao } from '@/lib/sessao';
import { supabase } from '@/lib/supabase';
import { cores, espaco } from '@/lib/tema';
import { guardarDestino, type Destino } from '@/lib/visitante';

const VALIDADE_SEG = 600; // 10 min — igual ao OTP Expiry do servidor
const ESPERA_REENVIO_SEG = 60;

// Sem rede, o supabase-js devolve um AuthRetryableFetchError com status 0
function semLigacao(error: { name?: string; status?: number } | null): boolean {
  return error?.name === 'AuthRetryableFetchError' && error?.status === 0;
}

/**
 * Folha de login por baixo (modelo Meesho): aparece quando o visitante toca numa função pessoal
 * (Pedir, avisos, pedidos, conta, Convida…). O ecrã fica visível por trás; o número e o código
 * escrevem-se aqui mesmo. Quem já tem conta fica onde estava (ou vai para `destino`); quem é novo
 * segue para o registo (só o nome) e depois para `destino`. ✕ / «Agora não» fecha sem castigo.
 */
export function LoginNecessario({
  visivel,
  motivo,
  destino,
  aoFechar,
  titulo = 'Entra na tua conta',
  nota = 'Só usamos o teu número para os teus pedidos.',
}: {
  visivel: boolean;
  motivo: string;
  destino: Destino;
  aoFechar: () => void;
  titulo?: string;
  /** Garantia por baixo do campo (privacidade; no «Pedir» também «Pagas na entrega») */
  nota?: string;
}) {
  const router = useRouter();
  const aqui = usePathname();
  const { actualizar } = useSessao();
  const [telefone, setTelefone] = useState('');
  const [codigo, setCodigo] = useState('');
  const [enviadoPara, setEnviadoPara] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);
  const [restante, setRestante] = useState(0);
  const [espera, setEspera] = useState(0);
  const tentado = useRef('');

  // Ao reabrir, começa do princípio
  useEffect(() => {
    if (!visivel) {
      setCodigo('');
      setEnviadoPara(null);
      setErro(null);
      tentado.current = '';
    }
  }, [visivel]);

  useEffect(() => {
    if (!enviadoPara) return;
    const id = setInterval(() => {
      setRestante((s) => Math.max(0, s - 1));
      setEspera((s) => Math.max(0, s - 1));
    }, 1000);
    return () => clearInterval(id);
  }, [enviadoPara]);

  async function enviarPara(numero: string) {
    setErro(null);
    setAEnviar(true);
    const { error } = await supabase.auth.signInWithOtp({ phone: numero });
    setAEnviar(false);
    if (error) {
      setErro(
        semLigacao(error)
          ? 'Sem ligação à internet. Liga os dados móveis ou o Wi-Fi e tenta de novo.'
          : 'Não conseguimos enviar o código. Tenta outra vez dentro de um minuto.',
      );
      return;
    }
    setEnviadoPara(numero);
    setCodigo('');
    setRestante(VALIDADE_SEG);
    setEspera(ESPERA_REENVIO_SEG);
  }

  async function pedirCodigo() {
    const numero = telefoneInternacional(telefone);
    if (!numero) {
      setErro('Escreve um número angolano com 9 dígitos (ex.: 923 456 789).');
      return;
    }
    await enviarPara(numero);
  }

  // Auto-entrar com os 6 dígitos (não repete o mesmo código já tentado)
  useEffect(() => {
    if (enviadoPara && codigo.length === 6 && !aEnviar && tentado.current !== codigo) {
      tentado.current = codigo;
      void confirmar();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [codigo, enviadoPara, aEnviar]);

  async function confirmar() {
    if (!enviadoPara) return;
    setErro(null);
    setAEnviar(true);
    const { error } = await supabase.auth.verifyOtp({ phone: enviadoPara, token: codigo.trim(), type: 'sms' });
    if (error) {
      setAEnviar(false);
      setErro(
        semLigacao(error)
          ? 'Sem ligação à internet. Liga os dados móveis ou o Wi-Fi e tenta de novo.'
          : 'O código não está certo ou já expirou. Pede um novo código.',
      );
      return;
    }
    // Fecha o código na lista do operador (OTP manual); falhar não bloqueia o login
    supabase.rpc('otp_confirmar').then(
      () => undefined,
      () => undefined,
    );
    const perfil = await meuPerfil().catch(() => null);
    setAEnviar(false);
    aoFechar();
    if (!perfil) {
      // Cliente novo: só falta o nome (o registo já traz o código de convite); depois segue para o destino
      await guardarDestino(destino);
      router.replace('/registo');
      return;
    }
    await actualizar().catch(() => undefined);
    // Já tinha conta: fica onde estava (o ecrã passa a mostrar a versão com conta) ou vai ao destino
    if (destino !== aqui) router.push(destino as Href);
  }

  const expirado = restante <= 0;

  return (
    <Modal visible={visivel} transparent animationType="slide" onRequestClose={aoFechar}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }}>
        {/* Fundo escurecido: tocar fora fecha (o ecrã de onde veio continua por trás) */}
        <Pressable accessibilityLabel="Fechar" onPress={aoFechar} style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.45)' }} />
        <View
          style={{
            backgroundColor: cores.fundo,
            borderTopLeftRadius: 20,
            borderTopRightRadius: 20,
            padding: espaco.l,
            paddingBottom: espaco.xl,
            gap: espaco.m,
          }}>
          <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: espaco.m }}>
            <Text style={{ flex: 1, fontSize: 20, fontWeight: '800', color: cores.texto }}>{titulo}</Text>
            <Pressable accessibilityRole="button" accessibilityLabel="Fechar" onPress={aoFechar} hitSlop={12}>
              <Text style={{ fontSize: 22, color: cores.textoSuave }}>✕</Text>
            </Pressable>
          </View>
          <Paragrafo suave>{motivo}</Paragrafo>
          {!enviadoPara ? (
            <>
              <Campo
                rotulo="Telefone"
                prefixo="+244"
                placeholder="923 456 789"
                keyboardType="phone-pad"
                autoComplete="tel"
                maxLength={11}
                value={telefone}
                onChangeText={setTelefone}
              />
              <Text style={{ color: cores.textoSuave, fontSize: 13, marginTop: -espaco.xs }}>{nota}</Text>
              {erro && <Aviso tipo="erro">{erro}</Aviso>}
              <Botao titulo="Receber código" aoCarregar={pedirCodigo} aCarregar={aEnviar} />
            </>
          ) : (
            <>
              <Paragrafo>Escreve o código que enviámos para {enviadoPara}.</Paragrafo>
              <CodigoOtp valor={codigo} aoMudar={setCodigo} />
              <Paragrafo suave>
                {expirado ? 'O código expirou. Pede um novo código.' : `O código é válido por ${minutosSegundos(restante)}.`}
              </Paragrafo>
              {erro && <Aviso tipo="erro">{erro}</Aviso>}
              <Botao titulo="Entrar" aoCarregar={confirmar} aCarregar={aEnviar} desactivado={codigo.trim().length < 6} />
              <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                <Botao
                  titulo={espera > 0 && !expirado ? `Reenviar em ${espera}s` : 'Reenviar código'}
                  variante="texto"
                  desactivado={espera > 0 && !expirado}
                  aCarregar={aEnviar}
                  aoCarregar={() => enviarPara(enviadoPara)}
                />
                <Botao titulo="Mudar o número" variante="texto" aoCarregar={() => setEnviadoPara(null)} />
              </View>
            </>
          )}
          <Text style={{ color: cores.textoSuave, fontSize: 12, textAlign: 'center' }}>
            Ao continuar, aceitas a{' '}
            <Text
              style={{ color: cores.marca, fontWeight: '700' }}
              onPress={() => {
                aoFechar();
                router.push('/politica-privacidade');
              }}>
              Política de privacidade
            </Text>
            .
          </Text>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}
