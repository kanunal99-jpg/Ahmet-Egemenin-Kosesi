import { supabase, isSupabaseConfigured } from './supabase.client';
import { Favorite, ServiceOperationResult } from '../types';

export class FavoriteService {
  async getUserFavorites(userId: string): Promise<Favorite[]> {
    if (!isSupabaseConfigured || !userId) return [];

    try {
      const { data, error } = await supabase
        .from('favorites')
        .select(`
          *,
          video:videos (*)
        `)
        .eq('user_id', userId)
        .order('created_at', { ascending: false });

      if (error || !data) return [];
      return data as Favorite[];
    } catch {
      return [];
    }
  }

  async isFavorite(userId: string, videoId: string): Promise<boolean> {
    if (!isSupabaseConfigured || !userId || !videoId) return false;

    try {
      const { data, error } = await supabase
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('video_id', videoId)
        .maybeSingle();

      return Boolean(!error && data);
    } catch {
      return false;
    }
  }

  async toggleFavorite(userId: string, videoId: string): Promise<ServiceOperationResult<{ isFavorite: boolean }>> {
    if (!isSupabaseConfigured || !userId) {
      return { success: false, error: 'Database unconfigured or user missing', affectedRows: 0 };
    }

    try {
      const currentlyFavorite = await this.isFavorite(userId, videoId);

      if (currentlyFavorite) {
        const { data, error, count } = await supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('video_id', videoId)
          .select();

        const affected = count ?? (data ? data.length : 0);
        if (error) {
          return { success: false, error: error.message, affectedRows: 0 };
        }
        return { success: true, data: { isFavorite: false }, affectedRows: affected };
      } else {
        const { data, error } = await supabase
          .from('favorites')
          .insert({ user_id: userId, video_id: videoId })
          .select()
          .single();

        if (error || !data) {
          return { success: false, error: error?.message || 'Add favorite failed', affectedRows: 0 };
        }
        return { success: true, data: { isFavorite: true }, affectedRows: 1 };
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Unknown error';
      return { success: false, error: msg, affectedRows: 0 };
    }
  }
}

export const favoriteService = new FavoriteService();
