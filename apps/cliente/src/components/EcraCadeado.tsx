import { useCallback, useEffect, useState } from 'react';
import { Modal, Text, TextInput, View } from 'react-native';

import { Confirmar } from '@/components/Confirmar';
import { Marca } from '@/components/Marca';
import { Aviso, Botao } from '@/components/ui';
import { estadoFalhas, pedirBiometria, removerCadeado, tamanhoPin, usaBiometria, verificarPin } from '@/lib/cadeado';
import { useCadeado } from '@/lib/cadeadoContexto';
import { useSessao } from '@/lib/sessao';
import { cores, espaco, raio } from '@/lib/tema';

function textoEspera(ms: number): string {
  const s = Math.ceil(ms / 1000);
  return s >= 60 ? `${Math.ceil(s / 60)} min` : `${s} s`;
}

/** Teclado do código + biometria. Usado ao abrir a app e antes de acções sensíveis. */
function Verificador({ titulo, aoPassar, aoCancelar }: { titulo: string; aoPassar: () => void; aoCancelar?: () => void }) {
  const { sair } = useSessao();
  const [pin, setPin] = useState('');
  const [tamanho, setTamanho] = useState<number | null>(null);
  const [bio, setBio] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [esgotado, setEsgotado] = useState(false);
  const [esquecer, setEsquecer] = useState(false);

  const tentarBiometria = useCallback(async () => {
    if (await pedirBiometria(titulo)) aoPassar();
  }, [titulo, aoPassar]);

  useEffect(() => {
    (async () => {
      setTamanho(await tamanhoPin());
      const f = await estadoFalhas();
      if (f.esgotado) setEsgotado(true);
      else if (f.esperaMs > 0) setErro(`Muitas tentativas. Espera ${textoEspera(f.esperaMs)}.`);
      const b = await usaBiometria();
      setBio(b);
      if (b && !f.esgotado) void tentarBiometria();
    })();
  }, [tentarBiometria]);

  async function verificar(valor: string) {
    const r = await verificarPin(valor);
    setPin('');
    if (r.ok) {
      setErro(null);
      aoPassar();
      return;
    }
    if (r.esgotado) setEsgotado(true);
    else if (r.esperaMs > 0) setErro(`Código errado. Espera ${textoEspera(r.esperaMs)} para tentar outra vez.`);
    else setErro(`Código errado (${r.falhas} de 10 tentativas).`);
  }

  function mudar(t: string) {
    const so = t.replace(/\D/g, '').slice(0, 6);
    setPin(so);
    if (tamanho && so.length === tamanho) void verificar(so);
  }

  async function esqueci() {
    setEsquecer(false);
    await removerCadeado();
    await sair();
  }

  return (
    <View style={{ flex: 1, backgroundColor: cores.fundo, justifyContent: 'center', padding: espaco.xl, gap: espaco.m }}>
      <View style={{ alignItems: 'center', marginBottom: espaco.l }}>
        <Marca grande />
      </View>
      <Text style={{ fontSize: 20, fontWeight: '700', color: cores.texto, textAlign: 'center' }}>{titulo}</Text>
      {esgotado ? (
        <Aviso tipo="erro">Demasiadas tentativas erradas. Para tua segurança, entra outra vez com o código por SMS.</Aviso>
      ) : (
        <>
          <TextInput
            accessibilityLabel="Código"
            value={pin}
            onChangeText={mudar}
            keyboardType="number-pad"
            secureTextEntry
            autoFocus={!bio}
            maxLength={6}
            textAlign="center"
            style={{
              borderWidth: 1,
              borderColor: cores.contorno,
              borderRadius: raio,
              fontSize: 28,
              letterSpacing: 12,
              paddingVertical: espaco.m,
              color: cores.texto,
            }}
          />
          {!tamanho && <Botao titulo="Entrar" desactivado={pin.length < 4} aoCarregar={() => verificar(pin)} />}
          {erro && <Aviso tipo="erro">{erro}</Aviso>}
          {bio && <Botao titulo="Usar impressão digital / rosto" variante="secundario" aoCarregar={tentarBiometria} />}
        </>
      )}
      {aoCancelar && <Botao titulo="Cancelar" variante="texto" aoCarregar={aoCancelar} />}
      <Botao titulo="Esqueci o código" variante="texto" aoCarregar={() => setEsquecer(true)} />
      <Confirmar
        visivel={esquecer}
        titulo="Esqueceste o código?"
        mensagem="Vais sair da conta neste telemóvel e entrar outra vez com o código por SMS. O cadeado fica desligado; podes voltar a ligá-lo em Conta."
        textoConfirmar="Sair e entrar por SMS"
        aoConfirmar={esqueci}
        aoCancelar={() => setEsquecer(false)}
      />
    </View>
  );
}

/** Tapa a app quando está bloqueada e mostra o verificador das acções sensíveis */
export function EcraCadeado() {
  const { estado, desbloquear, pedido } = useCadeado();
  return (
    <>
      <Modal visible={estado !== 'aberto'} animationType="none" onRequestClose={() => undefined} statusBarTranslucent>
        {estado === 'bloqueado' ? (
          <Verificador titulo="Introduz o teu código" aoPassar={desbloquear} />
        ) : (
          <View style={{ flex: 1, backgroundColor: cores.fundo }} />
        )}
      </Modal>
      <Modal
        visible={estado === 'aberto' && pedido !== null}
        animationType="slide"
        onRequestClose={() => pedido?.resolver(false)}>
        {pedido && (
          <Verificador titulo={pedido.motivo} aoPassar={() => pedido.resolver(true)} aoCancelar={() => pedido.resolver(false)} />
        )}
      </Modal>
    </>
  );
}
