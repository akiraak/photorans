import { Button, StyleSheet, Text, View } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { HistoryStackParamList } from '../navigation/types';

type Props = NativeStackScreenProps<HistoryStackParamList, 'HistoryList'>;

export default function HistoryListScreen({ navigation }: Props) {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>写真一覧</Text>
      <Text style={styles.note}>Phase2-4 でローカル DB 連携</Text>
      <View style={styles.spacer} />
      <Button
        title="ダミー詳細を開く"
        onPress={() => navigation.navigate('HistoryDetail', { id: 'dummy-1' })}
      />
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
  spacer: {
    height: 16,
  },
});
