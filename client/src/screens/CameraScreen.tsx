import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  Camera,
  CommonResolutions,
  useCameraDevice,
  useCameraPermission,
  usePhotoOutput,
} from 'react-native-vision-camera';
import { useIsFocused } from '@react-navigation/native';
import { Directory, File, Paths } from 'expo-file-system';
import { randomUUID } from 'expo-crypto';
import type { BottomTabScreenProps } from '@react-navigation/bottom-tabs';
import type { RootTabParamList } from '../navigation/types';
import { translatePhoto } from '../api/translate';
import { insertHistory } from '../db/database';

type Props = BottomTabScreenProps<RootTabParamList, 'Camera'>;

const PHOTOS_DIR_NAME = 'photos';
const IMAGE_MIME_TYPE = 'image/jpeg';

function ensurePhotosDir(): Directory {
  const dir = new Directory(Paths.document, PHOTOS_DIR_NAME);
  if (!dir.exists) {
    dir.create({ idempotent: true, intermediates: true });
  }
  return dir;
}

function toFileUri(path: string): string {
  return path.startsWith('file://') ? path : `file://${path}`;
}

export default function CameraScreen({ navigation }: Props) {
  const { hasPermission, requestPermission } = useCameraPermission();
  const device = useCameraDevice('back');
  const photoOutput = usePhotoOutput({
    targetResolution: CommonResolutions.FHD_4_3,
    containerFormat: 'jpeg',
    quality: 0.8,
  });
  const isFocused = useIsFocused();
  const [busy, setBusy] = useState(false);

  const onCapture = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    let savedFile: File | null = null;
    try {
      const photoFile = await photoOutput.capturePhotoToFile({}, {});
      const id = randomUUID();
      const dir = ensurePhotosDir();
      const dest = new File(dir, `${id}.jpg`);
      const src = new File(toFileUri(photoFile.filePath));
      src.move(dest);
      savedFile = new File(dir, `${id}.jpg`);

      const result = await translatePhoto({
        uri: savedFile.uri,
        mimeType: IMAGE_MIME_TYPE,
        fileName: `${id}.jpg`,
      });

      insertHistory({
        id,
        createdAt: new Date().toISOString(),
        imageUri: savedFile.uri,
        imageMimeType: IMAGE_MIME_TYPE,
        originalText: result.originalText,
        translatedText: result.translatedText,
        model: result.model,
      });

      navigation.navigate('History');
    } catch (err) {
      console.error('capture failed:', err);
      if (savedFile?.exists) {
        try {
          savedFile.delete();
        } catch {
          // ignore cleanup failure
        }
      }
      const message = err instanceof Error ? err.message : '不明なエラー';
      Alert.alert('翻訳に失敗しました', message);
    } finally {
      setBusy(false);
    }
  }, [busy, photoOutput, navigation]);

  if (!hasPermission) {
    return (
      <View style={styles.center}>
        <Text style={styles.title}>カメラ権限が必要です</Text>
        <Text style={styles.note}>
          書類を撮影して翻訳するためにカメラを使用します。
        </Text>
        <View style={styles.spacer} />
        <Pressable style={styles.button} onPress={requestPermission}>
          <Text style={styles.buttonText}>カメラを許可</Text>
        </Pressable>
      </View>
    );
  }

  if (!device) {
    return (
      <View style={styles.center}>
        <Text style={styles.note}>利用可能なカメラデバイスが見つかりません。</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Camera
        style={StyleSheet.absoluteFill}
        device={device}
        isActive={isFocused && !busy}
        outputs={[photoOutput]}
      />
      <View style={styles.controls} pointerEvents="box-none">
        {busy && <Text style={styles.busyText}>翻訳中...</Text>}
        <Pressable
          style={[styles.shutter, busy && styles.shutterBusy]}
          onPress={onCapture}
          disabled={busy}
        >
          {busy ? (
            <ActivityIndicator color="#000" />
          ) : (
            <View style={styles.shutterInner} />
          )}
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#fff',
    padding: 24,
  },
  title: { fontSize: 18, fontWeight: '600', marginBottom: 8 },
  note: { color: '#666', textAlign: 'center' },
  spacer: { height: 16 },
  button: {
    backgroundColor: '#0366d6',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 6,
  },
  buttonText: { color: '#fff', fontWeight: '600' },
  controls: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 32,
    alignItems: 'center',
  },
  shutter: {
    width: 76,
    height: 76,
    borderRadius: 38,
    borderWidth: 4,
    borderColor: '#fff',
    backgroundColor: 'rgba(255,255,255,0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  shutterBusy: { opacity: 0.7 },
  shutterInner: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#fff',
  },
  busyText: { color: '#fff', marginBottom: 12 },
});
