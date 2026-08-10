export type UserRole = 'child' | 'parent' | 'publisher' | 'admin' | 'guest' | 'GUEST';

export interface UserProfile {
  id: string;
  first_name: string | null;
  last_name: string | null;
  avatar_path: string | null;
  role: UserRole;
  created_at: string;
  updated_at: string;
}

export interface AuthState {
  user: { id: string; email?: string } | null;
  profile: UserProfile | null;
  role: UserRole;
  isLoading: boolean;
  error: string | null;
}
