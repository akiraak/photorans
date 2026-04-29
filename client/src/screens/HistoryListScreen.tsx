import { useCallback, useState } from 'react';
import {
  FlatList,
  Image,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { HistoryStackParamList } from '../navigation/types';
import { listHistory, type HistoryRecord } from '../db/database';

type Props = NativeStackScreenProps<HistoryStackParamList, 'HistoryList'>;

const PREVIEW_LINES = 2;

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

export default function HistoryListScreen({ navigation }: Props) {
  const [items, setItems] = useState<HistoryRecord[]>([]);

  useFocusEffect(
    useCallback(() => {
      setItems(listHistory());
    }, []),
  );

  if (items.length === 0) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyTitle}>まだ履歴がありません</Text>
        <Text style={styles.emptyNote}>
          カメラタブから書類を撮影すると、ここに翻訳結果が並びます。
        </Text>
      </View>
    );
  }

  return (
    <FlatList
      style={styles.list}
      data={items}
      keyExtractor={(item) => item.id}
      ItemSeparatorComponent={() => <View style={styles.separator} />}
      renderItem={({ item }) => (
        <Pressable
          style={({ pressed }) => [styles.row, pressed && styles.rowPressed]}
          onPress={() =>
            navigation.navigate('HistoryDetail', { id: item.id })
          }
        >
          <Image source={{ uri: item.imageUri }} style={styles.thumb} />
          <View style={styles.body}>
            <Text style={styles.date}>{formatCreatedAt(item.createdAt)}</Text>
            <Text
              style={styles.preview}
              numberOfLines={PREVIEW_LINES}
              ellipsizeMode="tail"
            >
              {item.translatedText.trim() || '(訳文なし)'}
            </Text>
          </View>
        </Pressable>
      )}
    />
  );
}

const styles = StyleSheet.create({
  list: { flex: 1, backgroundColor: '#fff' },
  separator: { height: 1, backgroundColor: '#eee', marginLeft: 88 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 16,
    backgroundColor: '#fff',
  },
  rowPressed: { backgroundColor: '#f0f0f0' },
  thumb: {
    width: 64,
    height: 64,
    borderRadius: 6,
    backgroundColor: '#ddd',
    marginRight: 12,
  },
  body: { flex: 1 },
  date: { fontSize: 12, color: '#888', marginBottom: 4 },
  preview: { fontSize: 14, color: '#222', lineHeight: 20 },
  empty: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    padding: 24,
  },
  emptyTitle: { fontSize: 16, fontWeight: '600', marginBottom: 8 },
  emptyNote: { color: '#666', textAlign: 'center' },
});
