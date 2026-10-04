import { useRouter } from 'expo-router';
import { useState } from 'react';
import { View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Marca } from '@/components/Marca';
import { Aviso, Botao, Campo, Paragrafo } from '@/components/ui';
import { telefoneInternacional } from '@/lib/formatar';
import { supabase } from '@/lib/supabase';
import { cores, espaco } from '@/lib/tema';

/** Entrar com o número de telefone e o código recebido por SMS (Supabase Auth) */
export default function Entrar() {
  const router = useRouter();
  const [telefone, setTelefone] = useState('');
  const [codigo, setCodigo] = useState('');
  const [enviadoPara, setEnviadoPara] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aEnviar, setAEnviar] = useState(false);

  async function pedirCodigo() {
    setErro(null);
    const numero = telefoneInternacional(telefone);
    if (!numero) {
      setErro('Escreve um número angolano com 9 dígitos (ex.: 923 456 789).');
      return;
    }
    setAEnviar(true);
    const { error } = await supabase.auth.signInWithOtp({ phone: numero });
    setAEnviar(false);
    if (error) setErro('Não conseguimos enviar o SMS. Tenta outra vez dentro de um minuto.');
    else setEnviadoPara(numero);
  }

  async function confirmar() {
    if (!enviadoPara) return;
    setErro(null);
    setAEnviar(true);
    const { error } = await supabase.auth.verifyOtp({ phone: enviadoPara, token: codigo.trim(), type: 'sms' });
    setAEnviar(false);
    if (error) setErro('O código não está certo ou já expirou. Pede um novo: chega em segundos.');
    else router.replace('/');
  }

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
            {erro && <Aviso tipo="erro">{erro}</Aviso>}
            <Botao titulo="Entrar" aoCarregar={confirmar} aCarregar={aEnviar} desactivado={codigo.trim().length < 4} />
            <Botao titulo="Mudar o número" variante="texto" aoCarregar={() => setEnviadoPara(null)} />
          </>
        )}
      </View>
    </SafeAreaView>
  );
}
