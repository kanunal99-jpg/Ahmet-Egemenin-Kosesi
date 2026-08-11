import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { UserRole, UserProfile } from '../types';
import { authService } from '../services/auth.service';
import { supabase, isSupabaseConfigured } from '../services/supabase.client';

interface AuthContextType {
  user: { id: string; email?: string } | null;
  profile: UserProfile | null;
  role: UserRole;
  isLoading: boolean;
  error: string | null;
  signOut: () => Promise<void>;
  refreshSession: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<{ id: string; email?: string } | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [role, setRole] = useState<UserRole>('guest');
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const refreshSession = async () => {
    setIsLoading(true);
    try {
      const sessionData = await authService.getCurrentSession();
      setUser(sessionData.user);
      setProfile(sessionData.profile);
      setRole(sessionData.role);
      setError(null);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Session load failed';
      setError(msg);
      setUser(null);
      setProfile(null);
      setRole('guest');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    refreshSession();

    if (isSupabaseConfigured) {
      const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
        refreshSession();
      });

      return () => {
        subscription.unsubscribe();
      };
    }
  }, []);

  const handleSignOut = async () => {
    await authService.signOut();
    setUser(null);
    setProfile(null);
    setRole('guest');
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        role,
        isLoading,
        error,
        signOut: handleSignOut,
        refreshSession,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuthContext = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuthContext must be used within an AuthProvider');
  }
  return context;
};
