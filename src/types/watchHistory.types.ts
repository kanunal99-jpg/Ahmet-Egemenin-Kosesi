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

export interface WatchSessionStartResult {
  success: boolean;
  allowed?: boolean;
  sessionId?: string;
  reason?: string;
  error?: string;
  reused?: boolean;
}

export interface HeartbeatSessionResponse {
  success: boolean;
  watched_seconds?: number;
  error?: string;
}

export interface WatchHistorySession {
  id: string;
  user_id: string;
  video_id: string;
  started_at: string;
  ended_at: string | null;
  watched_seconds: number;
  completed: boolean;
  created_at: string;
}

export interface WatchProgressInput {
  video_id: string;
  progress_seconds: number;
  completed?: boolean;
}
