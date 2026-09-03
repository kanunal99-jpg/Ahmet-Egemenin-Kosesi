import { supabase, isSupabaseConfigured } from './supabase.client';
import {
  ParentSettings,
  ParentChild,
  ReportTimePeriod,
  UsageReportData,
  ServiceOperationResult,
  EffectiveParentalSettings,
} from '../types';

export class ParentService {
  async getEffectiveParentalSettings(): Promise<EffectiveParentalSettings | null> {
    if (!isSupabaseConfigured) return null;
    try {
      const { data, error } = await supabase.rpc('get_my_effective_parental_settings');
      if (error || !data) return null;
      return data as EffectiveParentalSettings;
    } catch {
      return null;
    }
  }

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

  async getMyChildren(): Promise<ParentChild[]> {
    if (!isSupabaseConfigured) return [];
    try {
      const { data, error } = await supabase.rpc('get_my_children');
      if (error || !data) return [];

      const rows = data as Array<{
        id: string;
        child_id: string;
        child_name: string;
        created_at: string;
      }>;

      return rows.map((row) => ({
        id: row.id,
        childId: row.child_id,
        childName: row.child_name,
        createdAt: row.created_at,
      }));
    } catch {
      return [];
    }
  }

  async linkChild(childId: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !childId) {
      return { success: false, error: 'Database unconfigured or childId missing', affectedRows: 0 };
    }
    try {
      const { data, error } = await supabase.rpc('create_parent_child_link', { p_child_id: childId });
      if (error) return { success: false, error: error.message, affectedRows: 0 };
      const result = data as { success?: boolean; error?: string } | null;
      if (!result?.success) return { success: false, error: result?.error || 'Failed to link child', affectedRows: 0 };
      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown error', affectedRows: 0 };
    }
  }

  async verifyUserPin(userId: string | undefined, pin: string): Promise<{ success: boolean; message?: string; isLocked?: boolean; needsSetup?: boolean }> {
    if (!userId || !isSupabaseConfigured) return { success: false, message: 'Veritabanı bağlantısı yok.' };
    try {
      const { data, error } = await supabase.rpc('verify_parent_pin', { p_pin: pin });
      if (error) return { success: false, message: error.message };
      if (typeof data === 'boolean') return { success: data };
      if (data && typeof data === 'object') {
        const obj = data as { success?: boolean; message?: string; is_locked?: boolean; needs_setup?: boolean };
        return {
          success: Boolean(obj.success),
          message: obj.message,
          isLocked: Boolean(obj.is_locked),
          needsSetup: Boolean(obj.needs_setup),
        };
      }
      return { success: false, message: 'Geçersiz yanıt.' };
    } catch (err: unknown) {
      return { success: false, message: err instanceof Error ? err.message : 'PIN doğrulanamadı' };
    }
  }

  async updatePin(userId: string, newPin: string, oldPin?: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !userId) return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    try {
      const { data, error } = await supabase.rpc('update_parent_pin', {
        p_new_pin: newPin,
        p_old_pin: oldPin || null,
      });
      if (error) return { success: false, error: error.message, affectedRows: 0 };

      // The reconciled RPC contract returns BOOLEAN. Keep object compatibility for
      // older deployments so a partially migrated environment remains safe to use.
      if (typeof data === 'boolean') {
        return data
          ? { success: true, affectedRows: 1 }
          : { success: false, error: 'PIN güncellenemedi.', affectedRows: 0 };
      }

      if (data && typeof data === 'object') {
        const result = data as { success?: boolean; message?: string | null };
        if (result.success === true) return { success: true, affectedRows: 1 };
        return { success: false, error: result.message || 'PIN güncellenemedi.', affectedRows: 0 };
      }

      return { success: false, error: 'Geçersiz PIN güncelleme yanıtı.', affectedRows: 0 };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown error', affectedRows: 0 };
    }
  }

  async updateSettings(userId: string, settings: {
    daily_time_limit_minutes?: number | null;
    allowed_categories?: string[] | null;
    bedtime_start?: string | null;
    bedtime_end?: string | null;
  }): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !userId) return { success: false, error: 'Database unconfigured', affectedRows: 0 };

    try {
      const { data, error } = await supabase.rpc('update_parent_settings', {
        p_daily_time_limit_minutes: settings.daily_time_limit_minutes ?? null,
        p_allowed_categories: settings.allowed_categories ?? null,
        p_bedtime_start: settings.bedtime_start ?? null,
        p_bedtime_end: settings.bedtime_end ?? null,
      });

      if (error) return { success: false, error: error.message, affectedRows: 0 };
      if (data !== true) return { success: false, error: 'Ebeveyn ayarları sunucu tarafından onaylanmadı.', affectedRows: 0 };
      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown error', affectedRows: 0 };
    }
  }

  async getUsageReport(childId: string, period: ReportTimePeriod): Promise<UsageReportData> {
    const emptyReport: UsageReportData = {
      period,
      totalWatchTimeSeconds: 0,
      watchedVideosCount: 0,
      completedVideosCount: 0,
      categoryStats: [],
      topWatchedVideos: [],
    };

    if (!isSupabaseConfigured || !childId) return emptyReport;

    try {
      const { data, error } = await supabase.rpc('get_parent_child_usage_report', {
        p_child_id: childId,
        p_period: period,
      });
      if (error || !data) return emptyReport;

      const result = data as UsageReportData & { error?: string };
      if (result.error) return emptyReport;

      return {
        period: result.period || period,
        totalWatchTimeSeconds: Number(result.totalWatchTimeSeconds) || 0,
        watchedVideosCount: Number(result.watchedVideosCount) || 0,
        completedVideosCount: Number(result.completedVideosCount) || 0,
        categoryStats: Array.isArray(result.categoryStats) ? result.categoryStats : [],
        topWatchedVideos: Array.isArray(result.topWatchedVideos) ? result.topWatchedVideos : [],
      };
    } catch {
      return emptyReport;
    }
  }
}

export const parentService = new ParentService();
