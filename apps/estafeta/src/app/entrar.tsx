import { useRouter } from 'expo-router';
import { useState, useEffect } from 'react';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Marca } from '@/components/Marca';
import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { telefoneInternacional } from '@/lib/formatar';
import { supabase } from '@/lib/supabase';
import { cores, espaco } from '@/lib/tema';

const VALIDADE_SEG = 600; // 10 min — igual ao OTP Expiry do servidor
const ESPERA_REENVIO_SEG = 60;

// Sem rede, o supabase-js devolve um AuthRetryableFetchError com status 0 (o fetch falhou antes de
// chegar ao servidor). Um 5xx ou um limite de envio têm outro status.
function semLigacao(error: { name?: string; status?: number } | null): boolean {
  return error?.name === 'AuthRetryableFetchError' && error?.status === 0;
}

const mmss = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;

/** Entrar com o número de telefone e o código recebido por SMS (Supabase Auth) — app do estafeta */
export default function Entrar() {
  const router = useRouter();
  const [telefone, setTelefone] = useState('');
  const [codigo, setCodigo] = useState('');
  const [enviadoPara, setEnviadoPara] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);
  const [restante, setRestante] = useState(0);
  const [espera, setEspera] = useState(0);

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

  async function confirmar() {
    if (!enviadoPara) return;
    setErro(null);
    setAEnviar(true);
    const { error } = await supabase.auth.verifyOtp({ phone: enviadoPara, token: codigo.trim(), type: 'sms' });
    setAEnviar(false);
    if (error)
      setErro(
        semLigacao(error)
          ? 'Sem ligação à internet. Liga os dados móveis ou o Wi-Fi e tenta de novo.'
          : 'O código não está certo ou já expirou. Pede um novo código.',
      );
    else router.replace('/');
  }

  const expirado = restante <= 0;

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }}>
      <View style={{ flex: 1, padding: espaco.xl, justifyContent: 'center', gap: espaco.l }}>
        <Marca grande />
        {!enviadoPara ? (
          <>
            <Paragrafo>Entra com o teu número de telefone. Enviamos-te um código para confirmar.</Paragrafo>
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
            {erro && <Aviso tipo="erro">{erro}</Aviso>}
            <Botao titulo="Receber código" aoCarregar={pedirCodigo} aCarregar={aEnviar} />
          </>
        ) : (
          <>
            <Paragrafo>Escreve o código que enviámos para {enviadoPara}.</Paragrafo>
            <Campo
              rotulo="Código"
              placeholder="123456"
              keyboardType="number-pad"
              autoComplete="sms-otp"
              textContentType="oneTimeCode"
              maxLength={6}
              value={codigo}
              onChangeText={(t) => setCodigo(t.replace(/\D/g, ''))}
            />
            <Paragrafo suave>
              {expirado ? 'O código expirou. Pede um novo código.' : `O código é válido por ${mmss(restante)}.`}
            </Paragrafo>
            {erro && <Aviso tipo="erro">{erro}</Aviso>}
            <Botao titulo="Entrar" aoCarregar={confirmar} aCarregar={aEnviar} desactivado={codigo.trim().length < 6} />
            <Botao
              titulo={espera > 0 && !expirado ? `Reenviar em ${espera}s` : 'Reenviar código'}
              variante="texto"
              desactivado={espera > 0 && !expirado}
              aCarregar={aEnviar}
              aoCarregar={() => enviarPara(enviadoPara)}
            />
            <Botao titulo="Mudar o número" variante="texto" aoCarregar={() => setEnviadoPara(null)} />
          </>
        )}
      </View>
    </SafeAreaView>
  );
}
