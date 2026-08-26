import React, { createContext, useContext, useEffect, useState, useRef, ReactNode } from 'react';
import { UserRole, UserProfile, AuthSessionStatus } from '../types';
import { authService } from '../services/auth.service';
import { supabase, isSupabaseConfigured } from '../services/supabase.client';

interface AuthContextType {
  user: { id: string; email?: string } | null;
  profile: UserProfile | null;
  role: UserRole;
  authStatus: AuthSessionStatus;
  isLoading: boolean;
  error: string | null;
  signOut: () => Promise<void>;
  refreshSession: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);
const DEFAULT_ROLE: UserRole = 'child';

export const AuthProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<{ id: string; email?: string } | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [role, setRole] = useState<UserRole>(DEFAULT_ROLE);
  const [authStatus, setAuthStatus] = useState<AuthSessionStatus>('NO_SESSION');
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const requestSequenceRef = useRef<number>(0);

  const refreshSession = async () => {
    const sequenceId = ++requestSequenceRef.current;
    setIsLoading(true);

    try {
      const sessionData = await authService.getCurrentSession();
      if (sequenceId !== requestSequenceRef.current) return;

      setUser(sessionData.user);
      setProfile(sessionData.profile);
      setRole(sessionData.role);
      setAuthStatus(sessionData.status);

      if (sessionData.status === 'PROFILE_QUERY_ERROR') {
        setError(sessionData.error || 'Profil sorgulanırken veritabanı hatası oluştu.');
      } else {
        setError(null);
      }
    } catch (err: unknown) {
      if (sequenceId !== requestSequenceRef.current) return;
      const msg = err instanceof Error ? err.message : 'Oturum yüklenemedi';
      setError(msg);
      setUser(null);
      setProfile(null);
      setRole(DEFAULT_ROLE);
      setAuthStatus('PROFILE_QUERY_ERROR');
    } finally {
      if (sequenceId === requestSequenceRef.current) {
        setIsLoading(false);
      }
    }
  };

  useEffect(() => {
    void refreshSession();

    if (isSupabaseConfigured) {
      const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
        // Supabase auth callbacks must not perform awaited Supabase work inline.
        // Defer the profile/session refresh until after the callback returns.
        setTimeout(() => {
          void refreshSession();
        }, 0);
      });

      return () => {
        subscription.unsubscribe();
      };
    }
  }, []);

  const handleSignOut = async () => {
    requestSequenceRef.current++;
    await authService.signOut();
    setUser(null);
    setProfile(null);
    setRole(DEFAULT_ROLE);
    setAuthStatus('NO_SESSION');
    setError(null);
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        role,
        authStatus,
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
