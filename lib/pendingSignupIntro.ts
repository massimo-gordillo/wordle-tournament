import AsyncStorage from '@react-native-async-storage/async-storage';

/** Set after successful signup; index reads this to show the one-time intro (all platforms). */
export const PENDING_SIGNUP_INTRO_KEY = 'wt_pending_signup_intro';

export async function markPendingSignupIntro(): Promise<void> {
  await AsyncStorage.setItem(PENDING_SIGNUP_INTRO_KEY, '1');
}

export async function getPendingSignupIntro(): Promise<boolean> {
  const v = await AsyncStorage.getItem(PENDING_SIGNUP_INTRO_KEY);
  return v === '1';
}

export async function clearPendingSignupIntro(): Promise<void> {
  await AsyncStorage.removeItem(PENDING_SIGNUP_INTRO_KEY);
}
