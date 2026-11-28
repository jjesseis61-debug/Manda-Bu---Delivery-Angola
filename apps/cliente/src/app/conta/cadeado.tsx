import { useEffect, useState } from 'react';
import { Switch, Text, View } from 'react-native';

import { Aviso, Botao, Campo, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { biometriaDisponivel, cadeadoSuportado, definirBiometria, definirPin, removerCadeado, usaBiometria, validarPin } from '@/lib/cadeado';
import { useCadeado } from '@/lib/cadeadoContexto';
import { cores, espaco } from '@/lib/tema';

/** Ligar / mudar / desligar o cadeado (código e biometria) deste telemóvel */
export default function GerirCadeado() {
  const { activo, recarregar, confirmar } = useCadeado();
  const [temBio, setTemBio] = useState(false);
  const [bio, setBio] = useState(false);
  const [criar, setCriar] = useState(false);
  const [pin, setPin] = useState('');
  const [pin2, setPin2] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    void biometriaDisponivel().then(setTemBio);
    void usaBiometria().then(setBio);
  }, [activo]);

  if (!cadeadoSuportado()) {
    return (
      <Ecra>
        <Paragrafo>O cadeado com código só existe na app instalada no telemóvel (Android/iPhone).</Paragrafo>
      </Ecra>
    );
  }

  const erroPin = pin.length >= 4 ? validarPin(pin) : null;
  const diferentes = pin2.length > 0 && pin2 !== pin;

  async function guardar() {
    const e = validarPin(pin);
    if (e) return setErro(e);
    if (pin !== pin2) return setErro('Os dois códigos não são iguais.');
    setOcupado(true);
    setErro(null);
    try {
      // Mudar o código também exige o código actual (ou a biometria)
      if (activo && !(await confirmar('Confirma o código actual'))) return;
      await definirPin(pin, temBio && bio);
      await recarregar();
      setCriar(false);
      setPin('');
      setPin2('');
      setAviso(activo ? 'Código alterado.' : 'Cadeado ligado. A app passa a pedir o código ao abrir e antes de levantamentos.');
    } catch (x) {
      setErro((x as Error).message || 'Não foi possível guardar.');
    } finally {
      setOcupado(false);
    }
  }

  async function desligar() {
    if (!(await confirmar('Confirma para desligar o cadeado'))) return;
    await removerCadeado();
    await recarregar();
    setAviso('Cadeado desligado.');
  }

  async function mudarBio(v: boolean) {
    if (activo && !(await confirmar('Confirma o código'))) return;
    setBio(v);
    if (activo) await definirBiometria(v);
  }

  return (
    <Ecra>
      <Paragrafo>
        Protege o Manda Bué com um código só teu. Se alguém pegar no teu telemóvel desbloqueado, não consegue ver as tuas
        moradas, fazer pedidos, levantar o saldo nem apagar a conta.
      </Paragrafo>
      {aviso && <Aviso tipo="sucesso">{aviso}</Aviso>}
      {erro && <Aviso tipo="erro">{erro}</Aviso>}

      <Cartao estilo={{ gap: espaco.s }}>
        <Subtitulo>{activo ? '🔒 Cadeado ligado' : 'Cadeado desligado'}</Subtitulo>
        <Paragrafo suave>
          {activo
            ? 'Pede o código ao abrir a app, ao voltar depois de 1 minuto fora, e antes de levantar o saldo ou apagar a conta.'
            : 'Liga para a app pedir um código (4 a 6 números) ao abrir.'}
        </Paragrafo>
        {temBio && (
          <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: espaco.s }}>
            <Text style={{ color: cores.texto, flex: 1 }}>Usar também a impressão digital / rosto</Text>
            <Switch accessibilityLabel="Usar biometria" value={bio} onValueChange={(v) => void mudarBio(v)} />
          </View>
        )}
        {!criar && (
          <Botao
            titulo={activo ? 'Mudar o código' : 'Ligar o cadeado'}
            variante={activo ? 'secundario' : 'principal'}
            aoCarregar={() => {
              setAviso(null);
              setCriar(true);
            }}
          />
        )}
        {criar && (
          <View style={{ gap: espaco.s }}>
            <Campo
              rotulo={activo ? 'Novo código' : 'Código (4 a 6 números)'}
              value={pin}
              onChangeText={(t) => setPin(t.replace(/\D/g, '').slice(0, 6))}
              keyboardType="number-pad"
              secureTextEntry
              maxLength={6}
            />
            {erroPin && <Text style={{ color: cores.erro }}>{erroPin}</Text>}
            <Campo
              rotulo="Repete o código"
              value={pin2}
              onChangeText={(t) => setPin2(t.replace(/\D/g, '').slice(0, 6))}
              keyboardType="number-pad"
              secureTextEntry
              maxLength={6}
            />
            {diferentes && <Text style={{ color: cores.erro }}>Os dois códigos não são iguais.</Text>}
            <Botao titulo="Guardar código" aCarregar={ocupado} desactivado={!!erroPin || pin.length < 4 || pin !== pin2} aoCarregar={guardar} />
            <Botao titulo="Cancelar" variante="texto" aoCarregar={() => setCriar(false)} />
          </View>
        )}
        {activo && !criar && <Botao titulo="Desligar o cadeado" variante="texto" aoCarregar={desligar} />}
      </Cartao>
      <Paragrafo suave>
        Esqueceste o código? No ecrã do cadeado toca em «Esqueci o código»: sais e entras outra vez com o SMS. O cadeado é só
        deste telemóvel e nunca é enviado para o servidor.
      </Paragrafo>
    </Ecra>
  );
}
