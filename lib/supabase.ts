import 'react-native-url-polyfill/auto';
import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import Constants from 'expo-constants';
import { Platform } from 'react-native';

type AppExtra = {
  supabaseUrl?: string;
  supabaseAnonKey?: string;
};

const appExtra = (Constants.expoConfig?.extra ?? {}) as AppExtra;
const supabaseUrl = (process.env.EXPO_PUBLIC_SUPABASE_URL ?? appExtra.supabaseUrl)?.trim();
const supabaseAnonKey = (process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? appExtra.supabaseAnonKey)?.trim();
const hasSupabaseConfig = Boolean(supabaseUrl && supabaseAnonKey);
const fallbackUrl = 'https://placeholder.supabase.co';
const fallbackAnonKey = 'placeholder-anon-key';

if (!hasSupabaseConfig && __DEV__) {
  // eslint-disable-next-line no-console
  console.error(
    'Missing Supabase config. Set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY in your environment.'
  );
}

// Custom storage adapter for secure token storage
const ExpoSecureStoreAdapter = {
  getItem: async (key: string) => {
    if (Platform.OS !== 'web') {
      return SecureStore.getItemAsync(key);
    }
    if (typeof localStorage === 'undefined') {
      return null;
    }
    return localStorage.getItem(key);
  },
  setItem: async (key: string, value: string) => {
    if (Platform.OS !== 'web') {
      SecureStore.setItemAsync(key, value);
      return;
    }
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem(key, value);
    }
  },
  removeItem: async (key: string) => {
    if (Platform.OS !== 'web') {
      SecureStore.deleteItemAsync(key);
      return;
    }
    if (typeof localStorage !== 'undefined') {
      localStorage.removeItem(key);
    }
  },
};

export const supabase = createClient(
  hasSupabaseConfig ? supabaseUrl! : fallbackUrl,
  hasSupabaseConfig ? supabaseAnonKey! : fallbackAnonKey,
  {
    auth: {
      storage: ExpoSecureStoreAdapter,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  }
);
