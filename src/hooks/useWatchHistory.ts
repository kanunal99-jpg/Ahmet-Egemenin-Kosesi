import { useState, useEffect, useCallback } from 'react';
import { WatchHistory } from '../types';
import { watchHistoryService } from '../services/watchHistory.service';
import { useAuth } from './useAuth';

export function useWatchHistory() {
  const { user } = useAuth();
  const [history, setHistory] = useState<WatchHistory[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  const fetchHistory = useCallback(async () => {
    if (!user?.id) {
      setHistory([]);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      const data = await watchHistoryService.getUserHistory(user.id);
      setHistory(data);
    } catch {
      setHistory([]);
    } finally {
      setIsLoading(false);
    }
  }, [user?.id]);

  useEffect(() => {
    fetchHistory();
  }, [fetchHistory]);

  return { history, isLoading, refetch: fetchHistory };
}
