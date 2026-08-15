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
      const rows = data as Array<{ id: string; child_id: string; child_name: string; created_at: string }>;
      return rows.map((r) => ({ id: r.id, childId: r.child_id, childName: r.child_name, createdAt: r.created_at }));
    } catch {
      return [];
    }
  }

  /** Redeems a one-time invite code created by the child account. */
  async linkChild(inviteCode: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !inviteCode.trim()) {
      return { success: false, error: 'Database unconfigured or invite code missing', affectedRows: 0 };
    }
    try {
      const { data, error } = await supabase.rpc('redeem_parent_child_invite', { p_code: inviteCode.trim() });
      if (error) return { success: false, error: error.message, affectedRows: 0 };
      const res = data as { success?: boolean; error?: string };
      if (!res.success) return { success: false, error: res.error || 'Failed to link child', affectedRows: 0 };
      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown error', affectedRows: 0 };
    }
  }

  /** Generates a short-lived one-time code for the current child account. */
  async generateChildLinkInvite(): Promise<{ success: boolean; code?: string; expiresAt?: string; error?: string }> {
    if (!isSupabaseConfigured) return { success: false, error: 'Database unconfigured' };
    try {
      const { data, error } = await supabase.rpc('create_my_child_link_invite');
      if (error) return { success: false, error: error.message };
      const res = data as { success?: boolean; code?: string; expires_at?: string; error?: string };
      return { success: Boolean(res.success), code: res.code, expiresAt: res.expires_at, error: res.error };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Davet kodu oluşturulamadı' };
    }
  }

  async verifyUserPin(userId: string | undefined, pin: string): Promise<{ success: boolean; message?: string; isLocked?: boolean; needsSetup?: boolean }> {
    if (!userId || !isSupabaseConfigured) return { success: false, message: 'Veritabanı bağlantısı yok.' };
    try {
      const { data, error } = await supabase.rpc('verify_parent_pin', { p_pin: pin });
      if (error) return { success: false, message: error.message };
      if (typeof data === 'boolean') return { success: data };
      if (typeof data === 'object' && data !== null) {
        const obj = data as { success?: boolean; message?: string; is_locked?: boolean; needs_setup?: boolean };
        return { success: Boolean(obj.success), message: obj.message, isLocked: Boolean(obj.is_locked), needsSetup: Boolean(obj.needs_setup) };
      }
      return { success: false, message: 'Geçersiz yanıt.' };
    } catch (err: unknown) {
      return { success: false, message: err instanceof Error ? err.message : 'PIN doğrulanamadı' };
    }
  }

  async updatePin(userId: string, newPin: string, oldPin?: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !userId) return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    try {
      const { error } = await supabase.rpc('update_parent_pin', { p_new_pin: newPin, p_old_pin: oldPin || null });
      if (error) return { success: false, error: error.message, affectedRows: 0 };
      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown error', affectedRows: 0 };
    }
  }

  async updateSettings(userId: string, settings: { daily_time_limit_minutes?: number | null; allowed_categories?: string[] | null; bedtime_start?: string | null; bedtime_end?: string | null }): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured || !userId) return { success: false, error: 'Database unconfigured', affectedRows: 0 };
    try {
      const { error } = await supabase.rpc('update_parent_settings', {
        p_daily_time_limit_minutes: settings.daily_time_limit_minutes ?? null,
        p_allowed_categories: settings.allowed_categories ?? null,
        p_bedtime_start: settings.bedtime_start ?? null,
        p_bedtime_end: settings.bedtime_end ?? null,
      });
      if (error) return { success: false, error: error.message, affectedRows: 0 };
      return { success: true, affectedRows: 1 };
    } catch (err: unknown) {
      return { success: false, error: err instanceof Error ? err.message : 'Unknown error', affectedRows: 0 };
    }
  }

  async getUsageReport(childId: string, period: ReportTimePeriod): Promise<UsageReportData> {
    const emptyReport: UsageReportData = { period, totalWatchTimeSeconds: 0, watchedVideosCount: 0, completedVideosCount: 0, categoryStats: [], topWatchedVideos: [] };
    if (!isSupabaseConfigured || !childId) return emptyReport;
    try {
      const { data, error } = await supabase.rpc('get_parent_child_usage_report', { p_child_id: childId, p_period: period });
      if (error || !data) return emptyReport;
      const res = data as UsageReportData & { error?: string };
      if (res.error) return emptyReport;
      return {
        period: res.period || period,
        totalWatchTimeSeconds: Number(res.totalWatchTimeSeconds) || 0,
        watchedVideosCount: Number(res.watchedVideosCount) || 0,
        completedVideosCount: Number(res.completedVideosCount) || 0,
        categoryStats: Array.isArray(res.categoryStats) ? res.categoryStats : [],
        topWatchedVideos: Array.isArray(res.topWatchedVideos) ? res.topWatchedVideos : [],
      };
    } catch {
      return emptyReport;
    }
  }
}

export const parentService = new ParentService();
