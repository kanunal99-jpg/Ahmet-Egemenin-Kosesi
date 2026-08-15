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

  async getMyVideos(): Promise<Video[]> {
    if (!isSupabaseConfigured) return [];

    try {
      const { data: userData } = await supabase.auth.getUser();
      const currentUserId = userData?.user?.id;
      if (!currentUserId) return [];

      const { data, error } = await supabase
        .from('videos')
        .select('*')
        .eq('owner_id', currentUserId)
        .eq('is_deleted', false)
        .order('created_at', { ascending: false });

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

  /**
   * Hardened Video Creation via Generic create_video RPC
   * Client cannot pass owner_id, role, or internal timestamps.
   */
  async createVideo(input: VideoCreateInput): Promise<ServiceOperationResult<Video>> {
    if (!isSupabaseConfigured) {
      return { success: false, error: 'Database is not configured.', affectedRows: 0 };
    }

    try {
      const { data, error } = await supabase.rpc('create_video', {
        p_title: input.title,
        p_description: input.description || '',
        p_category_id: input.category_id || null,
        p_video_url: input.video_url,
        p_thumbnail_url: input.thumbnail_url || '',
        p_duration: input.duration || 0,
        p_visibility: input.visibility || 'public',
      });

      if (error) {
        return { success: false, error: error.message, affectedRows: 0 };
      }

      const res = data as { success: boolean; video_id?: string; error?: string };
      if (!res.success || !res.video_id) {
        return { success: false, error: res.error || 'Video creation failed.', affectedRows: 0 };
      }

      // Fetch the created video record
      const createdVideo = await this.getVideoById(res.video_id);
      return {
        success: true,
        data: createdVideo || undefined,
        affectedRows: 1,
      };
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: errorMessage, affectedRows: 0 };
    }
  }

  /**
   * Hardened Video Update via Generic update_video RPC
   * Server strictly enforces ownership or admin role.
   */
  async updateVideo(id: string, input: VideoUpdateInput): Promise<ServiceOperationResult<Video>> {
    if (!isSupabaseConfigured) {
      return { success: false, error: 'Database is not configured.', affectedRows: 0 };
    }

    try {
      const { data, error } = await supabase.rpc('update_video', {
        p_video_id: id,
        p_title: input.title !== undefined ? input.title : null,
        p_description: input.description !== undefined ? input.description : null,
        p_category_id: input.category_id !== undefined ? input.category_id : null,
        p_video_url: input.video_url !== undefined ? input.video_url : null,
        p_thumbnail_url: input.thumbnail_url !== undefined ? input.thumbnail_url : null,
        p_duration: input.duration !== undefined ? input.duration : null,
        p_visibility: input.visibility !== undefined ? input.visibility : null,
      });

      if (error) {
        return { success: false, error: error.message, affectedRows: 0 };
      }

      const res = data as { success: boolean; error?: string };
      if (!res.success) {
        return { success: false, error: res.error || 'Video update failed.', affectedRows: 0 };
      }

      const updatedVideo = await this.getVideoById(id);
      return {
        success: true,
        data: updatedVideo || undefined,
        affectedRows: 1,
      };
    } catch (err: unknown) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: errorMessage, affectedRows: 0 };
    }
  }

  /**
   * STRICT SOFT DELETE via Generic soft_delete_video RPC
   * Physical DELETE is disabled at database level.
   */
  async softDeleteVideo(id: string): Promise<ServiceOperationResult> {
    if (!isSupabaseConfigured) {
      return { success: false, error: 'Database is not configured.', affectedRows: 0 };
    }

    try {
      const { data, error } = await supabase.rpc('soft_delete_video', {
        p_video_id: id,
      });

      if (error) {
        return { success: false, error: error.message, affectedRows: 0 };
      }

      const res = data as { success: boolean; error?: string };
      if (!res.success) {
        return { success: false, error: res.error || 'Video deletion failed.', affectedRows: 0 };
      }

      return { success: true, affectedRows: 1 };
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
