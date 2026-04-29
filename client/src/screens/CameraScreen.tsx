import { StyleSheet, Text, View } from 'react-native';

export default function CameraScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>カメラ</Text>
      <Text style={styles.note}>Phase2-3 で撮影 → API 送信を実装予定</Text>
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
