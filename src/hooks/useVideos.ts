import { useState, useEffect, useCallback } from 'react';
import { Video, VideoFilterOptions } from '../types';
import { videoService } from '../services/video.service';

export function useVideos(options?: VideoFilterOptions) {
  const [videos, setVideos] = useState<Video[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const fetchVideos = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await videoService.getVideos(options);
      setVideos(data);
      setError(null);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Videolar yüklenemedi';
      setError(msg);
    } finally {
      setIsLoading(false);
    }
  }, [options?.categoryId, options?.searchQuery, options?.visibility, options?.includeDeleted]);

  useEffect(() => {
    fetchVideos();
  }, [fetchVideos]);

  return { videos, isLoading, error, refetch: fetchVideos };
}
