import React, { useState } from 'react';
import { MainLayout } from '../components/layout/MainLayout';
import { VideoGrid } from '../components/video/VideoGrid';
import { VideoPlayerModal } from '../components/video/VideoPlayerModal';
import { useWatchHistory } from '../hooks/useWatchHistory';
import { Video } from '../types';
import { History } from 'lucide-react';

export const WatchHistoryPage: React.FC = () => {
  const { history, isLoading, refetch } = useWatchHistory();
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);

  const historyVideos = history
    .map((h) => h.video)
    .filter((v): v is Video => Boolean(v && !v.is_deleted));

  return (
    <MainLayout>
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 rounded-2xl bg-blue-100 text-blue-500 flex items-center justify-center shadow-xs">
            <History className="w-6 h-6" />
          </div>
          <div>
            <h1 className="text-2xl font-black text-slate-800">İzleme Geçmişim</h1>
            <p className="text-xs text-slate-500 font-medium">Daha önce izlediğiniz tüm içerikler ve kaldığınız yer.</p>
          </div>
        </div>

        <VideoGrid
          videos={historyVideos}
          onPlay={(v) => setActiveVideo(v)}
          onRefresh={refetch}
          isLoading={isLoading}
        />
      </div>

      <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
    </MainLayout>
  );
};
