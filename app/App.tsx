import { StatusBar } from 'expo-status-bar';
import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { supabase } from './lib/supabase';

type Estado = 'a verificar' | 'ligado' | 'erro';

export default function App() {
  const [estado, setEstado] = useState<Estado>('a verificar');
  const [detalhe, setDetalhe] = useState('');

  useEffect(() => {
    supabase.auth
      .getSession()
      .then(({ error }) => {
        if (error) throw error;
        setEstado('ligado');
      })
      .catch((e: Error) => {
        setEstado('erro');
        setDetalhe(e.message);
      });
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.titulo}>Manda Bué — Delivery Angola</Text>
      <Text>Supabase: {estado}</Text>
      {detalhe ? <Text style={styles.erro}>{detalhe}</Text> : null}
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  titulo: {
    fontSize: 20,
    fontWeight: '600',
  },
  erro: {
    color: '#b00020',
  },
});
