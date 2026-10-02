import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type TextInputProps,
  type ViewStyle,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { cores, espaco, raio } from '@/lib/tema';

export function Ecra({ children, rolar = true }: { children: ReactNode; rolar?: boolean }) {
  return (
    <SafeAreaView style={estilos.ecra} edges={['bottom', 'left', 'right']}>
      {rolar ? (
        <ScrollView contentContainerStyle={estilos.conteudo} keyboardShouldPersistTaps="handled">
          {children}
        </ScrollView>
      ) : (
        <View style={[estilos.conteudo, { flex: 1 }]}>{children}</View>
      )}
    </SafeAreaView>
  );
}

export function Titulo({ children }: { children: ReactNode }) {
  return <Text style={estilos.titulo}>{children}</Text>;
}

export function Subtitulo({ children }: { children: ReactNode }) {
  return <Text style={estilos.subtitulo}>{children}</Text>;
}

export function Paragrafo({ children, suave = false }: { children: ReactNode; suave?: boolean }) {
  return <Text style={[estilos.paragrafo, suave && { color: cores.textoSuave }]}>{children}</Text>;
}

export function Cartao({ children, estilo }: { children: ReactNode; estilo?: ViewStyle }) {
  return <View style={[estilos.cartao, estilo]}>{children}</View>;
}

export function Linha({ esquerda, direita, forte = false }: { esquerda: ReactNode; direita: ReactNode; forte?: boolean }) {
  return (
    <View style={estilos.linha}>
      <Text style={[estilos.paragrafo, forte && estilos.forte]}>{esquerda}</Text>
      <Text style={[estilos.paragrafo, forte && estilos.forte]}>{direita}</Text>
    </View>
  );
}

type BotaoProps = {
  titulo: string;
  aoCarregar: () => void;
  variante?: 'principal' | 'secundario' | 'leve' | 'whatsapp' | 'texto';
  desactivado?: boolean;
  aCarregar?: boolean;
};

export function Botao({ titulo, aoCarregar, variante = 'principal', desactivado, aCarregar }: BotaoProps) {
  const fundo =
    variante === 'principal'
      ? cores.marca
      : variante === 'whatsapp'
        ? cores.whatsapp
        : variante === 'secundario'
          ? cores.fundoSuave
          : variante === 'leve'
            ? cores.marcaClara
            : 'transparent';
  const corTexto = variante === 'principal' || variante === 'whatsapp' ? '#fff' : cores.marca;
  return (
    <Pressable
      accessibilityRole="button"
      onPress={aoCarregar}
      disabled={desactivado || aCarregar}
      style={({ pressed }) => [
        estilos.botao,
        { backgroundColor: fundo, opacity: desactivado ? 0.45 : pressed ? 0.8 : 1 },
        variante === 'texto' && { paddingVertical: espaco.s },
      ]}>
      {aCarregar ? <ActivityIndicator color={corTexto} /> : <Text style={[estilos.botaoTexto, { color: corTexto }]}>{titulo}</Text>}
    </Pressable>
  );
}

export function Campo(props: TextInputProps & { rotulo: string }) {
  const { rotulo, style, ...resto } = props;
  return (
    <View style={{ marginBottom: espaco.m }}>
      <Text style={estilos.rotulo}>{rotulo}</Text>
      <TextInput placeholderTextColor={cores.textoSuave} style={[estilos.campo, style]} {...resto} />
    </View>
  );
}

export function Escolha<T extends string>({
  opcoes,
  valor,
  aoMudar,
}: {
  opcoes: { valor: T; rotulo: string }[];
  valor: T;
  aoMudar: (v: T) => void;
}) {
  return (
    <View style={estilos.escolha}>
      {opcoes.map((o) => (
        <Pressable
          key={o.valor}
          accessibilityRole="radio"
          accessibilityState={{ selected: o.valor === valor }}
          onPress={() => aoMudar(o.valor)}
          style={[estilos.opcao, o.valor === valor && estilos.opcaoActiva]}>
          <Text style={[estilos.opcaoTexto, o.valor === valor && { color: '#fff' }]}>{o.rotulo}</Text>
        </Pressable>
      ))}
    </View>
  );
}

export function Aviso({ children, tipo = 'aviso' }: { children: ReactNode; tipo?: 'aviso' | 'erro' | 'sucesso' }) {
  const fundo = tipo === 'erro' ? cores.erroFundo : tipo === 'sucesso' ? '#E6F4EA' : cores.avisoFundo;
  const cor = tipo === 'erro' ? cores.erro : tipo === 'sucesso' ? cores.sucesso : cores.aviso;
  // A cor não é o único sinal: ícone e barra lateral distinguem o aviso dos botões da marca.
  // No erro o texto fica escuro, para não se confundir com o vermelho das acções.
  const icone = tipo === 'erro' ? '⚠' : tipo === 'sucesso' ? '✓' : 'ℹ';
  return (
    <View
      accessibilityRole={tipo === 'erro' ? 'alert' : undefined}
      style={[estilos.aviso, { backgroundColor: fundo, borderLeftColor: cor }]}>
      <Text style={{ color: cor, fontSize: 15, fontWeight: '700' }}>{icone}</Text>
      <Text style={{ color: tipo === 'erro' ? cores.texto : cor, fontSize: 14, flex: 1 }}>{children}</Text>
    </View>
  );
}

export function ACarregar() {
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: espaco.xl }}>
      <ActivityIndicator color={cores.marca} />
    </View>
  );
}

export const estilos = StyleSheet.create({
  ecra: { flex: 1, backgroundColor: cores.fundo },
  conteudo: { padding: espaco.l, paddingBottom: espaco.xl * 2, gap: espaco.m },
  titulo: { fontSize: 24, fontWeight: '700', color: cores.texto },
  subtitulo: { fontSize: 17, fontWeight: '600', color: cores.texto, marginTop: espaco.s },
  paragrafo: { fontSize: 15, color: cores.texto, lineHeight: 21 },
  forte: { fontWeight: '700' },
  cartao: { backgroundColor: cores.fundoSuave, borderRadius: raio, padding: espaco.l, gap: espaco.s },
  linha: { flexDirection: 'row', justifyContent: 'space-between', gap: espaco.m },
  botao: { borderRadius: raio, paddingVertical: espaco.m + 2, paddingHorizontal: espaco.l, alignItems: 'center' },
  botaoTexto: { fontSize: 16, fontWeight: '600' },
  rotulo: { fontSize: 13, color: cores.textoSuave, marginBottom: espaco.xs },
  campo: {
    borderWidth: 1,
    borderColor: cores.contorno,
    borderRadius: raio,
    paddingHorizontal: espaco.m,
    paddingVertical: espaco.m,
    fontSize: 16,
    color: cores.texto,
    backgroundColor: '#fff',
  },
  escolha: { flexDirection: 'row', flexWrap: 'wrap', gap: espaco.s },
  opcao: { borderWidth: 1, borderColor: cores.marca, borderRadius: 20, paddingVertical: espaco.s, paddingHorizontal: espaco.l },
  opcaoActiva: { backgroundColor: cores.marca },
  opcaoTexto: { color: cores.marca, fontWeight: '600' },
  aviso: { borderRadius: raio, padding: espaco.m, borderLeftWidth: 4, flexDirection: 'row', gap: espaco.s },
});
