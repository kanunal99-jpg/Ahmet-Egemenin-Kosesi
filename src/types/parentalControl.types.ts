export type PlaybackAuthorizationReason =
  | 'OK'
  | 'NOT_AUTHENTICATED'
  | 'NOT_CHILD'
  | 'VIDEO_NOT_FOUND'
  | 'VIDEO_DELETED'
  | 'CATEGORY_RESTRICTED'
  | 'BEDTIME'
  | 'DAILY_LIMIT'
  | 'SETTINGS_UNAVAILABLE'
  | 'AUTHORIZATION_ERROR'
  | 'SESSION_AUTHORIZATION_FAILED';

export interface PlaybackAuthorization {
  allowed: boolean;
  reason: PlaybackAuthorizationReason;
  message?: string;
  error?: string;
}
