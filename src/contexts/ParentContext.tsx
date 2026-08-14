import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { parentService } from '../services/parent.service';
import { useAuthContext } from './AuthContext';
import { APP_CONFIG } from '../constants/app.constants';

interface ParentContextType {
  isParentUnlocked: boolean;
  failedAttempts: number;
  isLockedOut: boolean;
  lockoutRemainingSeconds: number;
  hasPin: boolean | null;
  needsPinSetup: boolean;
  unlockParentMode: (pin: string) => Promise<{ success: boolean; error?: string; needsSetup?: boolean }>;
  setupInitialPin: (newPin: string) => Promise<{ success: boolean; error?: string }>;
  lockParentMode: () => void;
  refreshSettings: () => Promise<void>;
}

const ParentContext = createContext<ParentContextType | undefined>(undefined);

export const ParentProvider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const { user } = useAuthContext();
  const [isParentUnlocked, setIsParentUnlocked] = useState<boolean>(false);
  const [failedAttempts, setFailedAttempts] = useState<number>(0);
  const [lockoutRemainingSeconds, setLockoutRemainingSeconds] = useState<number>(0);
  const [hasPin, setHasPin] = useState<boolean | null>(null);
  const [needsPinSetup, setNeedsPinSetup] = useState<boolean>(false);

  const isLockedOut = lockoutRemainingSeconds > 0;

  const refreshSettings = async () => {
    if (!user?.id) return;
    try {
      const settings = await parentService.getSettings(user.id);
      if (settings) {
        setHasPin(settings.has_pin !== false);
        setNeedsPinSetup(settings.has_pin === false);
        if (settings.is_locked && settings.locked_until) {
          const diffMs = new Date(settings.locked_until).getTime() - Date.now();
          if (diffMs > 0) {
            const remainingSecs = Math.ceil(diffMs / 1000);
            setLockoutRemainingSeconds(remainingSecs);
          }
        }
      }
    } catch {
      // Ignored - defaults preserved
    }
  };

  // Invariant: Always reset parent unlock status and session attempts when user switches or logs out
  useEffect(() => {
    setIsParentUnlocked(false);
    setFailedAttempts(0);
    setLockoutRemainingSeconds(0);
    setHasPin(null);
    setNeedsPinSetup(false);

    if (!user?.id) return;

    refreshSettings();
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

  const unlockParentMode = async (pin: string): Promise<{ success: boolean; error?: string; needsSetup?: boolean }> => {
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
      setHasPin(true);
      setNeedsPinSetup(false);
      return { success: true };
    } else {
      if (res.needsSetup) {
        setNeedsPinSetup(true);
        setHasPin(false);
        return {
          success: false,
          needsSetup: true,
          error: res.message || 'Lütfen önce Ebeveyn PIN kodunuzu oluşturun.',
        };
      }
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

  const setupInitialPin = async (newPin: string): Promise<{ success: boolean; error?: string }> => {
    if (!user?.id) {
      return { success: false, error: 'Oturum açılmamış.' };
    }

    const res = await parentService.updatePin(user.id, newPin);
    if (res.success) {
      setIsParentUnlocked(true);
      setHasPin(true);
      setNeedsPinSetup(false);
      setFailedAttempts(0);
      setLockoutRemainingSeconds(0);
      return { success: true };
    } else {
      return { success: false, error: res.error || 'PIN oluşturulamadı.' };
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
        hasPin,
        needsPinSetup,
        unlockParentMode,
        setupInitialPin,
        lockParentMode,
        refreshSettings,
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
