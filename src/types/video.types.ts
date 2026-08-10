export type VideoVisibility = 'public' | 'private' | 'unlisted';

export interface Video {
  id: string;
  owner_id: string;
  title: string;
  description: string | null;
  category_id: string | null;
  video_url: string;
  thumbnail_url: string | null;
  duration: number; // in seconds
  view_count?: number;
  visibility: VideoVisibility;
  is_deleted: boolean;
  created_at: string;
  updated_at: string;
}

export interface VideoCreateInput {
  title: string;
  description?: string;
  category_id?: string;
  video_url: string;
  thumbnail_url?: string;
  duration?: number;
  visibility?: VideoVisibility;
}

export interface VideoUpdateInput {
  title?: string;
  description?: string;
  category_id?: string;
  video_url?: string;
  thumbnail_url?: string;
  duration?: number;
  visibility?: VideoVisibility;
}

export interface VideoFilterOptions {
  categoryId?: string;
  searchQuery?: string;
  visibility?: VideoVisibility;
  includeDeleted?: boolean;
}

export interface ServiceOperationResult<T = void> {
  success: boolean;
  data?: T;
  error?: string | null;
  affectedRows: number;
}
