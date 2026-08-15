import { supabase, isSupabaseConfigured } from './supabase.client';
import { WatchHistory, WatchProgressInput, WatchSessionStartResult, HeartbeatSessionResponse, ServiceOperationResult } from '../types';

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

  /**
   * Starts a new watch session in watch_history_sessions table via RPC (CRIT-08 & CRIT-18)
   * Hardened: Verifies server-side authorization and sessionId before returning success
   */
  async startSession(videoId: string): Promise<WatchSessionStartResult> {
    if (!isSupabaseConfigured || !videoId) {
      return { success: false, allowed: false, error: 'Database unconfigured or video missing' };
    }

    try {
      const { data, error } = await supabase.rpc('start_watch_session', {
        p_video_id: videoId,
      });

      if (error) {
        return { success: false, allowed: false, error: error.message };
      }

      const res = data as {
        success?: boolean;
        allowed?: boolean;
        session_id?: string;
        reason?: string;
        error?: string;
        reused?: boolean;
      };

      if (!res || !res.success || !res.session_id || res.allowed === false) {
        return {
          success: false,
          allowed: false,
          reason: res?.reason || 'SESSION_AUTHORIZATION_FAILED',
          error: res?.error || 'Failed to start authorized session',
        };
      }

      return {
        success: true,
        allowed: true,
        sessionId: res.session_id,
        reason: res.reason,
        reused: Boolean(res.reused),
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error starting session';
      return { success: false, allowed: false, error: msg };
    }
  }

  /**
   * Sends heartbeat for active watch session to record verified playing duration (CRIT-43)
   */
  async heartbeatSession(sessionId: string): Promise<HeartbeatSessionResponse> {
    if (!isSupabaseConfigured || !sessionId) {
      return { success: false, error: 'Database unconfigured or session missing' };
    }

    try {
      const { data, error } = await supabase.rpc('heartbeat_watch_session', {
        p_session_id: sessionId,
      });

      if (error) {
        return { success: false, error: error.message };
      }

      const res = data as { success?: boolean; watched_seconds?: number; error?: string };
      return {
        success: Boolean(res?.success),
        watched_seconds: res?.watched_seconds,
        error: res?.error,
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error during session heartbeat';
      return { success: false, error: msg };
    }
  }

  /**
   * Finalizes an active watch session in watch_history_sessions table via RPC (CRIT-08)
   */
  async finalizeSession(
    sessionId: string,
    watchedSeconds: number,
    completed: boolean = false
  ): Promise<{ success: boolean; error?: string }> {
    if (!isSupabaseConfigured || !sessionId) {
      return { success: false, error: 'Database unconfigured or session missing' };
    }

    try {
      const { data, error } = await supabase.rpc('finalize_watch_session', {
        p_session_id: sessionId,
        p_watched_seconds: Math.max(0, Math.floor(watchedSeconds)),
        p_completed: completed,
      });

      if (error) {
        return { success: false, error: error.message };
      }

      const res = data as { success?: boolean; error?: string };
      return { success: Boolean(res?.success), error: res?.error };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error finalizing session';
      return { success: false, error: msg };
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
