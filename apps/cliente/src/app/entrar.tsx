import { useRouter } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { BlocoContactos, temContacto } from '@/components/BlocoContactos';
import { CodigoOtp } from '@/components/CodigoOtp';
import { Marca } from '@/components/Marca';
import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { CONTACTO_AJUDA } from '@/lib/empresa';
import { minutosSegundos, telefoneInternacional } from '@/lib/formatar';
import { supabase } from '@/lib/supabase';
import { cores, espaco } from '@/lib/tema';

// Sem rede, o supabase-js devolve um AuthRetryableFetchError com status 0 (o fetch
// falhou antes de chegar ao servidor). Um 5xx ou um limite de envio têm outro status.
function semLigacao(error: { name?: string; status?: number } | null): boolean {
  return error?.name === 'AuthRetryableFetchError' && error?.status === 0;
}

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
  const tentado = useRef(''); // último código já tentado (evita auto-submeter em ciclo)

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

  // Auto-entrar assim que o código tiver 6 dígitos (não repete o mesmo código já tentado)
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
    setAEnviar(false);
    if (error)
      setErro(
        semLigacao(error)
          ? 'Sem ligação à internet. Liga os dados móveis ou o Wi-Fi e tenta de novo.'
          : 'O código não está certo ou já expirou. Pede um novo código.',
      );
    else {
      // Fecha o código na lista do operador (OTP manual). O .then() é necessário: o builder do rpc
      // só envia o pedido quando é "consumido"; sem isto, nada é enviado. Falha não bloqueia o login.
      supabase.rpc('otp_confirmar').then(
        () => undefined,
        () => undefined,
      );
      router.replace('/');
    }
  }

  const expirado = restante <= 0;

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: cores.fundo }}>
      <View style={{ flex: 1, padding: espaco.xl, paddingTop: espaco.xl * 3, gap: espaco.l }}>
        <Marca grande />
        {!enviadoPara ? (
          <>
            <Paragrafo>Entra com o teu número de telefone. Enviamos-te um código para confirmar (por SMS ou WhatsApp).</Paragrafo>
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
            <Paragrafo suave>Só usamos o teu número para entrares e para te avisarmos dos teus pedidos.</Paragrafo>
            {erro && <Aviso tipo="erro">{erro}</Aviso>}
            <Botao titulo="Receber código" aoCarregar={pedirCodigo} aCarregar={aEnviar} />
            {temContacto(CONTACTO_AJUDA) && (
              <View style={{ marginTop: 'auto' }}>
                <BlocoContactos contacto={CONTACTO_AJUDA} titulo="Precisas de ajuda? Fala connosco" />
              </View>
            )}
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
