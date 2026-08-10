import { Video } from './video.types';

export interface WatchHistory {
  id: string;
  user_id: string;
  video_id: string;
  progress_seconds: number;
  completed: boolean;
  updated_at: string;
  video?: Video;
}

export interface WatchProgressInput {
  video_id: string;
  progress_seconds: number;
  completed?: boolean;
}
