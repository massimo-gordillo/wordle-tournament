import { Alert, Platform } from 'react-native';

/** Cross-platform confirm: Alert.alert on native, window.confirm on web. */
export function confirmDestructive(
  title: string,
  message: string,
  confirmLabel: string,
  cancelLabel: string,
  onConfirm: () => void | Promise<void>,
  onCancel?: () => void,
) {
  if (Platform.OS === 'web' && typeof window !== 'undefined' && window.confirm) {
    const ok = window.confirm([title, message].filter(Boolean).join('\n\n'));
    if (ok) {
      void Promise.resolve(onConfirm());
    } else {
      onCancel?.();
    }
    return;
  }

  Alert.alert(title, message, [
    { text: cancelLabel, style: 'cancel', onPress: onCancel },
    {
      text: confirmLabel,
      style: 'destructive',
      onPress: () => void Promise.resolve(onConfirm()),
    },
  ]);
}
