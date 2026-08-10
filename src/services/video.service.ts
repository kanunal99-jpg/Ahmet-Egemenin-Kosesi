import { supabase, isSupabaseConfigured } from './supabase.client';
import {
  Video,
  VideoCreateInput,
  VideoUpdateInput,
  VideoFilterOptions,
  ServiceOperationResult,
} from '../types';

export class VideoService {
  async getVideos(options?: VideoFilterOptions): Promise<Video[]> {
    if (!isSupabaseConfigured) return [];

    try {
      let query = supabase.from('videos').select('*');

      if (!options?.includeDeleted) {
        query = query.eq('is_deleted', false);
      }

      if (options?.categoryId) {
        query = query.eq('category_id', options.categoryId);
      }

      if (options?.visibility) {
        query = query.eq('visibility', options.visibility);
      }

      if (options?.searchQuery) {
        query = query.ilike('title', `%${options.searchQuery}%`);
      }

      query = query.order('created_at', { ascending: false });

      const { data, error } = await query;
      if (error || !data) return [];
      return data as Video[];
    } catch {
      return [];
    }
  }

  async getVideoById(id: string): Promise<Video | null> {
    if (!isSupabaseConfigured) return null;

    try {
      const { data, error } = await supabase
        .from('videos')
        .select('*')
        .eq('id', id)
        .eq('is_deleted', false)
        .single();

      if (error || !data) return null;
      return data as Video;
    } catch {
      return null;
    }
  }

  async createVideo(ownerId: string, input: VideoCreateInput): Promise<ServiceOperationResult<Video>> {
    if (!isSupabaseConfigured) {
      return { success: false, error: 'Database is not configured.', affectedRows: 0 };
    }

    try {
      const payload = {
        owner_id: ownerId,
        title: input.title,
        description: input.description || null,
        category_id: input.category_id || null,
        video_url: input.video_url,
        thumbnail_url: input.thumbnail_url || null,
        duration: input.duration || 0,
        visibility: input.visibility || 'public',
        is_deleted: false,
      };

      const { data, error } = await supabase.from('videos').insert(payload).select().single();

      if (error || !data) {
        return { success: false, error: error?.message || 'Video creation failed.', affectedRows: 0 };
      }

      return { success: true, data: data as Video, affectedRows: 1 };
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: errorMessage, affectedRows: 0 };
    }
  }

  async updateVideo(id: string, input: VideoUpdateInput): Promise<ServiceOperationResult<Video>> {
    if (!isSupabaseConfigured) {
      return { success: false, error: 'Database is not configured.', affectedRows: 0 };
    }

    try {
      const payload = {
        ...input,
        updated_at: new Date().toISOString(),
      };

      const { data, error, count } = await supabase
        .from('videos')
        .update(payload)
        .eq('id', id)
        .eq('is_deleted', false)
        .select();

      const affected = count ?? (data ? data.length : 0);

      if (error || affected === 0 || !data || data.length === 0) {
        return {
          success: false,
          error: error?.message || 'Update failed or video not found / already deleted.',
          affectedRows: affected,
        };
      }

      return { success: true, data: data[0] as Video, affectedRows: affected };
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: errorMessage, affectedRows: 0 };
    }
  }

  /**
   * STRICT SOFT DELETE implementation
   * Sets is_deleted = true and updated_at = now()
   * Verifies response error AND affected rows.
   */
  async softDeleteVideo(id: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured) {
      return { success: false, error: 'Database is not configured.', affectedRows: 0 };
    }

    try {
      const { data, error, count } = await supabase
        .from('videos')
        .update({
          is_deleted: true,
          updated_at: new Date().toISOString(),
        })
        .eq('id', id)
        .eq('is_deleted', false)
        .select();

      const affected = count ?? (data ? data.length : 0);

      // Strict validation: Must not have error AND affected rows must be > 0
      if (error) {
        return { success: false, error: error.message, affectedRows: 0 };
      }

      if (affected === 0 || !data || data.length === 0) {
        return {
          success: false,
          error: 'Process failed: Target video was not updated (either missing or already deleted).',
          affectedRows: 0,
        };
      }

      return { success: true, affectedRows: affected };
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: errorMessage, affectedRows: 0 };
    }
  }

  /**
   * Alias for softDeleteVideo - ensures physical DELETE is never executed.
   */
  async deleteVideo(id: string): Promise<ServiceOperationResult> {
    return this.softDeleteVideo(id);
  }

  /**
   * Increments video view_count securely via RPC (SECURITY DEFINER)
   */
  async incrementViewCount(videoId: string): Promise<void> {
    if (!isSupabaseConfigured || !videoId) return;
    try {
      await supabase.rpc('increment_video_view_count', { p_video_id: videoId });
    } catch (e) {
      console.error('Failed to increment view count:', e);
    }
  }
}

export const videoService = new VideoService();
