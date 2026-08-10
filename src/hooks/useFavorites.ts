import { useState, useEffect, useCallback } from 'react';
import { Favorite } from '../types';
import { favoriteService } from '../services/favorite.service';
import { useAuth } from './useAuth';

export function useFavorites() {
  const { user } = useAuth();
  const [favorites, setFavorites] = useState<Favorite[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);

  const fetchFavorites = useCallback(async () => {
    if (!user?.id) {
      setFavorites([]);
      setIsLoading(false);
      return;
    }
    setIsLoading(true);
    try {
      const data = await favoriteService.getUserFavorites(user.id);
      setFavorites(data);
    } catch {
      setFavorites([]);
    } finally {
      setIsLoading(false);
    }
  }, [user?.id]);

  useEffect(() => {
    fetchFavorites();
  }, [fetchFavorites]);

  return { favorites, isLoading, refetch: fetchFavorites };
}
