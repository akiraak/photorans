import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HistoryListScreen from '../screens/HistoryListScreen';
import HistoryDetailScreen from '../screens/HistoryDetailScreen';
import type { HistoryStackParamList } from './types';

const Stack = createNativeStackNavigator<HistoryStackParamList>();

export default function HistoryStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen
        name="HistoryList"
        component={HistoryListScreen}
        options={{ title: '写真一覧' }}
      />
      <Stack.Screen
        name="HistoryDetail"
        component={HistoryDetailScreen}
        options={{ title: '詳細' }}
      />
    </Stack.Navigator>
  );
}
