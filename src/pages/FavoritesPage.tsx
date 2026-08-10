import React, { useState } from 'react';
import { MainLayout } from '../components/layout/MainLayout';
import { VideoGrid } from '../components/video/VideoGrid';
import { VideoPlayerModal } from '../components/video/VideoPlayerModal';
import { useFavorites } from '../hooks/useFavorites';
import { Video } from '../types';
import { Heart } from 'lucide-react';

export const FavoritesPage: React.FC = () => {
  const { favorites, isLoading, refetch } = useFavorites();
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);

  const favoriteVideos = favorites
    .map((f) => f.video)
    .filter((v): v is Video => Boolean(v && !v.is_deleted));

  return (
    <MainLayout>
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-2xl bg-rose-100 text-rose-500 flex items-center justify-center shadow-xs">
            <Heart className="w-6 h-6 fill-current" />
          </div>
          <div>
            <h1 className="text-2xl font-black text-slate-800">Favori Videolarım</h1>
            <p className="text-xs text-slate-500 font-medium">Beğendiğiniz tüm içerikler burada listenir.</p>
          </div>
        </div>

        <VideoGrid
          videos={favoriteVideos}
          onPlay={(v) => setActiveVideo(v)}
          onRefresh={refetch}
          isLoading={isLoading}
        />
      </div>

      <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
    </MainLayout>
  );
};
