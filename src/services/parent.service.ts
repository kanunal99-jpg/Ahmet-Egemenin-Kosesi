import { supabase, isSupabaseConfigured } from './supabase.client';
import { ParentSettings, ReportTimePeriod, UsageReportData, ServiceOperationResult } from '../types';

export class ParentService {
  /**
   * Retrieves non-sensitive parent settings status using RPC or secure view (NO pin_hash/failed_attempts)
   */
  async getSettings(userId: string): Promise<ParentSettings | null> {
    if (!isSupabaseConfigured || !userId) return null;

    try {
      const { data, error } = await supabase.rpc('get_my_parent_settings_status');

      if (error || !data) return null;
      return data as ParentSettings;
    } catch {
      return null;
    }
  }

  /**
   * Verifies PIN strictly server-side via RPC with lockout handling
   */
  async verifyUserPin(userId: string | undefined, pin: string): Promise<{ success: boolean; message?: string; isLocked?: boolean }> {
    if (!userId || !isSupabaseConfigured) {
      return { success: false, message: 'Veritabanı bağlantısı yok.' };
    }

    try {
      const { data, error } = await supabase.rpc('verify_parent_pin', {
        p_pin: pin,
      });

      if (error) {
        return { success: false, message: error.message };
      }

      if (typeof data === 'boolean') {
        return { success: data };
      }

      if (typeof data === 'object' && data !== null) {
        const obj = data as { success?: boolean; message?: string; is_locked?: boolean };
        return {
          success: Boolean(obj.success),
          message: obj.message,
          isLocked: Boolean(obj.is_locked),
        };
      }
      return { success: false, message: 'Geçersiz yanıt.' };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'PIN doğrulanamadı';
      return { success: false, message: msg };
    }
  }

  /**
   * Updates PIN strictly server-side via RPC with mandatory old PIN check when existing
   */
  async updatePin(userId: string, newPin: string, oldPin?: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !userId) {
      return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    }

    try {
      const { error } = await supabase.rpc('update_parent_pin', {
        p_new_pin: newPin,
        p_old_pin: oldPin || null,
      });

      if (error) {
        return { success: false, error: error.message, affectedRows: 0 };
      }

      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: msg, affectedRows: 0 };
    }
  }

  /**
   * Updates non-sensitive parent settings via RPC
   */
  async updateSettings(
    userId: string,
    settings: {
      daily_time_limit_minutes?: number | null;
      allowed_categories?: string[] | null;
      bedtime_start?: string | null;
      bedtime_end?: string | null;
    }
  ): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !userId) {
      return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    }

    try {
      const { error } = await supabase.rpc('update_parent_settings', {
        p_daily_time_limit_minutes: settings.daily_time_limit_minutes ?? null,
        p_allowed_categories: settings.allowed_categories ?? null,
        p_bedtime_start: settings.bedtime_start ?? null,
        p_bedtime_end: settings.bedtime_end ?? null,
      });

      if (error) {
        return { success: false, error: error.message, affectedRows: 0 };
      }

      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: msg, affectedRows: 0 };
    }
  }

  /**
   * Generates usage report strictly from watch_history (READ-ONLY calculation)
   */
  async getUsageReport(userId: string, period: ReportTimePeriod): Promise<UsageReportData> {
    // Read-only calculation stub for Stage 2 architecture
    return {
      period,
      totalWatchTimeSeconds: 0,
      watchedVideosCount: 0,
      completedVideosCount: 0,
      categoryStats: [],
      topWatchedVideos: [],
    };
  }
}

export const parentService = new ParentService();
