import React from 'react';
import { Video } from '../../types';
import { VideoCard } from './VideoCard';
import { Tv } from 'lucide-react';

interface VideoGridProps {
  videos: Video[];
  onPlay: (video: Video) => void;
  onRefresh?: () => void;
  isLoading?: boolean;
}

export const VideoGrid: React.FC<VideoGridProps> = ({
  videos,
  onPlay,
  onRefresh,
  isLoading,
}) => {
  if (isLoading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        {[1, 2, 3, 4, 5, 6].map((i) => (
          <div key={i} className="bg-white rounded-3xl h-64 animate-pulse border border-amber-100" />
        ))}
      </div>
    );
  }

  if (videos.length === 0) {
    return (
      <div className="text-center py-16 bg-white rounded-3xl border border-dashed border-amber-200 p-8">
        <div className="w-16 h-16 rounded-3xl bg-amber-100 text-amber-600 flex items-center justify-center mx-auto mb-4">
          <Tv className="w-8 h-8" />
        </div>
        <h3 className="text-lg font-bold text-slate-800">Henüz Video Bulunmuyor</h3>
        <p className="text-sm text-slate-500 mt-1 max-w-sm mx-auto">
          Seçilen kategori veya arama kriterine uygun henüz eklenmiş video yok.
        </p>
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
      {videos.map((video) => (
        <VideoCard key={video.id} video={video} onPlay={onPlay} onRefresh={onRefresh} />
      ))}
    </div>
  );
};
