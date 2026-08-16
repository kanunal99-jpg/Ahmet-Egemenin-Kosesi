import React, { useState, useEffect, useCallback } from 'react';
import { Video, VideoCreateInput, VideoUpdateInput, VideoVisibility } from '../../types';
import { videoService } from '../../services/video.service';
import { DEFAULT_CATEGORIES } from '../../constants/categories.constants';
import { VideoCard } from '../video/VideoCard';
import { VideoPlayerModal } from '../video/VideoPlayerModal';
import {
  Plus,
  Edit2,
  Trash2,
  AlertTriangle,
  CheckCircle2,
  Film,
  Eye,
  Lock,
  Globe,
  Loader2,
  X,
} from 'lucide-react';

export const ParentVideoManager: React.FC = () => {
  const [myVideos, setMyVideos] = useState<Video[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);

  // Modal / Form state
  const [isFormOpen, setIsFormOpen] = useState<boolean>(false);
  const [editingVideo, setEditingVideo] = useState<Video | null>(null);
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);

  // Delete modal state
  const [deletingVideo, setDeletingVideo] = useState<Video | null>(null);
  const [isDeleting, setIsDeleting] = useState<boolean>(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  // Form inputs
  const [title, setTitle] = useState<string>('');
  const [description, setDescription] = useState<string>('');
  const [categoryId, setCategoryId] = useState<string>(DEFAULT_CATEGORIES[0]?.id || '');
  const [videoUrl, setVideoUrl] = useState<string>('');
  const [thumbnailUrl, setThumbnailUrl] = useState<string>('');
  const [durationMinutes, setDurationMinutes] = useState<number>(5);
  const [visibility, setVisibility] = useState<VideoVisibility>('public');

  const fetchMyVideos = useCallback(async () => {
    setIsLoading(true);
    try {
      const videos = await videoService.getMyVideos();
      setMyVideos(videos);
    } catch {
      setMyVideos([]);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchMyVideos();
  }, [fetchMyVideos]);

  const openCreateModal = () => {
    setEditingVideo(null);
    setTitle('');
    setDescription('');
    setCategoryId(DEFAULT_CATEGORIES[0]?.id || '');
    setVideoUrl('');
    setThumbnailUrl('');
    setDurationMinutes(5);
    setVisibility('public');
    setFormError(null);
    setFormSuccess(null);
    setIsFormOpen(true);
  };

  const openEditModal = (video: Video) => {
    setEditingVideo(video);
    setTitle(video.title || '');
    setDescription(video.description || '');
    setCategoryId(video.category_id || DEFAULT_CATEGORIES[0]?.id || '');
    setVideoUrl(video.video_url || '');
    setThumbnailUrl(video.thumbnail_url || '');
    setDurationMinutes(Math.max(1, Math.round((video.duration || 0) / 60)));
    setVisibility(video.visibility || 'public');
    setFormError(null);
    setFormSuccess(null);
    setIsFormOpen(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);
    setFormSuccess(null);

    if (!title.trim()) {
      setFormError('Lütfen video başlığını giriniz.');
      return;
    }
    if (!videoUrl.trim()) {
      setFormError('Lütfen video URL adresini giriniz.');
      return;
    }

    setIsSubmitting(true);
    try {
      const durationSeconds = Math.max(0, durationMinutes * 60);

      if (editingVideo) {
        // Update
        const updateInput: VideoUpdateInput = {
          title: title.trim(),
          description: description.trim() || undefined,
          category_id: categoryId || undefined,
          video_url: videoUrl.trim(),
          thumbnail_url: thumbnailUrl.trim() || undefined,
          duration: durationSeconds,
          visibility,
        };

        const result = await videoService.updateVideo(editingVideo.id, updateInput);
        if (!result.success) {
          setFormError(result.error || 'Video güncellenirken bir hata oluştu.');
          return;
        }

        setFormSuccess('Video başarıyla güncellendi.');
      } else {
        // Create
        const createInput: VideoCreateInput = {
          title: title.trim(),
          description: description.trim() || undefined,
          category_id: categoryId || undefined,
          video_url: videoUrl.trim(),
          thumbnail_url: thumbnailUrl.trim() || undefined,
          duration: durationSeconds,
          visibility,
        };

        const result = await videoService.createVideo(createInput);
        if (!result.success) {
          setFormError(result.error || 'Video eklenirken bir hata oluştu.');
          return;
        }

        setFormSuccess('Video başarıyla oluşturuldu ve yayınlandı.');
      }

      await fetchMyVideos();
      setTimeout(() => {
        setIsFormOpen(false);
      }, 1000);
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'Beklenmeyen bir hata oluştu.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleConfirmDelete = async () => {
    if (!deletingVideo) return;
    setIsDeleting(true);
    setDeleteError(null);

    try {
      const result = await videoService.softDeleteVideo(deletingVideo.id);
      if (!result.success) {
        setDeleteError(result.error || 'Video silinirken bir hata oluştu.');
        return;
      }
      setDeletingVideo(null);
      await fetchMyVideos();
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Silme işlemi sırasında hata oluştu.');
    } finally {
      setIsDeleting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Header & Add Button */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 bg-white p-6 rounded-2xl border border-slate-100 shadow-sm">
        <div>
          <h2 className="text-xl font-bold text-slate-800 flex items-center gap-2">
            <Film className="w-5 h-5 text-indigo-600" />
            Video Yönetimi
          </h2>
          <p className="text-slate-500 text-sm mt-1">
            Yüklediğiniz videoları yönetin, yeni video ekleyin veya mevcutları düzenleyin.
          </p>
        </div>
        <button
          onClick={openCreateModal}
          className="flex items-center gap-2 px-5 py-2.5 bg-indigo-600 hover:bg-indigo-700 active:bg-indigo-800 text-white font-medium rounded-xl shadow-sm transition-colors text-sm"
        >
          <Plus className="w-4 h-4" />
          Yeni Video Ekle
        </button>
      </div>

      {/* Video List */}
      {isLoading ? (
        <div className="flex items-center justify-center p-12 bg-white rounded-2xl border border-slate-100 shadow-sm">
          <Loader2 className="w-8 h-8 animate-spin text-indigo-600" />
          <span className="ml-3 text-slate-600 font-medium">Videolar yükleniyor...</span>
        </div>
      ) : myVideos.length === 0 ? (
        <div className="text-center p-12 bg-white rounded-2xl border border-slate-100 shadow-sm">
          <div className="w-16 h-16 mx-auto bg-indigo-50 text-indigo-600 rounded-full flex items-center justify-center mb-4">
            <Film className="w-8 h-8" />
          </div>
          <h3 className="text-lg font-bold text-slate-800">Henüz video eklemediniz</h3>
          <p className="text-slate-500 text-sm max-w-md mx-auto mt-2 mb-6">
            Çocuğunuz veya aileniz için güvenli YouTube videoları ekleyerek burada listeleyebilirsiniz.
          </p>
          <button
            onClick={openCreateModal}
            className="inline-flex items-center gap-2 px-5 py-2.5 bg-indigo-600 hover:bg-indigo-700 text-white font-medium rounded-xl shadow-sm transition-colors text-sm"
          >
            <Plus className="w-4 h-4" />
            İlk Videoyu Ekle
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {myVideos.map((video) => (
            <div
              key={video.id}
              className="bg-white rounded-2xl border border-slate-100 overflow-hidden shadow-sm flex flex-col justify-between hover:shadow-md transition-shadow"
            >
              <div>
                <VideoCard video={video} onPlay={(v) => setActiveVideo(v)} />
              </div>
              <div className="p-4 border-t border-slate-100 flex items-center justify-between gap-2 bg-slate-50/50">
                <div className="flex items-center gap-1.5 text-xs text-slate-500 font-medium">
                  {video.visibility === 'public' ? (
                    <>
                      <Globe className="w-3.5 h-3.5 text-emerald-600" />
                      <span>Herkese Açık</span>
                    </>
                  ) : video.visibility === 'unlisted' ? (
                    <>
                      <Eye className="w-3.5 h-3.5 text-amber-600" />
                      <span>Liste Dışı</span>
                    </>
                  ) : (
                    <>
                      <Lock className="w-3.5 h-3.5 text-slate-600" />
                      <span>Gizli</span>
                    </>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => openEditModal(video)}
                    className="p-2 text-slate-600 hover:text-indigo-600 hover:bg-indigo-50 rounded-lg transition-colors"
                    title="Düzenle"
                  >
                    <Edit2 className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => setDeletingVideo(video)}
                    className="p-2 text-slate-600 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                    title="Sil"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Video Player Modal */}
      {activeVideo && (
        <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
      )}

      {/* Create / Edit Modal */}
      {isFormOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs">
          <div className="bg-white rounded-2xl max-w-xl w-full p-6 shadow-xl border border-slate-100 max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between pb-4 border-b border-slate-100 mb-5">
              <h3 className="text-lg font-bold text-slate-800 flex items-center gap-2">
                <Film className="w-5 h-5 text-indigo-600" />
                {editingVideo ? 'Videoyu Düzenle' : 'Yeni Video Ekle'}
              </h3>
              <button
                onClick={() => setIsFormOpen(false)}
                className="p-1.5 text-slate-400 hover:text-slate-600 rounded-lg"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {formError && (
              <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-xl flex items-center gap-2">
                <AlertTriangle className="w-4 h-4 shrink-0" />
                <span>{formError}</span>
              </div>
            )}

            {formSuccess && (
              <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 text-sm rounded-xl flex items-center gap-2">
                <CheckCircle2 className="w-4 h-4 shrink-0" />
                <span>{formSuccess}</span>
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Video Başlığı *
                </label>
                <input
                  type="text"
                  required
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="Örn: Eğitici Çizgi Film - Renkleri Öğrenelim"
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  YouTube / Video URL *
                </label>
                <input
                  type="url"
                  required
                  value={videoUrl}
                  onChange={(e) => setVideoUrl(e.target.value)}
                  placeholder="https://www.youtube.com/watch?v=..."
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Kategori
                  </label>
                  <select
                    value={categoryId}
                    onChange={(e) => setCategoryId(e.target.value)}
                    className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    {DEFAULT_CATEGORIES.map((cat) => (
                      <option key={cat.id} value={cat.id}>
                        {cat.title}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Görünürlük
                  </label>
                  <select
                    value={visibility}
                    onChange={(e) => setVisibility(e.target.value as VideoVisibility)}
                    className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="public">Herkese Açık</option>
                    <option value="unlisted">Liste Dışı</option>
                    <option value="private">Gizli</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Tahmini Süre (Dakika)
                  </label>
                  <input
                    type="number"
                    min="0"
                    value={durationMinutes}
                    onChange={(e) => setDurationMinutes(parseInt(e.target.value) || 0)}
                    className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Thumbnail URL (İsteğe Bağlı)
                  </label>
                  <input
                    type="url"
                    value={thumbnailUrl}
                    onChange={(e) => setThumbnailUrl(e.target.value)}
                    placeholder="https://img.youtube.com/vi/.../hqdefault.jpg"
                    className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Açıklama (İsteğe Bağlı)
                </label>
                <textarea
                  rows={3}
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Video hakkında kısa açıklama..."
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 resize-none"
                />
              </div>

              <div className="flex items-center justify-end gap-3 pt-4 border-t border-slate-100">
                <button
                  type="button"
                  onClick={() => setIsFormOpen(false)}
                  disabled={isSubmitting}
                  className="px-4 py-2.5 text-slate-600 hover:bg-slate-100 rounded-xl text-sm font-medium transition-colors"
                >
                  İptal
                </button>
                <button
                  type="submit"
                  disabled={isSubmitting}
                  className="flex items-center gap-2 px-5 py-2.5 bg-indigo-600 hover:bg-indigo-700 active:bg-indigo-800 text-white text-sm font-medium rounded-xl shadow-sm transition-colors disabled:opacity-50"
                >
                  {isSubmitting ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin" />
                      <span>Kaydediliyor...</span>
                    </>
                  ) : (
                    <span>{editingVideo ? 'Güncelle' : 'Kaydet'}</span>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {deletingVideo && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-xl border border-slate-100">
            <div className="w-12 h-12 bg-red-50 text-red-600 rounded-full flex items-center justify-center mb-4">
              <AlertTriangle className="w-6 h-6" />
            </div>

            <h3 className="text-lg font-bold text-slate-800 mb-2">Videoyu Sil</h3>
            <p className="text-slate-600 text-sm mb-4">
              <strong>"{deletingVideo.title}"</strong> başlıklı videoyu kaldırmak istediğinize emin misiniz? Bu video güvenli şekilde listeden kaldırılacaktır.
            </p>

            {deleteError && (
              <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-sm rounded-xl">
                {deleteError}
              </div>
            )}

            <div className="flex items-center justify-end gap-3">
              <button
                onClick={() => setDeletingVideo(null)}
                disabled={isDeleting}
                className="px-4 py-2 text-slate-600 hover:bg-slate-100 rounded-xl text-sm font-medium transition-colors"
              >
                Vazgeç
              </button>
              <button
                onClick={handleConfirmDelete}
                disabled={isDeleting}
                className="flex items-center gap-2 px-4 py-2 bg-red-600 hover:bg-red-700 text-white text-sm font-medium rounded-xl shadow-sm transition-colors disabled:opacity-50"
              >
                {isDeleting ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    <span>Siliniyor...</span>
                  </>
                ) : (
                  <span>Evet, Sil</span>
                )}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
