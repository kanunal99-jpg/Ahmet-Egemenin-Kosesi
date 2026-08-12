import { supabase, isSupabaseConfigured } from './supabase.client';
import { ParentSettings, ReportTimePeriod, UsageReportData, ServiceOperationResult } from '../types';
import { DEFAULT_CATEGORIES } from '../constants/categories.constants';

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
    const emptyReport: UsageReportData = {
      period,
      totalWatchTimeSeconds: 0,
      watchedVideosCount: 0,
      completedVideosCount: 0,
      categoryStats: [],
      topWatchedVideos: [],
    };

    if (!isSupabaseConfigured || !userId) return emptyReport;

    try {
      let query = supabase
        .from('watch_history')
        .select(`
          id,
          user_id,
          video_id,
          progress_seconds,
          completed,
          updated_at,
          video:videos!inner (
            id,
            title,
            category_id,
            is_deleted,
            category:categories (
              id,
              title
            )
          )
        `)
        .eq('user_id', userId)
        .eq('video.is_deleted', false);

      const now = new Date();
      let startDate: Date | null = null;

      switch (period) {
        case 'daily':
          startDate = new Date(now);
          startDate.setHours(0, 0, 0, 0);
          break;
        case 'weekly':
          startDate = new Date(now);
          startDate.setDate(now.getDate() - 7);
          break;
        case 'monthly':
          startDate = new Date(now);
          startDate.setMonth(now.getMonth() - 1);
          break;
        case '3months':
          startDate = new Date(now);
          startDate.setMonth(now.getMonth() - 3);
          break;
        case '6months':
          startDate = new Date(now);
          startDate.setMonth(now.getMonth() - 6);
          break;
        case '9months':
          startDate = new Date(now);
          startDate.setMonth(now.getMonth() - 9);
          break;
        case '12months':
          startDate = new Date(now);
          startDate.setFullYear(now.getFullYear() - 1);
          break;
      }

      if (startDate) {
        query = query.gte('updated_at', startDate.toISOString());
      }

      const { data, error } = await query;

      if (error || !data) {
        return emptyReport;
      }

      type JoinedRow = {
        id: string;
        user_id: string;
        video_id: string;
        progress_seconds: number;
        completed: boolean;
        updated_at: string;
        video?: {
          id: string;
          title: string;
          category_id: string | null;
          is_deleted: boolean;
          category?: {
            id: string;
            title: string;
          } | null;
        } | null;
      };

      const rows = (data as unknown as JoinedRow[]).filter((r) => r.video && !r.video.is_deleted);

      const totalWatchTimeSeconds = rows.reduce((sum, r) => sum + (r.progress_seconds || 0), 0);
      const watchedVideosCount = rows.length;
      const completedVideosCount = rows.filter((r) => r.completed).length;

      const categoryMap = new Map<string, { categoryTitle: string; watchTimeSeconds: number; videoCount: number }>();

      rows.forEach((r) => {
        const catId = r.video?.category_id || 'uncategorized';
        const catTitle =
          r.video?.category?.title ||
          DEFAULT_CATEGORIES.find((c) => c.id === catId)?.title ||
          'Kategorisiz';

        const existing = categoryMap.get(catId) || { categoryTitle: catTitle, watchTimeSeconds: 0, videoCount: 0 };
        existing.watchTimeSeconds += r.progress_seconds || 0;
        existing.videoCount += 1;
        categoryMap.set(catId, existing);
      });

      const categoryStats = Array.from(categoryMap.entries())
        .map(([categoryId, stats]) => ({
          categoryId,
          categoryTitle: stats.categoryTitle,
          watchTimeSeconds: stats.watchTimeSeconds,
          videoCount: stats.videoCount,
        }))
        .sort((a, b) => b.watchTimeSeconds - a.watchTimeSeconds);

      const topWatchedVideos = rows
        .map((r) => ({
          videoId: r.video_id,
          title: r.video?.title || 'Bilinmeyen Video',
          watchCount: 1,
          totalSeconds: r.progress_seconds || 0,
        }))
        .sort((a, b) => b.totalSeconds - a.totalSeconds)
        .slice(0, 5);

      return {
        period,
        totalWatchTimeSeconds,
        watchedVideosCount,
        completedVideosCount,
        categoryStats,
        topWatchedVideos,
      };
    } catch {
      return emptyReport;
    }
  }
}

export const parentService = new ParentService();
