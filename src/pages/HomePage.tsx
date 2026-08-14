import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { MainLayout } from '../components/layout/MainLayout';
import { VideoGrid } from '../components/video/VideoGrid';
import { VideoPlayerModal } from '../components/video/VideoPlayerModal';
import { DEFAULT_CATEGORIES } from '../constants/categories.constants';
import { useVideos } from '../hooks/useVideos';
import { useAuth } from '../hooks/useAuth';
import { parentService } from '../services/parent.service';
import { Video } from '../types';
import { Sparkles, Search, Compass } from 'lucide-react';

export const HomePage: React.FC = () => {
  const { slug } = useParams<{ slug?: string }>();
  const { user } = useAuth();
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);
  const [allowedCategoryIds, setAllowedCategoryIds] = useState<string[] | null>(null);

  // Sync category selection with route slug
  useEffect(() => {
    if (slug) {
      const match = DEFAULT_CATEGORIES.find((c) => c.slug === slug);
      if (match) {
        setSelectedCategory(match.id);
      }
    }
  }, [slug]);

  // Load allowed categories if restricted by parent
  useEffect(() => {
    if (!user?.id) return;
    parentService.getSettings(user.id).then((settings) => {
      if (settings?.allowed_categories && settings.allowed_categories.length > 0) {
        setAllowedCategoryIds(settings.allowed_categories);
      } else {
        setAllowedCategoryIds(null);
      }
    });
  }, [user?.id]);

  const { videos, isLoading, refetch } = useVideos({
    categoryId: selectedCategory || undefined,
    searchQuery: searchQuery || undefined,
  });

  const visibleCategories = allowedCategoryIds
    ? DEFAULT_CATEGORIES.filter((c) => allowedCategoryIds.includes(c.id))
    : DEFAULT_CATEGORIES;

  const filteredVideos = allowedCategoryIds
    ? videos.filter((v) => !v.category_id || allowedCategoryIds.includes(v.category_id))
    : videos;

  return (
    <MainLayout>
      {/* Hero Banner */}
      <div className="relative overflow-hidden rounded-3xl bg-gradient-to-r from-amber-400 via-orange-400 to-amber-500 text-white p-8 sm:p-12 shadow-xl mb-10">
        <div className="relative z-10 max-w-2xl">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/20 backdrop-blur-md text-xs font-black tracking-wide uppercase mb-4">
            <Sparkles className="w-4 h-4 fill-white" />
            %100 Güvenli Aile Medya Alanı
          </div>
          <h1 className="text-3xl sm:text-5xl font-black tracking-tight leading-tight">
            Eğlenceli ve Eğitici İçerikler Burada!
          </h1>
          <p className="text-amber-100 text-sm sm:text-base font-medium mt-3 leading-relaxed">
            Ahmet Egemen&apos;in Köşesi ile masallar, eğitici çizgi filmler, doğa ve hayvan videoları elinizin altında.
          </p>
        </div>
      </div>

      {/* Search and Category Filter Section */}
      <div className="space-y-6 mb-10">
        {/* Search Bar */}
        <div className="relative max-w-xl">
          <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" />
          <input
            type="text"
            placeholder="Video veya konu ara..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-12 pr-4 py-3.5 rounded-2xl bg-white border border-amber-200/80 shadow-xs focus:outline-none focus:ring-2 focus:ring-amber-500 text-sm font-medium transition-all"
          />
        </div>

        {/* Categories Chips */}
        <div className="flex items-center gap-2 overflow-x-auto pb-2 scrollbar-none">
          <button
            onClick={() => setSelectedCategory(null)}
            className={`px-4 py-2.5 rounded-2xl font-bold text-xs shrink-0 transition-all flex items-center gap-2 ${
              selectedCategory === null
                ? 'bg-amber-500 text-white shadow-md'
                : 'bg-white text-slate-600 border border-amber-100 hover:bg-amber-50'
            }`}
          >
            <Compass className="w-4 h-4" />
            Tümü
          </button>

          {visibleCategories.map((cat) => (
            <button
              key={cat.id}
              onClick={() => setSelectedCategory(cat.id)}
              className={`px-4 py-2.5 rounded-2xl font-bold text-xs shrink-0 transition-all ${
                selectedCategory === cat.id
                  ? 'bg-amber-500 text-white shadow-md'
                  : 'bg-white text-slate-600 border border-amber-100 hover:bg-amber-50'
              }`}
            >
              {cat.title}
            </button>
          ))}
        </div>
      </div>

      {/* Video Grid */}
      <div className="space-y-4">
        <h2 className="text-xl font-black text-slate-800 tracking-tight">Öne Çıkan Videolar</h2>
        <VideoGrid
          videos={filteredVideos}
          onPlay={(v) => setActiveVideo(v)}
          onRefresh={refetch}
          isLoading={isLoading}
        />
      </div>

      {/* Video Player Modal */}
      <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
    </MainLayout>
  );
};
