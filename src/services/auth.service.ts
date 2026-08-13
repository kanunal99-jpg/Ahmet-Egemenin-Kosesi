import { supabase, isSupabaseConfigured } from './supabase.client';
import { UserProfile, UserRole, SessionResult, AuthSessionStatus } from '../types';

export class AuthService {
  /**
   * Retrieves profile with explicit status distinction:
   * PROFILE_FOUND | PROFILE_NOT_FOUND | PROFILE_QUERY_ERROR
   */
  async getProfileResult(userId: string): Promise<{
    profile: UserProfile | null;
    status: Extract<AuthSessionStatus, 'PROFILE_FOUND' | 'PROFILE_NOT_FOUND' | 'PROFILE_QUERY_ERROR'>;
    error?: string;
  }> {
    if (!isSupabaseConfigured || !userId) {
      return { profile: null, status: 'PROFILE_NOT_FOUND' };
    }

    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();

      if (error) {
        return {
          profile: null,
          status: 'PROFILE_QUERY_ERROR',
          error: error.message,
        };
      }

      if (!data) {
        return {
          profile: null,
          status: 'PROFILE_NOT_FOUND',
        };
      }

      return {
        profile: {
          id: data.id,
          first_name: data.first_name,
          last_name: data.last_name,
          avatar_path: data.avatar_path,
          role: (data.role as UserRole) || 'child',
          created_at: data.created_at,
          updated_at: data.updated_at,
        },
        status: 'PROFILE_FOUND',
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Bilinmeyen profil sorgu hatası';
      return {
        profile: null,
        status: 'PROFILE_QUERY_ERROR',
        error: msg,
      };
    }
  }

  async getProfile(userId: string): Promise<UserProfile | null> {
    const res = await this.getProfileResult(userId);
    return res.profile;
  }

  /**
   * Evaluates current session and returns explicit status contract
   */
  async getCurrentSession(): Promise<SessionResult> {
    if (!isSupabaseConfigured) {
      return { user: null, profile: null, role: 'guest', status: 'NO_SESSION' };
    }

    try {
      const { data: { session }, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) {
        return {
          user: null,
          profile: null,
          role: 'guest',
          status: 'NO_SESSION',
          error: sessionError.message,
        };
      }

      if (!session?.user) {
        return { user: null, profile: null, role: 'guest', status: 'NO_SESSION' };
      }

      const { profile, status, error: profileErr } = await this.getProfileResult(session.user.id);

      if (status === 'PROFILE_FOUND' && profile) {
        return {
          user: { id: session.user.id, email: session.user.email },
          profile,
          role: profile.role,
          status: 'PROFILE_FOUND',
        };
      }

      if (status === 'PROFILE_QUERY_ERROR') {
        return {
          user: { id: session.user.id, email: session.user.email },
          profile: null,
          role: 'guest',
          status: 'PROFILE_QUERY_ERROR',
          error: profileErr || 'Profil sorgusu sırasında veritabanı hatası oluştu.',
        };
      }

      // PROFILE_NOT_FOUND (Auth user exists, but no profiles row yet)
      return {
        user: { id: session.user.id, email: session.user.email },
        profile: null,
        role: 'guest',
        status: 'PROFILE_NOT_FOUND',
        error: 'Kullanıcı profili bulunamadı.',
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Oturum yüklenemedi';
      return {
        user: null,
        profile: null,
        role: 'guest',
        status: 'PROFILE_QUERY_ERROR',
        error: msg,
      };
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
