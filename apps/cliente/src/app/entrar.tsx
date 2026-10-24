import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Marca } from '@/components/Marca';
import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { minutosSegundos, telefoneInternacional } from '@/lib/formatar';
import { supabase } from '@/lib/supabase';
import { cores, espaco } from '@/lib/tema';

const VALIDADE_SEG = 600; // 10 min — igual ao OTP Expiry do servidor
const ESPERA_REENVIO_SEG = 60;

/** Entrar com o número de telefone e o código recebido por SMS (Supabase Auth) */
export default function Entrar() {
  const router = useRouter();
  const [telefone, setTelefone] = useState('');
  const [codigo, setCodigo] = useState('');
  const [enviadoPara, setEnviadoPara] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);
  const [restante, setRestante] = useState(0); // segundos até o código expirar
  const [espera, setEspera] = useState(0); // segundos até poder reenviar

  // Relógio: desconta a validade e a espera de reenvio a cada segundo
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
      setErro('Não conseguimos enviar o código. Tenta outra vez dentro de um minuto.');
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
    if (error) setErro('O código não está certo ou já expirou. Pede um novo código.');
    else router.replace('/');
  }

  const expirado = restante <= 0;

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }}>
      <View style={{ flex: 1, padding: espaco.xl, justifyContent: 'center', gap: espaco.l }}>
        <Marca grande />
        {!enviadoPara ? (
          <>
            <Paragrafo>Entra com o teu número de telefone. Enviamos um código por SMS.</Paragrafo>
            <Campo
              rotulo="Telefone"
              placeholder="923 456 789"
              keyboardType="phone-pad"
              autoComplete="tel"
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
              rotulo="Código do SMS"
              placeholder="123456"
              keyboardType="number-pad"
              autoComplete="sms-otp"
              textContentType="oneTimeCode"
              value={codigo}
              onChangeText={setCodigo}
            />
            <Paragrafo suave>
              {expirado ? 'O código expirou. Pede um novo código.' : `O código é válido por ${minutosSegundos(restante)}.`}
            </Paragrafo>
            {erro && <Aviso tipo="erro">{erro}</Aviso>}
            <Botao titulo="Entrar" aoCarregar={confirmar} aCarregar={aEnviar} desactivado={codigo.trim().length < 4} />
            <Botao
              titulo={espera > 0 && !expirado ? `Reenviar em ${espera}s` : 'Reenviar código'}
              variante="secundario"
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
