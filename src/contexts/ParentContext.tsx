import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { parentService } from '../services/parent.service';
import { useAuthContext } from './AuthContext';
import { APP_CONFIG } from '../constants/app.constants';

interface ParentContextType {
  isParentUnlocked: boolean;
  failedAttempts: number;
  isLockedOut: boolean;
  lockoutRemainingSeconds: number;
  unlockParentMode: (pin: string) => Promise<{ success: boolean; error?: string }>;
  lockParentMode: () => void;
}

const ParentContext = createContext<ParentContextType | undefined>(undefined);

export const ParentProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const { user } = useAuthContext();
  const [isParentUnlocked, setIsParentUnlocked] = useState<boolean>(false);
  const [failedAttempts, setFailedAttempts] = useState<number>(0);
  const [lockoutRemainingSeconds, setLockoutRemainingSeconds] = useState<number>(0);

  const isLockedOut = lockoutRemainingSeconds > 0;

  // Invariant: Always reset parent unlock status and session attempts when user switches or logs out
  useEffect(() => {
    setIsParentUnlocked(false);
    setFailedAttempts(0);
    setLockoutRemainingSeconds(0);

    if (!user?.id) return;

    // Check remote lockout state on mount or user switch
    let isMounted = true;
    parentService.getSettings(user.id).then((settings) => {
      if (!isMounted || !settings) return;
      if (settings.is_locked && settings.locked_until) {
        const diffMs = new Date(settings.locked_until).getTime() - Date.now();
        if (diffMs > 0) {
          const remainingSecs = Math.ceil(diffMs / 1000);
          setLockoutRemainingSeconds(remainingSecs);
        }
      }
    });

    return () => {
      isMounted = false;
    };
  }, [user?.id]);

  // Interval timer for local lockout countdown
  useEffect(() => {
    let timer: NodeJS.Timeout;
    if (lockoutRemainingSeconds > 0) {
      timer = setInterval(() => {
        setLockoutRemainingSeconds((prev) => (prev > 1 ? prev - 1 : 0));
      }, 1000);
    }
    return () => {
      if (timer) clearInterval(timer);
    };
  }, [lockoutRemainingSeconds]);

  const unlockParentMode = async (pin: string): Promise<{ success: boolean; error?: string }> => {
    if (isLockedOut) {
      return {
        success: false,
        error: `Çok fazla hatalı deneme! Lütfen ${lockoutRemainingSeconds} saniye bekleyin.`,
      };
    }

    const res = await parentService.verifyUserPin(user?.id, pin);

    if (res.success) {
      setIsParentUnlocked(true);
      setFailedAttempts(0);
      setLockoutRemainingSeconds(0);
      return { success: true };
    } else {
      if (res.isLocked) {
        // Authoritative database lockout policy is 15 minutes (900 seconds)
        setLockoutRemainingSeconds(Math.floor(APP_CONFIG.PIN_LOCKOUT_MS / 1000));
      }
      return {
        success: false,
        error: res.message || 'Hatalı PIN!',
      };
    }
  };

  const lockParentMode = () => {
    setIsParentUnlocked(false);
  };

  return (
    <ParentContext.Provider
      value={{
        isParentUnlocked,
        failedAttempts,
        isLockedOut,
        lockoutRemainingSeconds,
        unlockParentMode,
        lockParentMode,
      }}
    >
      {children}
    </ParentContext.Provider>
  );
};

export const useParentContext = (): ParentContextType => {
  const context = useContext(ParentContext);
  if (!context) {
    throw new Error('useParentContext must be used within a ParentProvider');
  }
  return context;
};

