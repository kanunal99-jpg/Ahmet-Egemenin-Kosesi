export type UserRole = 'child' | 'parent' | 'publisher' | 'admin' | 'guest';

export interface UserProfile {
  id: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  role: UserRole;
  created_at: string;
  updated_at: string;
}

export type AuthSessionStatus =
  | 'NO_SESSION'
  | 'PROFILE_NOT_FOUND'
  | 'PROFILE_QUERY_ERROR'
  | 'PROFILE_FOUND';

export interface SessionResult {
  user: { id: string; email?: string } | null;
  profile: UserProfile | null;
  role: UserRole;
  status: AuthSessionStatus;
  error?: string | null;
}

export interface AuthState {
  user: { id: string; email?: string } | null;
  profile: UserProfile | null;
  role: UserRole;
  status: AuthSessionStatus;
  isLoading: boolean;
  error: string | null;
}
