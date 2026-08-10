import { Video } from './video.types';

export interface Favorite {
  id: string;
  user_id: string;
  video_id: string;
  created_at: string;
  video?: Video;
}
