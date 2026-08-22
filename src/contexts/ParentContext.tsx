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
  const [isParentUnlocked, setIsParentUnlocked] = useState(false);
  const [failedAttempts, setFailedAttempts] = useState(0);
  const [lockoutRemainingSeconds, setLockoutRemainingSeconds] = useState(0);
  const [hasPin, setHasPin] = useState<boolean | null>(null);
  const [needsPinSetup, setNeedsPinSetup] = useState(false);

  const isLockedOut = lockoutRemainingSeconds > 0;

  const refreshSettings = async () => {
    if (!user?.id) return;

    try {
      const settings = await parentService.getSettings(user.id);
      if (!settings) return;

      setHasPin(settings.has_pin !== false);
      setNeedsPinSetup(settings.has_pin === false);

      if (settings.is_locked && settings.locked_until) {
        const diffMs = new Date(settings.locked_until).getTime() - Date.now();
        setLockoutRemainingSeconds(diffMs > 0 ? Math.ceil(diffMs / 1000) : 0);
      } else {
        setLockoutRemainingSeconds(0);
      }
    } catch {
      // Keep the current state on transient settings errors.
    }
  };

  useEffect(() => {
    setIsParentUnlocked(false);
    setFailedAttempts(0);
    setLockoutRemainingSeconds(0);
    setHasPin(null);
    setNeedsPinSetup(false);

    if (!user?.id) return;
    void refreshSettings();
  }, [user?.id]);

  useEffect(() => {
    if (lockoutRemainingSeconds <= 0) return undefined;
    const timer = setInterval(() => {
      setLockoutRemainingSeconds((prev) => (prev > 1 ? prev - 1 : 0));
    }, 1000);
    return () => clearInterval(timer);
  }, [lockoutRemainingSeconds]);

  const unlockParentMode = async (pin: string) => {
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
    }

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
      setLockoutRemainingSeconds(Math.floor(APP_CONFIG.PIN_LOCKOUT_MS / 1000));
    }

    return { success: false, error: res.message || 'Hatalı PIN!' };
  };

  const setupInitialPin = async (newPin: string) => {
    if (!user?.id) return { success: false, error: 'Oturum açılmamış.' };

    const res = await parentService.updatePin(user.id, newPin);
    if (!res.success) return { success: false, error: res.error || 'PIN oluşturulamadı.' };

    setIsParentUnlocked(true);
    setHasPin(true);
    setNeedsPinSetup(false);
    setFailedAttempts(0);
    setLockoutRemainingSeconds(0);
    return { success: true };
  };

  const lockParentMode = () => setIsParentUnlocked(false);

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
  if (!context) throw new Error('useParentContext must be used within a ParentProvider');
  return context;
};