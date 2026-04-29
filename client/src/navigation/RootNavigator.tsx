import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import CameraScreen from '../screens/CameraScreen';
import HistoryStack from './HistoryStack';
import type { RootTabParamList } from './types';

const Tab = createBottomTabNavigator<RootTabParamList>();

export default function RootNavigator() {
  return (
    <Tab.Navigator>
      <Tab.Screen
        name="Camera"
        component={CameraScreen}
        options={{ title: 'カメラ' }}
      />
      <Tab.Screen
        name="History"
        component={HistoryStack}
        options={{ title: '一覧', headerShown: false }}
      />
    </Tab.Navigator>
  );
}
