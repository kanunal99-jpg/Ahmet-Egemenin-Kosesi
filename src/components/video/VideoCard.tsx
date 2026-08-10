import React, { useState } from 'react';
import { Video } from '../../types';
import { getYouTubeThumbnail } from '../../utils/youtube.utils';
import { formatDuration } from '../../utils/formatters.utils';
import { Play, Heart, Trash2, Edit3, AlertTriangle } from 'lucide-react';
import { useAuth } from '../../hooks/useAuth';
import { videoService } from '../../services/video.service';
import { favoriteService } from '../../services/favorite.service';

interface VideoCardProps {
  video: Video;
  onPlay: (video: Video) => void;
  onRefresh?: () => void;
  isFavoriteInitial?: boolean;
}

export const VideoCard: React.FC<VideoCardProps> = ({
  video,
  onPlay,
  onRefresh,
  isFavoriteInitial = false,
}) => {
  const { user, role } = useAuth();
  const [isFavorite, setIsFavorite] = useState<boolean>(isFavoriteInitial);
  const [isDeleting, setIsDeleting] = useState<boolean>(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState<boolean>(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const isPublisherOrAdmin = role === 'publisher' || role === 'admin';
  const canManage = user && isPublisherOrAdmin && (video.owner_id === user.id || role === 'admin');

  const thumbnailUrl = video.thumbnail_url || getYouTubeThumbnail(video.video_url);

  const handleToggleFavorite = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!user) return;

    const res = await favoriteService.toggleFavorite(user.id, video.id);
    if (res.success && res.data) {
      setIsFavorite(res.data.isFavorite);
    }
  };

  /**
   * Strict Soft Delete trigger
   */
  const handleConfirmSoftDelete = async (e: React.MouseEvent) => {
    e.stopPropagation();
    setIsDeleting(true);
    setDeleteError(null);

    const result = await videoService.softDeleteVideo(video.id);
    setIsDeleting(false);

    if (result.success && result.affectedRows > 0) {
      setShowDeleteConfirm(false);
      if (onRefresh) onRefresh();
    } else {
      setDeleteError(result.error || 'Silme işlemi gerçekleştirilemedi (0 satır etkilendi).');
    }
  };

  return (
    <div className="group bg-white rounded-3xl overflow-hidden border border-amber-100/80 shadow-sm hover:shadow-xl transition-all duration-300 flex flex-col relative">
      {/* Thumbnail Container */}
      <div className="relative aspect-video overflow-hidden cursor-pointer" onClick={() => onPlay(video)}>
        <img
          src={thumbnailUrl}
          alt={video.title}
          referrerPolicy="no-referrer"
          className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500"
        />
        <div className="absolute inset-0 bg-gradient-to-t from-slate-900/60 via-transparent to-black/20 group-hover:bg-slate-900/40 transition-colors" />

        {/* Play Icon Overlay */}
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="w-14 h-14 rounded-full bg-amber-500/90 group-hover:bg-amber-500 text-white flex items-center justify-center shadow-lg transform group-hover:scale-110 transition-all">
            <Play className="w-7 h-7 fill-white ml-1" />
          </div>
        </div>

        {/* Duration Badge */}
        {video.duration > 0 && (
          <div className="absolute bottom-3 right-3 px-2.5 py-1 bg-slate-900/80 backdrop-blur-xs text-white text-xs font-mono font-bold rounded-xl">
            {formatDuration(video.duration)}
          </div>
        )}

        {/* Favorite Button */}
        {user && (
          <button
            onClick={handleToggleFavorite}
            className={`absolute top-3 right-3 p-2.5 rounded-2xl backdrop-blur-md transition-all ${
              isFavorite
                ? 'bg-rose-500 text-white shadow-md'
                : 'bg-white/80 text-slate-700 hover:bg-white hover:text-rose-500'
            }`}
            title={isFavorite ? 'Favorilerden Çıkar' : 'Favorilere Ekle'}
          >
            <Heart className={`w-4 h-4 ${isFavorite ? 'fill-white' : ''}`} />
          </button>
        )}
      </div>

      {/* Card Content */}
      <div className="p-5 flex flex-col flex-grow">
        <h3 className="font-bold text-slate-800 text-base line-clamp-2 leading-snug group-hover:text-amber-600 transition-colors">
          {video.title}
        </h3>
        {video.description && (
          <p className="text-xs text-slate-500 line-clamp-2 mt-1.5 leading-relaxed">
            {video.description}
          </p>
        )}

        <div className="mt-auto pt-4 flex items-center justify-between border-t border-slate-100">
          <button
            onClick={() => onPlay(video)}
            className="text-xs font-bold text-amber-600 hover:text-amber-700 flex items-center gap-1"
          >
            İzle
            <Play className="w-3 h-3 fill-current" />
          </button>

          {/* Management actions if authorized owner/publisher */}
          {canManage && (
            <div className="flex items-center gap-1.5">
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setShowDeleteConfirm(true);
                }}
                className="p-1.5 rounded-xl text-slate-400 hover:bg-rose-50 hover:text-rose-600 transition-colors"
                title="Videoyu Sil (Soft Delete)"
              >
                <Trash2 className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Soft Delete Confirmation Modal Overlay */}
      {showDeleteConfirm && (
        <div className="absolute inset-0 z-30 bg-slate-900/90 backdrop-blur-xs p-4 flex flex-col justify-center text-center text-white">
          <AlertTriangle className="w-10 h-10 text-rose-400 mx-auto mb-2" />
          <h4 className="font-bold text-sm">Videoyu Sil?</h4>
          <p className="text-[11px] text-slate-300 mt-1 mb-4">
            Bu video gizlenecektir. İzleme geçmişiniz ve favorileriniz korunur.
          </p>

          {deleteError && (
            <p className="text-xs text-rose-300 bg-rose-950/60 p-2 rounded-xl mb-3">
              {deleteError}
            </p>
          )}

          <div className="flex gap-2 justify-center">
            <button
              onClick={(e) => {
                e.stopPropagation();
                setShowDeleteConfirm(false);
              }}
              className="px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-xs font-bold rounded-xl"
            >
              İptal
            </button>
            <button
              onClick={handleConfirmSoftDelete}
              disabled={isDeleting}
              className="px-3 py-1.5 bg-rose-600 hover:bg-rose-700 disabled:opacity-50 text-xs font-bold rounded-xl flex items-center gap-1"
            >
              {isDeleting ? 'Siliniyor...' : 'Evet, Sil'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
