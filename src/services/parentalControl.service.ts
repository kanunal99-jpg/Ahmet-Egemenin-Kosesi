import { supabase, isSupabaseConfigured } from './supabase.client';
import { PlaybackAuthorization } from '../types/parentalControl.types';

export class ParentalControlService {
  /**
   * Authorizes child video playback strictly via server-side RPC (CRIT-07, CRIT-16)
   * Enforces FAIL-CLOSED: Any network error, timeout, or missing data returns allowed: false.
   */
  async authorizePlayback(videoId: string): Promise<PlaybackAuthorization> {
    if (!videoId) {
      return {
        allowed: false,
        reason: 'VIDEO_NOT_FOUND',
        message: 'Geçersiz video kimliği.',
      };
    }

    if (!isSupabaseConfigured) {
      return {
        allowed: false,
        reason: 'SETTINGS_UNAVAILABLE',
        message: 'Veritabanı bağlantısı kurulamadı. Güvenlik nedeniyle oynatma durduruldu.',
        error: 'Database unconfigured',
      };
    }

    try {
      const { data, error } = await supabase.rpc('authorize_child_video_play', {
        p_video_id: videoId,
      });

      if (error) {
        return {
          allowed: false,
          reason: 'AUTHORIZATION_ERROR',
          message: 'Yetkilendirme sunucusuna ulaşılamadı. Lütfen tekrar deneyin.',
          error: error.message,
        };
      }

      if (!data || typeof data !== 'object') {
        return {
          allowed: false,
          reason: 'SETTINGS_UNAVAILABLE',
          message: 'Ebeveyn kontrol sunucusundan geçersiz yanıt alındı.',
        };
      }

      const res = data as { allowed?: boolean; reason?: string; message?: string };

      return {
        allowed: Boolean(res.allowed),
        reason: (res.reason as any) || (res.allowed ? 'OK' : 'AUTHORIZATION_ERROR'),
        message: res.message,
      };
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Unknown authorization error';
      return {
        allowed: false,
        reason: 'AUTHORIZATION_ERROR',
        message: 'Ebeveyn kontrolü doğrulanırken bir hata oluştu.',
        error: errorMsg,
      };
    }
  }
}

export const parentalControlService = new ParentalControlService();
