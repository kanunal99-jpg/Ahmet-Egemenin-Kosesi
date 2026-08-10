import { supabase, isSupabaseConfigured } from './supabase.client';
import { WatchHistory, WatchProgressInput, ServiceOperationResult } from '../types';

export class WatchHistoryService {
  async getUserHistory(userId: string): Promise<WatchHistory[]> {
    if (!isSupabaseConfigured || !userId) return [];

    try {
      const { data, error } = await supabase
        .from('watch_history')
        .select(`
          *,
          video:videos (*)
        `)
        .eq('user_id', userId)
        .order('updated_at', { ascending: false });

      if (error || !data) return [];
      return data as WatchHistory[];
    } catch {
      return [];
    }
  }

  async getProgress(userId: string, videoId: string): Promise<WatchHistory | null> {
    if (!isSupabaseConfigured || !userId || !videoId) return null;

    try {
      const { data, error } = await supabase
        .from('watch_history')
        .select('*')
        .eq('user_id', userId)
        .eq('video_id', videoId)
        .maybeSingle();

      if (error || !data) return null;
      return data as WatchHistory;
    } catch {
      return null;
    }
  }

  async saveProgress(userId: string, input: WatchProgressInput): Promise<ServiceOperationResult<WatchHistory>> {
    if (!isSupabaseConfigured || !userId) {
      return { success: false, error: 'Database unconfigured or user missing', affectedRows: 0 };
    }

    try {
      const existing = await this.getProgress(userId, input.video_id);

      let resultData;
      let errorResult;
      let affected = 0;

      if (existing) {
        const { data, error, count } = await supabase
          .from('watch_history')
          .update({
            progress_seconds: input.progress_seconds,
            completed: input.completed ?? existing.completed,
            updated_at: new Date().toISOString(),
          })
          .eq('id', existing.id)
          .select();

        resultData = data?.[0];
        errorResult = error;
        affected = count ?? (data ? data.length : 0);
      } else {
        const { data, error } = await supabase
          .from('watch_history')
          .insert({
            user_id: userId,
            video_id: input.video_id,
            progress_seconds: input.progress_seconds,
            completed: input.completed ?? false,
          })
          .select()
          .single();

        resultData = data;
        errorResult = error;
        affected = data ? 1 : 0;
      }

      if (errorResult || !resultData) {
        return { success: false, error: errorResult?.message || 'Save progress failed', affectedRows: 0 };
      }

      return { success: true, data: resultData as WatchHistory, affectedRows: affected };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: msg, affectedRows: 0 };
    }
  }
}

export const watchHistoryService = new WatchHistoryService();
