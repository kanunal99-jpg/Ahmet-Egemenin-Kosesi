import { supabase, isSupabaseConfigured } from './supabase.client';
import { UserProfile, ServiceOperationResult } from '../types';

export class ProfileService {
  async updateProfile(userId: string, updates: Partial<UserProfile>): Promise<ServiceOperationResult<UserProfile>> {
    if (!isSupabaseConfigured || !userId) {
      return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    }

    try {
      const payload = {
        first_name: updates.first_name,
        last_name: updates.last_name,
        avatar_path: updates.avatar_path,
        updated_at: new Date().toISOString(),
      };

      const { data, error, count } = await supabase
        .from('profiles')
        .update(payload)
        .eq('id', userId)
        .select();

      const affected = count ?? (data ? data.length : 0);
      if (error || affected === 0 || !data || data.length === 0) {
        return { success: false, error: error?.message || 'Profile update failed', affectedRows: affected };
      }

      return { success: true, data: data[0] as UserProfile, affectedRows: affected };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: msg, affectedRows: 0 };
    }
  }
}

export const profileService = new ProfileService();
