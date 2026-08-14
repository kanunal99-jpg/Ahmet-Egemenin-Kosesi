export interface ParentChild {
  id: string;
  childId: string;
  childName?: string;
  createdAt: string;
}

export type ReportTimePeriod =
  | 'daily'
  | 'weekly'
  | 'monthly'
  | '3months'
  | '6months'
  | '9months'
  | '12months';

export interface ParentSettings {
  id: string;
  user_id: string;
  failed_attempts: number;
  locked_until: string | null;
  is_locked: boolean;
  has_pin?: boolean;
  pin_failed_attempts?: number;
  pin_locked_until?: string | null;
  daily_time_limit_minutes: number | null;
  allowed_categories: string[] | null;
  bedtime_start?: string | null;
  bedtime_end?: string | null;
  created_at: string;
  updated_at: string;
}


export interface CategoryUsageStats {
  categoryId: string;
  categoryTitle: string;
  watchTimeSeconds: number;
  videoCount: number;
}

export interface UsageReportData {
  period: ReportTimePeriod;
  totalWatchTimeSeconds: number;
  watchedVideosCount: number;
  completedVideosCount: number;
  categoryStats: CategoryUsageStats[];
  topWatchedVideos: {
    videoId: string;
    title: string;
    watchCount: number;
    totalSeconds: number;
  }[];
}
