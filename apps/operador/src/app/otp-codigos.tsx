import { useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Linking, Platform, Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Botao, Cartao, Ecra, Paragrafo } from '@/components/ui';
import { lerFuncionalidades, otpLimpar, otpMarcarEntregue, otpPendentes } from '@/lib/api';
import { mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { OtpPendente } from '@/lib/tipos';

/** Mensagem que o operador envia ao cliente com o código */
function mensagemCodigo(codigo: string): string {
  return `O seu código Manda Bué é ${codigo}. Válido por 10 minutos. Não partilhe com ninguém.`;
}

/** Tempo que falta até expirar, em "m:ss" (ou "expirado") */
function emFalta(expiraEm: string, agora: number): string {
  const seg = Math.round((new Date(expiraEm).getTime() - agora) / 1000);
  if (seg <= 0) return 'expirado';
  return `${Math.floor(seg / 60)}:${String(seg % 60).padStart(2, '0')}`;
}

/** "agora mesmo" / "há N min" desde um instante */
function haQuanto(iso: string | null, agora: number): string {
  if (!iso) return '';
  const seg = Math.max(0, Math.round((agora - new Date(iso).getTime()) / 1000));
  if (seg < 60) return 'agora mesmo';
  return `há ${Math.floor(seg / 60)} min`;
}

/** Códigos de login (OTP manual): o operador vê os códigos pendentes e entrega-os por WhatsApp/SMS. */
export default function OtpCodigos() {
  const [lista, setLista] = useState<OtpPendente[] | null>(null);
  const [ligado, setLigado] = useState<boolean | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [agora, setAgora] = useState(Date.now());
  const [ocupado, setOcupado] = useState<string | null>(null);

  const carregar = useCallback(() => {
    otpPendentes()
      .then(setLista)
      .catch((e) => setErro(mensagemErro(e)));
  }, []);

  useFocusEffect(
    useCallback(() => {
      let vivo = true;
      void otpLimpar().catch(() => undefined);
      lerFuncionalidades()
        .then((fs) => vivo && setLigado(fs.find((f) => f.chave === 'otp_manual')?.activa ?? false))
        .catch(() => undefined);
      carregar();
      // Recarrega os códigos a cada 8 s e o relógio a cada 1 s (contagem decrescente)
      const t1 = setInterval(carregar, 8000);
      const t2 = setInterval(() => setAgora(Date.now()), 1000);
      return () => {
        vivo = false;
        clearInterval(t1);
        clearInterval(t2);
      };
    }, [carregar]),
  );

  async function abrir(url: string, alternativa?: string) {
    try {
      if (alternativa && !(await Linking.canOpenURL(url).catch(() => false))) url = alternativa;
      await Linking.openURL(url);
    } catch (e) {
      setErro(mensagemErro(e));
    }
  }

  async function enviarWhatsapp(o: OtpPendente) {
    const digitos = o.telefone.replace(/\D/g, '');
    const texto = encodeURIComponent(mensagemCodigo(o.codigo ?? ''));
    await abrir(`whatsapp://send?phone=${digitos}&text=${texto}`, `https://wa.me/${digitos}?text=${texto}`);
  }

  async function enviarSms(o: OtpPendente) {
    const sep = Platform.OS === 'ios' ? '&' : '?';
    await abrir(`sms:${o.telefone}${sep}body=${encodeURIComponent(mensagemCodigo(o.codigo ?? ''))}`);
  }

  async function marcar(id: string) {
    setOcupado(id);
    setErro(null);
    try {
      await otpMarcarEntregue(id);
      carregar();
    } catch (e) {
      setErro(mensagemErro(e));
    } finally {
      setOcupado(null);
    }
  }

  return (
    <Guarda permissoes={['otp.entregar']}>
      <Ecra>
        <Paragrafo suave>Entrega o código ao cliente por WhatsApp ou SMS. Cada código serve uma vez e expira.</Paragrafo>
        {ligado === false && (
          <Aviso tipo="erro">O serviço de OTP manual está desligado — não chegam códigos novos. Liga em Parâmetros.</Aviso>
        )}
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!lista && !erro && <ACarregar />}
        {lista && lista.length === 0 && <Paragrafo suave>Sem códigos pendentes.</Paragrafo>}
        {lista?.map((o) => {
          if (o.estado === 'confirmado') {
            return (
              <Aviso key={o.id} tipo="sucesso">
                Login de {o.nome ?? 'cliente'} realizado · {haQuanto(o.confirmado_em, agora)}
              </Aviso>
            );
          }
          const falta = emFalta(o.expira_em, agora);
          return (
            <Cartao key={o.id}>
              <View style={{ gap: espaco.s }}>
                <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
                  <Text style={{ fontSize: 26, fontWeight: '800', letterSpacing: 2, color: cores.texto }}>{o.codigo}</Text>
                  <Text style={{ color: falta === 'expirado' ? cores.marca : cores.textoSuave }}>{falta === 'expirado' ? 'expirado' : `expira em ${falta}`}</Text>
                </View>
                <Text style={{ color: cores.textoSuave }}>{o.telefone}</Text>
                <View style={{ flexDirection: 'row', gap: espaco.s }}>
                  <View style={{ flex: 1 }}>
                    <Botao titulo="WhatsApp" variante="whatsapp" aoCarregar={() => enviarWhatsapp(o)} />
                  </View>
                  <View style={{ flex: 1 }}>
                    <Botao titulo="SMS" variante="secundario" aoCarregar={() => enviarSms(o)} />
                  </View>
                </View>
                <Botao titulo="Marcar como entregue" variante="texto" aCarregar={ocupado === o.id} aoCarregar={() => marcar(o.id)} />
              </View>
            </Cartao>
          );
        })}
      </Ecra>
    </Guarda>
  );
}
