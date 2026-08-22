import { supabase, isSupabaseConfigured } from './supabase.client';

export type ChildInviteResult = {
  success: boolean;
  code?: string;
  expires_at?: string;
  error?: string;
};

export type ParentRedeemResult = {
  success: boolean;
  error?: string;
};

export const parentLinkService = {
  async createChildInvite(): Promise<ChildInviteResult> {
    if (!isSupabaseConfigured) return { success: false, error: 'Veritabanı bağlantısı yok.' };
    try {
      const { data, error } = await supabase.rpc('create_my_child_link_invite');
      if (error) return { success: false, error: error.message };
      const result = data as ChildInviteResult | null;
      if (!result?.success || !result.code) return { success: false, error: result?.error || 'Bağlantı kodu oluşturulamadı.' };
      return result;
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Bağlantı kodu oluşturulamadı.' };
    }
  },

  async redeemChildInvite(code: string): Promise<ParentRedeemResult> {
    const normalized = code.trim().replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
    if (!isSupabaseConfigured) return { success: false, error: 'Veritabanı bağlantısı yok.' };
    if (normalized.length < 8 || normalized.length > 16) return { success: false, error: 'Geçerli bir bağlantı kodu girin.' };

    try {
      const { data, error } = await supabase.rpc('redeem_parent_child_invite', { p_code: normalized });
      if (error) return { success: false, error: error.message };
      const result = data as ParentRedeemResult | null;
      return result?.success ? { success: true } : { success: false, error: result?.error || 'Bağlantı kurulamadı.' };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Bağlantı kurulamadı.' };
    }
  },
};
