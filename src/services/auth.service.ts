import { supabase, isSupabaseConfigured } from './supabase.client';
import { UserProfile, UserRole } from '../types';

export class AuthService {
  async getProfile(userId: string): Promise<UserProfile | null> {
    if (!isSupabaseConfigured) return null;

    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();

      if (error || !data) return null;

      return {
        id: data.id,
        first_name: data.first_name,
        last_name: data.last_name,
        avatar_path: data.avatar_path,
        role: (data.role as UserRole) || 'guest',
        created_at: data.created_at,
        updated_at: data.updated_at,
      };
    } catch {
      return null;
    }
  }

  async getCurrentSession() {
    if (!isSupabaseConfigured) return { user: null, profile: null, role: 'guest' as UserRole };

    try {
      const { data: { session } } = await supabase.auth.getSession();
      if (!session?.user) {
        return { user: null, profile: null, role: 'guest' as UserRole };
      }

      const profile = await this.getProfile(session.user.id);
      const role: UserRole = profile?.role || 'guest';

      return {
        user: { id: session.user.id, email: session.user.email },
        profile,
        role,
      };
    } catch {
      return { user: null, profile: null, role: 'guest' as UserRole };
    }
  }

  async signOut(): Promise<void> {
    if (!isSupabaseConfigured) return;
    try {
      await supabase.auth.signOut();
    } catch (e) {
      console.error('[AuthService] Sign out error:', e);
    }
  }
}

export const authService = new AuthService();
