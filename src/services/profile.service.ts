import { supabase, isSupabaseConfigured } from './supabase.client';
import { UserProfile, ServiceOperationResult } from '../types';

export class ProfileService {
  async updateProfile(userId: string, updates: Partial<UserProfile>): Promise<ServiceOperationResult<UserProfile>> {
    if (!isSupabaseConfigured || !userId) {
      return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    }

    try {
      const payload: Record<string, string | null> = {
        updated_at: new Date().toISOString(),
      };

      if (updates.first_name !== undefined) payload.first_name = updates.first_name;
      if (updates.last_name !== undefined) payload.last_name = updates.last_name;
      if (updates.avatar_path !== undefined) payload.avatar_path = updates.avatar_path;

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

  async updateAvatarPath(userId: string, avatarPath: string | null): Promise<ServiceOperationResult<UserProfile>> {
    return this.updateProfile(userId, { avatar_path: avatarPath });
  }
}

export const profileService = new ProfileService();
