import { StyleSheet, Text, View } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { HistoryStackParamList } from '../navigation/types';

type Props = NativeStackScreenProps<HistoryStackParamList, 'HistoryDetail'>;

export default function HistoryDetailScreen({ route }: Props) {
  const { id } = route.params;
  return (
    <View style={styles.container}>
      <Text style={styles.title}>詳細</Text>
      <Text style={styles.note}>id: {id}</Text>
      <Text style={styles.note}>Phase2-5 で写真 / 原文 / 訳文を表示</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    padding: 16,
  },
  title: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 8,
  },
  note: {
    color: '#666',
  },
});
