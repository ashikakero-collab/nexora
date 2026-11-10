import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HubScreen from '../../features/hub/screens/HubScreen';
import { palette } from '../../theme/colors/palette';

export type RootStackParamList = {
  Hub: undefined;
};

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function RootNavigator() {
  return (
    <NavigationContainer>
      <Stack.Navigator
        initialRouteName="Hub"
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: palette.background },
          animation: 'fade',
        }}
      >
        <Stack.Screen name="Hub" component={HubScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
