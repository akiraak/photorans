import { useCallback, useState } from 'react';
import { Image, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { HistoryStackParamList } from '../navigation/types';
import { getHistoryById, type HistoryRecord } from '../db/database';

type Props = NativeStackScreenProps<HistoryStackParamList, 'HistoryDetail'>;

type LoadState =
  | { status: 'loading' }
  | { status: 'found'; record: HistoryRecord }
  | { status: 'missing' };

function formatCreatedAt(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd} ${hh}:${mi}`;
}

export default function HistoryDetailScreen({ route }: Props) {
  const { id } = route.params;
  const [state, setState] = useState<LoadState>({ status: 'loading' });

  useFocusEffect(
    useCallback(() => {
      const record = getHistoryById(id);
      setState(record ? { status: 'found', record } : { status: 'missing' });
    }, [id]),
  );

  if (state.status === 'loading') {
    return <View style={styles.center} />;
  }

  if (state.status === 'missing') {
    return (
      <View style={styles.center}>
        <Text style={styles.missingTitle}>履歴が見つかりません</Text>
        <Text style={styles.missingNote}>
          この履歴は削除されたか、存在しません。
        </Text>
      </View>
    );
  }

  const { record } = state;

  return (
    <ScrollView
      style={styles.scroll}
      contentContainerStyle={styles.content}
    >
      <Image
        source={{ uri: record.imageUri }}
        style={styles.image}
        resizeMode="contain"
      />
      <Text style={styles.meta}>{formatCreatedAt(record.createdAt)}</Text>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>訳文</Text>
        <Text style={styles.body} selectable>
          {record.translatedText.trim() || '(訳文なし)'}
        </Text>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle}>原文</Text>
        <Text style={styles.body} selectable>
          {record.originalText.trim() || '(原文なし)'}
        </Text>
      </View>

      <Text style={styles.model}>model: {record.model}</Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scroll: { flex: 1, backgroundColor: '#fff' },
  content: { padding: 16, paddingBottom: 32 },
  image: {
    width: '100%',
    aspectRatio: 3 / 4,
    backgroundColor: '#eee',
    borderRadius: 6,
    marginBottom: 8,
  },
  meta: { fontSize: 12, color: '#888', marginBottom: 16 },
  section: { marginBottom: 20 },
  sectionTitle: {
    fontSize: 13,
    fontWeight: '600',
    color: '#555',
    marginBottom: 6,
  },
  body: { fontSize: 16, lineHeight: 24, color: '#222' },
  model: { fontSize: 11, color: '#aaa', marginTop: 8 },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    padding: 24,
  },
  missingTitle: { fontSize: 16, fontWeight: '600', marginBottom: 8 },
  missingNote: { color: '#666', textAlign: 'center' },
});
