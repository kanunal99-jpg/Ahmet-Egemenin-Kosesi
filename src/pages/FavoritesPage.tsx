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
  const favoriteVideos = favorites.map((f) => f.video).filter((v): v is Video => Boolean(v && !v.is_deleted));

  return (
    <MainLayout>
      <div className="space-y-7">
        <header className="rounded-3xl bg-white border border-slate-200 p-6 sm:p-7 shadow-sm">
          <div className="flex items-center gap-4">
            <div className="w-12 h-12 rounded-2xl bg-blue-50 text-blue-700 flex items-center justify-center"><Heart className="w-6 h-6 fill-current" /></div>
            <div><p className="text-xs font-black uppercase tracking-widest text-blue-700">Kişisel alan</p><h1 className="text-2xl font-black text-slate-900">Favori Videolarım</h1><p className="text-sm text-slate-500 mt-1">Beğendiğiniz içeriklere hızlıca geri dönün.</p></div>
          </div>
        </header>
        <VideoGrid videos={favoriteVideos} onPlay={(v) => setActiveVideo(v)} onRefresh={refetch} isLoading={isLoading} />
      </div>
      <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
    </MainLayout>
  );
};
