import { supabase, isSupabaseConfigured } from './supabase.client';
import { PlaybackAuthorization } from '../types/parentalControl.types';

export class ParentalControlService {
  /**
   * Authorizes playback with a strict split between public guest content and
   * authenticated parent/child policy enforcement.
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
      const { data: { user } } = await supabase.auth.getUser();

      // Guest playback is limited to videos already exposed as public by RLS.
      // This avoids granting anon EXECUTE on the SECURITY DEFINER policy RPC.
      if (!user) {
        const { data: video, error } = await supabase
          .from('videos')
          .select('visibility,is_deleted')
          .eq('id', videoId)
          .maybeSingle();

        if (error) {
          return {
            allowed: false,
            reason: 'VIDEO_LOOKUP_ERROR',
            message: 'Video yetkilendirmesi doğrulanamadı.',
            error: error.message,
          };
        }

        if (!video || video.is_deleted) {
          return {
            allowed: false,
            reason: 'VIDEO_NOT_FOUND',
            message: 'Video bulunamadı.',
          };
        }

        return video.visibility === 'public'
          ? { allowed: true, reason: 'OK', message: undefined }
          : { allowed: false, reason: 'VIDEO_NOT_PUBLIC', message: 'Bu video herkese açık değil.' };
      }

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
        reason: res.reason || (res.allowed ? 'OK' : 'AUTHORIZATION_ERROR'),
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
