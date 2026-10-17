import { useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Text, View } from 'react-native';

import { Guarda } from '@/components/Guarda';
import { ACarregar, Aviso, Cartao, Ecra, Paragrafo, Subtitulo } from '@/components/ui';
import { auditoriaCardapio } from '@/lib/api';
import { formatarData, mensagemErro } from '@/lib/formatar';
import { cores, espaco } from '@/lib/tema';
import type { AuditoriaCardapio } from '@/lib/tipos';

// O que o funcionário vê em vez do nome técnico da tabela/campo
const TIPO: Record<string, string> = {
  cardapio: 'Prato',
  cozinhas: 'Perfil da cozinha',
  cozinhas_localizacao: 'Morada',
  opcoes_grupos: 'Grupo de opções',
  opcoes: 'Opção',
};
const CAMPO: Record<string, string> = {
  nome: 'Nome',
  descricao: 'Descrição',
  categoria: 'Categoria',
  preco: 'Preço',
  preco_extra: 'Preço extra',
  disponivel: 'Disponível',
  do_dia: 'Prato do dia',
  ordem: 'Ordem',
  foto_url: 'Foto',
  doses_dia: 'Doses do dia',
  visivel_online: 'Visível online',
  historia: 'História',
  estado: 'Estado',
  responsavel: 'Responsável',
  consentimento_publico: 'Perfil público autorizado',
  telefone_publico: 'Telefone',
  whatsapp_publico: 'WhatsApp',
  horario_publico: 'Horário',
  etiqueta: 'Etiqueta',
  obrigatorio: 'Obrigatório',
  minimo: 'Mínimo',
  maximo: 'Máximo',
  morada: 'Morada',
  referencia: 'Referência',
  latitude: 'Latitude',
  longitude: 'Longitude',
};

function rotuloCampo(c: string): string {
  return CAMPO[c] ?? c.replace(/_/g, ' ');
}

function valorLegivel(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  if (typeof v === 'boolean') return v ? 'Sim' : 'Não';
  if (typeof v === 'string' && /^https?:\/\//.test(v)) return '(foto)';
  if (typeof v === 'string' && v.length > 60) return `${v.slice(0, 60)}…`;
  return String(v);
}

// Um diff de edição tem a forma { campo: { de, para } }; um registo novo é a linha inteira.
function ehDiff(m: Record<string, unknown>): boolean {
  const vs = Object.values(m);
  return vs.length > 0 && vs.every((v) => typeof v === 'object' && v !== null && 'de' in v && 'para' in v);
}

function Mudancas({ acao, mudou }: { acao: string; mudou: Record<string, unknown> | null }) {
  if (acao.endsWith('_criada')) return <Text style={{ color: cores.textoSuave }}>Criado</Text>;
  if (!mudou || Object.keys(mudou).length === 0) return <Text style={{ color: cores.textoSuave }}>Alterado</Text>;
  if (!ehDiff(mudou)) return <Text style={{ color: cores.textoSuave }}>Alterado</Text>;
  return (
    <View style={{ gap: espaco.xs }}>
      {Object.entries(mudou).map(([campo, dp]) => {
        const { de, para } = dp as { de: unknown; para: unknown };
        return (
          <Text key={campo} style={{ color: cores.texto }}>
            <Text style={{ fontWeight: '600' }}>{rotuloCampo(campo)}: </Text>
            {valorLegivel(de)} → {valorLegivel(para)}
          </Text>
        );
      })}
    </View>
  );
}

/** Auditoria do cardápio por cozinha: quem alterou o quê (pratos, perfil, morada, opções) e quando. */
export default function HistoricoCardapio() {
  const { cozinha } = useLocalSearchParams<{ cozinha: string }>();
  const [linhas, setLinhas] = useState<AuditoriaCardapio[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    if (cozinha) auditoriaCardapio(cozinha).then(setLinhas, (e) => setErro(mensagemErro(e)));
  }, [cozinha]);

  return (
    <Guarda permissoes={['auditoria.ver']}>
      <Ecra>
        {erro && <Aviso tipo="erro">{erro}</Aviso>}
        {!linhas && !erro && <ACarregar />}
        {linhas && (
          <>
            <Subtitulo>Alterações ao cardápio</Subtitulo>
            <Paragrafo suave>Cada alteração a pratos, perfil, morada ou opções fica registada: quem a fez (e a sua função), quando e o que mudou.</Paragrafo>
            {linhas.length === 0 && <Paragrafo suave>Ainda não há alterações registadas nesta cozinha.</Paragrafo>}
            {linhas.map((l, i) => (
              <Cartao key={i}>
                <View style={{ gap: espaco.xs, borderLeftWidth: 3, borderLeftColor: cores.marca, paddingLeft: espaco.s }}>
                  <Text style={{ color: cores.textoSuave }}>{formatarData(l.quando, true)}</Text>
                  <Text style={{ fontWeight: '700' }}>
                    {TIPO[l.ref_tipo] ?? l.ref_tipo}
                    {l.item && l.item !== l.ref_tipo ? ` · ${l.item}` : ''}
                  </Text>
                  <Mudancas acao={l.acao} mudou={l.mudou} />
                  <Text style={{ color: cores.textoSuave }}>
                    {l.quem ?? 'sistema'}
                    {l.cargo ? ` · ${l.cargo}` : ''}
                  </Text>
                </View>
              </Cartao>
            ))}
          </>
        )}
      </Ecra>
    </Guarda>
  );
}
