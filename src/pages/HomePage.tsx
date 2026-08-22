import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import { MainLayout } from '../components/layout/MainLayout';
import { VideoGrid } from '../components/video/VideoGrid';
import { VideoPlayerModal } from '../components/video/VideoPlayerModal';
import { DEFAULT_CATEGORIES } from '../constants/categories.constants';
import { useVideos } from '../hooks/useVideos';
import { useAuth } from '../hooks/useAuth';
import { parentService } from '../services/parent.service';
import { parentLinkService } from '../services/parentLink.service';
import { Video } from '../types';
import { Sparkles, Search, Compass, Link2, CheckCircle2 } from 'lucide-react';

export const HomePage: React.FC = () => {
  const { slug } = useParams<{ slug?: string }>();
  const { user, role } = useAuth();
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);
  const [allowedCategoryIds, setAllowedCategoryIds] = useState<string[] | null>(null);
  const [inviteCode, setInviteCode] = useState<string | null>(null);
  const [inviteExpiresAt, setInviteExpiresAt] = useState<string | null>(null);
  const [inviteError, setInviteError] = useState<string | null>(null);
  const [isGeneratingInvite, setIsGeneratingInvite] = useState(false);

  useEffect(() => {
    if (slug) {
      const match = DEFAULT_CATEGORIES.find((category) => category.slug === slug);
      setSelectedCategory(match?.id ?? null);
    } else {
      setSelectedCategory(null);
    }
  }, [slug]);

  useEffect(() => {
    if (!user?.id || role !== 'child') {
      setAllowedCategoryIds(null);
      return;
    }

    let isMounted = true;
    parentService.getEffectiveParentalSettings().then((settings) => {
      if (!isMounted) return;
      if (settings?.allowed_categories && settings.allowed_categories.length > 0) setAllowedCategoryIds(settings.allowed_categories);
      else setAllowedCategoryIds(null);
    }).catch(() => {
      if (isMounted) setAllowedCategoryIds(null);
    });

    return () => { isMounted = false; };
  }, [user?.id, role]);

  const { videos, isLoading, refetch } = useVideos({
    categoryId: selectedCategory || undefined,
    searchQuery: searchQuery || undefined,
  });

  const visibleCategories = allowedCategoryIds
    ? DEFAULT_CATEGORIES.filter((category) => allowedCategoryIds.includes(category.id))
    : DEFAULT_CATEGORIES;

  const filteredVideos = allowedCategoryIds
    ? videos.filter((video) => !video.category_id || allowedCategoryIds.includes(video.category_id))
    : videos;

  const generateInvite = async () => {
    setIsGeneratingInvite(true);
    setInviteError(null);
    const result = await parentLinkService.createChildInvite();
    setIsGeneratingInvite(false);
    if (result.success) {
      setInviteCode(result.code || null);
      setInviteExpiresAt(result.expires_at || null);
    } else {
      setInviteError(result.error || 'Bağlantı kodu oluşturulamadı.');
    }
  };

  return (
    <MainLayout>
      <section className="relative overflow-hidden rounded-[2rem] bg-slate-900 text-white p-7 sm:p-10 lg:p-12 shadow-xl mb-8">
        <div className="absolute -right-16 -top-16 w-56 h-56 rounded-full bg-blue-700/30 blur-3xl" />
        <div className="absolute -left-10 -bottom-20 w-48 h-48 rounded-full bg-cyan-500/20 blur-3xl" />
        <div className="relative z-10 max-w-3xl">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-white/10 border border-white/15 text-xs font-black tracking-wide uppercase mb-4"><Sparkles className="w-4 h-4 text-cyan-300" />%100 Güvenli Aile Medya Alanı</div>
          <h1 className="text-3xl sm:text-4xl lg:text-5xl font-black tracking-tight leading-tight">Eğlenceli ve Eğitici İçerikler Burada!</h1>
          <p className="text-slate-300 text-sm sm:text-base font-medium mt-4 leading-relaxed max-w-2xl">Ahmet Egemen&apos;in Köşesi ile masallar, eğitici çizgi filmler, doğa ve hayvan videoları elinizin altında.</p>
        </div>
      </section>

      {role === 'child' && (
        <section className="mb-8 p-5 sm:p-6 rounded-3xl bg-white border border-blue-100 shadow-sm">
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <h2 className="text-base font-black text-slate-800 flex items-center gap-2"><Link2 className="w-5 h-5 text-blue-600" />Ebeveyn Bağlantısı</h2>
              <p className="text-xs text-slate-500 mt-1">Ebeveyn hesabınızın sizi bağlayabilmesi için 30 dakika geçerli bir kod oluşturun.</p>
            </div>
            <button onClick={generateInvite} disabled={isGeneratingInvite} className="px-4 py-2.5 rounded-2xl bg-blue-600 hover:bg-blue-700 text-white text-xs font-black disabled:opacity-50">{isGeneratingInvite ? 'Oluşturuluyor...' : 'Bağlantı Kodu Oluştur'}</button>
          </div>
          {inviteError && <p className="mt-3 text-xs font-semibold text-rose-700">{inviteError}</p>}
          {inviteCode && (
            <div className="mt-4 p-4 rounded-2xl bg-blue-50 border border-blue-200">
              <div className="flex items-center gap-2 text-blue-800 text-xs font-bold"><CheckCircle2 className="w-4 h-4" />Kodu ebeveyn hesabınıza iletin.</div>
              <div className="mt-2 text-2xl tracking-[0.35em] font-black text-blue-900 select-all">{inviteCode}</div>
              {inviteExpiresAt && <p className="mt-1 text-[11px] text-blue-700">Son geçerlilik: {new Date(inviteExpiresAt).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}</p>}
            </div>
          )}
        </section>
      )}

      <section className="space-y-5 mb-9" aria-label="İçerik filtreleri">
        <div className="relative max-w-2xl"><Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-slate-400" /><input type="text" placeholder="Video veya konu ara..." value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} className="w-full pl-12 pr-4 py-3.5 rounded-2xl bg-white border border-slate-200 shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-600/30 focus:border-blue-600 text-sm font-medium transition-all" /></div>
        <div className="flex items-center gap-2 overflow-x-auto pb-2 scrollbar-none">
          <button onClick={() => setSelectedCategory(null)} aria-pressed={selectedCategory === null} className={`px-4 py-2.5 rounded-xl font-bold text-xs shrink-0 transition-all flex items-center gap-2 border ${selectedCategory === null ? 'bg-slate-900 text-white border-slate-900 shadow-sm' : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50 hover:border-slate-300'}`}><Compass className="w-4 h-4" /> Tümü</button>
          {visibleCategories.map((category) => <button key={category.id} onClick={() => setSelectedCategory(category.id)} aria-pressed={selectedCategory === category.id} className={`px-4 py-2.5 rounded-xl font-bold text-xs shrink-0 transition-all border ${selectedCategory === category.id ? 'bg-slate-900 text-white border-slate-900 shadow-sm' : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50 hover:border-slate-300'}`}>{category.title}</button>)}
        </div>
      </section>

      <section className="space-y-4">
        <div className="flex items-end justify-between gap-4"><div><p className="text-xs font-bold uppercase tracking-widest text-blue-700">Keşfet</p><h2 className="text-xl sm:text-2xl font-black text-slate-900 tracking-tight">Öne Çıkan Videolar</h2></div></div>
        <VideoGrid videos={filteredVideos} onPlay={setActiveVideo} onRefresh={refetch} isLoading={isLoading} />
      </section>

      <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
    </MainLayout>
  );
};