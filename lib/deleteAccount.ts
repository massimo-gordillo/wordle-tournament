import { supabase } from '@/lib/supabase';

export async function deleteAccount(): Promise<{ error: string | null }> {
  const { data, error } = await supabase.functions.invoke('delete-account', {
    method: 'POST',
  });

  if (error) {
    return { error: error.message };
  }

  const payload = data as { success?: boolean; error?: string } | null;
  if (payload?.error) {
    return { error: payload.error };
  }

  if (!payload?.success) {
    return { error: 'Account deletion did not complete.' };
  }

  return { error: null };
}
