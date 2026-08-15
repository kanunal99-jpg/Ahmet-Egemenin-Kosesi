import React, { useState, useEffect } from 'react';
import { MainLayout } from '../components/layout/MainLayout';
import { ReportTimePeriod, UsageReportData, Video } from '../types';
import {
  Shield,
  Key,
  BarChart3,
  CheckCircle2,
  Film,
  Sliders,
  Clock,
  Moon,
  Check,
  Heart,
  History,
  Lock,
} from 'lucide-react';
import { parentService } from '../services/parent.service';
import { useAuth } from '../hooks/useAuth';
import { useParent } from '../hooks/useParent';
import { useFavorites } from '../hooks/useFavorites';
import { useWatchHistory } from '../hooks/useWatchHistory';
import { formatDurationHuman } from '../utils/formatters.utils';
import { DEFAULT_CATEGORIES } from '../constants/categories.constants';
import { VideoGrid } from '../components/video/VideoGrid';
import { VideoPlayerModal } from '../components/video/VideoPlayerModal';

type ParentPanelTab = 'reports' | 'history' | 'favorites' | 'controls' | 'pin';

export const ParentPanelPage: React.FC = () => {
  const { user } = useAuth();
  const { refreshSettings, lockParentMode } = useParent();
  const [activeTab, setActiveTab] = useState<ParentPanelTab>('reports');
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);

  // Reports state
  const [selectedPeriod, setSelectedPeriod] = useState<ReportTimePeriod>('weekly');
  const [reportData, setReportData] = useState<UsageReportData | null>(null);
  const [isLoadingReport, setIsLoadingReport] = useState<boolean>(false);

  // Favorites & History hooks
  const { favorites, isLoading: isLoadingFavorites, refetch: refetchFavorites } = useFavorites();
  const { history, isLoading: isLoadingHistory, refetch: refetchHistory } = useWatchHistory();

  const favoriteVideos = favorites
    .map((f) => f.video)
    .filter((v): v is Video => Boolean(v && !v.is_deleted));

  const historyVideos = history
    .map((h) => h.video)
    .filter((v): v is Video => Boolean(v && !v.is_deleted));

  // PIN Form State
  const [currentPin, setCurrentPin] = useState<string>('');
  const [newPin, setNewPin] = useState<string>('');
  const [hasExistingPin, setHasExistingPin] = useState<boolean>(true);
  const [pinMessage, setPinMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [isUpdatingPin, setIsUpdatingPin] = useState<boolean>(false);

  // Parental Control Settings State
  const [dailyTimeLimitMinutes, setDailyTimeLimitMinutes] = useState<number | null>(null);
  const [allowedCategories, setAllowedCategories] = useState<string[]>([]);
  const [bedtimeStart, setBedtimeStart] = useState<string>('');
  const [bedtimeEnd, setBedtimeEnd] = useState<string>('');
  const [settingsMessage, setSettingsMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [isSavingSettings, setIsSavingSettings] = useState<boolean>(false);
  const [isLoadingSettings, setIsLoadingSettings] = useState<boolean>(false);

  // Load report data for current user
  useEffect(() => {
    if (!user?.id) return;

    let isMounted = true;
    setIsLoadingReport(true);

    parentService
      .getUsageReport(user.id, selectedPeriod)
      .then((data) => {
        if (isMounted) {
          setReportData(data);
        }
      })
      .catch(() => {
        if (isMounted) {
          setReportData(null);
        }
      })
      .finally(() => {
        if (isMounted) {
          setIsLoadingReport(false);
        }
      });

    return () => {
      isMounted = false;
    };
  }, [user?.id, selectedPeriod]);

  // Load parent settings on mount
  useEffect(() => {
    if (!user?.id) return;
    let isMounted = true;
    setIsLoadingSettings(true);

    parentService.getSettings(user.id).then((settings) => {
      if (isMounted && settings) {
        setHasExistingPin(settings.has_pin !== false);
        setDailyTimeLimitMinutes(settings.daily_time_limit_minutes ?? null);
        setAllowedCategories(settings.allowed_categories || []);
        setBedtimeStart(settings.bedtime_start || '');
        setBedtimeEnd(settings.bedtime_end || '');
        setIsLoadingSettings(false);
      }
    });

    return () => {
      isMounted = false;
    };
  }, [user?.id]);

  const periods: { id: ReportTimePeriod; label: string }[] = [
    { id: 'daily', label: 'Günlük' },
    { id: 'weekly', label: 'Haftalık' },
    { id: 'monthly', label: 'Aylık' },
    { id: '3months', label: '3 Aylık' },
    { id: '6months', label: '6 Aylık' },
    { id: '9months', label: '9 Aylık' },
    { id: '12months', label: '12 Aylık' },
  ];

  const handleUpdatePin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user?.id) return;
    if (newPin.length < 4) {
      setPinMessage({ type: 'error', text: 'Yeni PIN 4 haneli olmalıdır.' });
      return;
    }

    if (hasExistingPin && currentPin.length < 4) {
      setPinMessage({ type: 'error', text: 'Lütfen mevcut 4 haneli PIN kodunuzu girin.' });
      return;
    }

    setIsUpdatingPin(true);
    setPinMessage(null);

    const res = await parentService.updatePin(user.id, newPin, hasExistingPin ? currentPin : undefined);
    setIsUpdatingPin(false);

    if (res.success) {
      setPinMessage({ type: 'success', text: 'Ebeveyn PIN kodu başarıyla güncellendi!' });
      setNewPin('');
      setCurrentPin('');
      setHasExistingPin(true);
      await refreshSettings();
    } else {
      setPinMessage({ type: 'error', text: res.error || 'PIN güncellenemedi.' });
    }
  };

  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user?.id) return;

    setIsSavingSettings(true);
    setSettingsMessage(null);

    const res = await parentService.updateSettings(user.id, {
      daily_time_limit_minutes: dailyTimeLimitMinutes,
      allowed_categories: allowedCategories.length > 0 ? allowedCategories : null,
      bedtime_start: bedtimeStart ? bedtimeStart : null,
      bedtime_end: bedtimeEnd ? bedtimeEnd : null,
    });
    setIsSavingSettings(false);

    if (res.success) {
      setSettingsMessage({ type: 'success', text: 'Ebeveyn kontrol ayarları başarıyla kaydedildi!' });
      await refreshSettings();
    } else {
      setSettingsMessage({ type: 'error', text: res.error || 'Ayarlar kaydedilemedi.' });
    }
  };

  const toggleCategory = (categoryId: string) => {
    setAllowedCategories((prev) =>
      prev.includes(categoryId) ? prev.filter((id) => id !== categoryId) : [...prev, categoryId]
    );
  };

  const tabs: { id: ParentPanelTab; label: string; icon: React.FC<{ className?: string }> }[] = [
    { id: 'reports', label: 'Kullanım Raporları', icon: BarChart3 },
    { id: 'history', label: 'İzleme Geçmişi', icon: History },
    { id: 'favorites', label: 'Favoriler', icon: Heart },
    { id: 'controls', label: 'Kısıtlamalar ve Süre', icon: Sliders },
    { id: 'pin', label: 'PIN Yönetimi', icon: Key },
  ];

  return (
    <MainLayout>
      <div className="space-y-8">
        {/* Header */}
        <div className="bg-white p-8 rounded-3xl border border-purple-100 shadow-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-2xl bg-purple-100 text-purple-600 flex items-center justify-center shadow-inner">
              <Shield className="w-8 h-8" />
            </div>
            <div>
              <h1 className="text-2xl font-black text-slate-800">Ebeveyn Yönetim Paneli</h1>
              <p className="text-xs text-slate-500 font-medium">
                İzleme geçmişini, favorileri, kullanım raporlarını ve güvenlik kısıtlamalarını yönetin.
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div className="px-4 py-2 bg-purple-50 rounded-2xl border border-purple-200 text-purple-800 text-xs font-bold flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4 text-purple-600" />
              Ebeveyn Doğrulaması Aktif
            </div>
            <button
              onClick={() => lockParentMode()}
              className="p-2 bg-slate-100 hover:bg-rose-50 hover:text-rose-600 text-slate-600 rounded-2xl border border-slate-200 transition-all text-xs font-bold flex items-center gap-1.5"
              title="Ebeveyn Panelini Kilitle"
            >
              <Lock className="w-4 h-4" />
              <span className="hidden sm:inline">Kilitle</span>
            </button>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none border-b border-slate-200">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-5 py-3 rounded-2xl text-xs font-bold shrink-0 transition-all flex items-center gap-2 mb-2 ${
                  isActive
                    ? 'bg-purple-600 text-white shadow-md'
                    : 'bg-white text-slate-600 border border-slate-200 hover:bg-purple-50 hover:text-purple-700'
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>

        {/* TAB 1: USAGE REPORTS */}
        {activeTab === 'reports' && (
          <div className="bg-white p-6 rounded-3xl border border-amber-100 shadow-sm space-y-6">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
                <BarChart3 className="w-5 h-5 text-purple-600" />
                Kullanım Raporları
              </h2>
            </div>

            {/* Time Period Selector */}
            <div className="flex items-center gap-2 overflow-x-auto pb-2 scrollbar-none">
              {periods.map((p) => (
                <button
                  key={p.id}
                  onClick={() => setSelectedPeriod(p.id)}
                  className={`px-4 py-2 rounded-xl text-xs font-bold shrink-0 transition-all ${
                    selectedPeriod === p.id
                      ? 'bg-purple-600 text-white shadow-md'
                      : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>

            {/* Metric Summary Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-2">
              <div className="p-4 rounded-2xl bg-amber-50/50 border border-amber-100">
                <span className="text-xs font-semibold text-amber-800 block">Toplam İzleme Süresi</span>
                <span className="text-2xl font-black text-slate-800 mt-1 block">
                  {isLoadingReport ? '...' : formatDurationHuman(reportData?.totalWatchTimeSeconds || 0)}
                </span>
              </div>
              <div className="p-4 rounded-2xl bg-blue-50/50 border border-blue-100">
                <span className="text-xs font-semibold text-blue-800 block">İzlenen Video Sayısı</span>
                <span className="text-2xl font-black text-slate-800 mt-1 block">
                  {isLoadingReport ? '...' : `${reportData?.watchedVideosCount || 0} adet`}
                </span>
              </div>
              <div className="p-4 rounded-2xl bg-emerald-50/50 border border-emerald-100">
                <span className="text-xs font-semibold text-emerald-800 block">Tamamlanan İçerikler</span>
                <span className="text-2xl font-black text-slate-800 mt-1 block">
                  {isLoadingReport ? '...' : `${reportData?.completedVideosCount || 0} adet`}
                </span>
              </div>
            </div>

            {/* Category Stats Breakdown */}
            {reportData && reportData.categoryStats.length > 0 && (
              <div className="pt-4 border-t border-slate-100 space-y-3">
                <h3 className="text-xs font-bold text-slate-700 uppercase tracking-wider">Kategori Dağılımı</h3>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {reportData.categoryStats.map((cat) => (
                    <div key={cat.categoryId} className="p-3 bg-slate-50 rounded-xl flex items-center justify-between text-xs">
                      <span className="font-semibold text-slate-700">{cat.categoryName || cat.categoryTitle}</span>
                      <span className="font-bold text-purple-700">
                        {formatDurationHuman(cat.watchTimeSeconds)} {cat.videoCount !== undefined ? `(${cat.videoCount} video)` : ''}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Top Watched Videos */}
            {reportData && reportData.topWatchedVideos.length > 0 && (
              <div className="pt-4 border-t border-slate-100 space-y-3">
                <h3 className="text-xs font-bold text-slate-700 uppercase tracking-wider">En Çok İzlenen Videolar</h3>
                <div className="space-y-2">
                  {reportData.topWatchedVideos.map((item) => (
                    <div key={item.videoId} className="p-3 bg-slate-50 rounded-xl flex items-center justify-between text-xs">
                      <div className="flex items-center gap-2 truncate pr-2">
                        <Film className="w-4 h-4 text-purple-600 shrink-0" />
                        <span className="font-semibold text-slate-800 truncate">{item.title}</span>
                      </div>
                      <span className="font-bold text-slate-600 shrink-0">
                        {formatDurationHuman(item.totalSeconds)}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* TAB 2: WATCH HISTORY */}
        {activeTab === 'history' && (
          <div className="bg-white p-6 rounded-3xl border border-blue-100 shadow-sm space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-2xl bg-blue-100 text-blue-600 flex items-center justify-center">
                  <History className="w-5 h-5" />
                </div>
                <div>
                  <h2 className="text-lg font-bold text-slate-800">İzleme Geçmişi</h2>
                  <p className="text-xs text-slate-500 font-medium">Daha önce izlenen tüm içerikler ve kalınan yerler.</p>
                </div>
              </div>
            </div>

            <VideoGrid
              videos={historyVideos}
              onPlay={(v) => setActiveVideo(v)}
              onRefresh={refetchHistory}
              isLoading={isLoadingHistory}
            />
          </div>
        )}

        {/* TAB 3: FAVORITES */}
        {activeTab === 'favorites' && (
          <div className="bg-white p-6 rounded-3xl border border-rose-100 shadow-sm space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-2xl bg-rose-100 text-rose-600 flex items-center justify-center">
                  <Heart className="w-5 h-5 fill-current" />
                </div>
                <div>
                  <h2 className="text-lg font-bold text-slate-800">Favori İçerikler</h2>
                  <p className="text-xs text-slate-500 font-medium">Beğenilen ve kaydedilen tüm videolar.</p>
                </div>
              </div>
            </div>

            <VideoGrid
              videos={favoriteVideos}
              onPlay={(v) => setActiveVideo(v)}
              onRefresh={refetchFavorites}
              isLoading={isLoadingFavorites}
            />
          </div>
        )}

        {/* TAB 4: PARENTAL CONTROLS & RESTRICTIONS */}
        {activeTab === 'controls' && (
          <div className="bg-white p-6 rounded-3xl border border-amber-100 shadow-sm space-y-6">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
                <Sliders className="w-5 h-5 text-purple-600" />
                Ebeveyn Koruması ve Kısıtlamalar
              </h2>
            </div>

            {settingsMessage && (
              <div
                className={`p-3 rounded-2xl text-xs font-semibold ${
                  settingsMessage.type === 'success'
                    ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                    : 'bg-rose-50 text-rose-800 border border-rose-200'
                }`}
              >
                {settingsMessage.text}
              </div>
            )}

            <form onSubmit={handleSaveSettings} className="space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Daily Time Limit */}
                <div className="p-5 rounded-2xl bg-slate-50 border border-slate-200 space-y-3">
                  <div className="flex items-center gap-2 text-slate-800 font-bold text-sm">
                    <Clock className="w-4 h-4 text-amber-600" />
                    Günlük İzleme Süresi Sınırı
                  </div>
                  <p className="text-xs text-slate-500">
                    Günde en fazla kaç dakika video izlenebileceğini belirleyin.
                  </p>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-2">
                    {[
                      { val: null, label: 'Limitsiz' },
                      { val: 30, label: '30 Dk' },
                      { val: 60, label: '1 Saat' },
                      { val: 120, label: '2 Saat' },
                    ].map((opt) => (
                      <button
                        key={String(opt.val)}
                        type="button"
                        onClick={() => setDailyTimeLimitMinutes(opt.val)}
                        className={`py-2 px-3 rounded-xl text-xs font-bold transition-all border ${
                          dailyTimeLimitMinutes === opt.val
                            ? 'bg-purple-600 text-white border-purple-600 shadow-sm'
                            : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        {opt.label}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Bedtime Restriction */}
                <div className="p-5 rounded-2xl bg-slate-50 border border-slate-200 space-y-3">
                  <div className="flex items-center gap-2 text-slate-800 font-bold text-sm">
                    <Moon className="w-4 h-4 text-indigo-600" />
                    Uyku Vakti Kısıtlaması
                  </div>
                  <p className="text-xs text-slate-500">
                    Bu saatler arasında çocuk ekranında uyku dinlenme modu gösterilir.
                  </p>
                  <div className="grid grid-cols-2 gap-3 pt-2">
                    <div>
                      <label className="block text-xs font-bold text-slate-600 mb-1">Başlangıç (Örn: 21:00)</label>
                      <input
                        type="time"
                        value={bedtimeStart}
                        onChange={(e) => setBedtimeStart(e.target.value)}
                        className="w-full py-2 px-3 rounded-xl bg-white border border-slate-200 text-xs font-bold text-slate-700 focus:outline-none focus:ring-2 focus:ring-purple-500"
                      />
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-slate-600 mb-1">Bitiş (Örn: 07:00)</label>
                      <input
                        type="time"
                        value={bedtimeEnd}
                        onChange={(e) => setBedtimeEnd(e.target.value)}
                        className="w-full py-2 px-3 rounded-xl bg-white border border-slate-200 text-xs font-bold text-slate-700 focus:outline-none focus:ring-2 focus:ring-purple-500"
                      />
                    </div>
                  </div>
                </div>
              </div>

              {/* Allowed Categories */}
              <div className="p-5 rounded-2xl bg-slate-50 border border-slate-200 space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <h3 className="text-sm font-bold text-slate-800">İzin Verilen Kategoriler</h3>
                    <p className="text-xs text-slate-500">
                      Seçim yapılmazsa tüm kategorilere izin verilir. Seçilenler dışındakiler gizlenir.
                    </p>
                  </div>
                  {allowedCategories.length > 0 && (
                    <button
                      type="button"
                      onClick={() => setAllowedCategories([])}
                      className="text-xs text-purple-600 font-bold hover:underline"
                    >
                      Tümüne İzin Ver
                    </button>
                  )}
                </div>

                <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2 pt-2">
                  {DEFAULT_CATEGORIES.map((cat) => {
                    const isChecked = allowedCategories.length === 0 || allowedCategories.includes(cat.id);
                    return (
                      <button
                        key={cat.id}
                        type="button"
                        onClick={() => toggleCategory(cat.id)}
                        className={`p-3 rounded-xl text-xs font-bold transition-all border flex items-center justify-between text-left ${
                          isChecked
                            ? 'bg-purple-50 text-purple-900 border-purple-200 shadow-xs'
                            : 'bg-white text-slate-400 border-slate-200 opacity-60'
                        }`}
                      >
                        <span className="truncate">{cat.title}</span>
                        {isChecked && <Check className="w-3.5 h-3.5 text-purple-600 shrink-0" />}
                      </button>
                    );
                  })}
                </div>
              </div>

              <button
                type="submit"
                disabled={isSavingSettings || isLoadingSettings}
                className="px-6 py-3 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white font-bold rounded-xl shadow-md transition-all text-xs flex items-center gap-2"
              >
                {isSavingSettings ? 'Kaydediliyor...' : 'Ayarları Kaydet ve Uygula'}
              </button>
            </form>
          </div>
        )}

        {/* TAB 5: PIN MANAGEMENT */}
        {activeTab === 'pin' && (
          <div className="bg-white p-6 rounded-3xl border border-amber-100 shadow-sm max-w-xl space-y-4">
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
              <Key className="w-5 h-5 text-amber-600" />
              Ebeveyn PIN Değiştirme
            </h2>

            {pinMessage && (
              <div
                className={`p-3 rounded-2xl text-xs font-semibold ${
                  pinMessage.type === 'success'
                    ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                    : 'bg-rose-50 text-rose-800 border border-rose-200'
                }`}
              >
                {pinMessage.text}
              </div>
            )}

            <form onSubmit={handleUpdatePin} className="space-y-4">
              {hasExistingPin && (
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">Mevcut 4 Haneli PIN</label>
                  <input
                    type="password"
                    maxLength={4}
                    value={currentPin}
                    onChange={(e) => setCurrentPin(e.target.value.replace(/\D/g, ''))}
                    placeholder="••••"
                    className="w-full text-center text-xl tracking-widest font-mono font-bold py-2.5 px-4 rounded-xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-purple-500"
                  />
                </div>
              )}

              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  {hasExistingPin ? 'Yeni 4 Haneli PIN' : '4 Haneli Ebeveyn PIN Belirleyin'}
                </label>
                <input
                  type="password"
                  maxLength={4}
                  value={newPin}
                  onChange={(e) => setNewPin(e.target.value.replace(/\D/g, ''))}
                  placeholder="••••"
                  className="w-full text-center text-xl tracking-widest font-mono font-bold py-2.5 px-4 rounded-xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-purple-500"
                />
              </div>

              <button
                type="submit"
                disabled={isUpdatingPin || newPin.length < 4 || (hasExistingPin && currentPin.length < 4)}
                className="w-full py-3 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white font-bold rounded-xl shadow-md transition-all text-xs"
              >
                {isUpdatingPin ? 'Güncelleniyor...' : hasExistingPin ? 'PIN\'i Güncelle' : 'PIN Oluştur'}
              </button>
            </form>
          </div>
        )}
      </div>

      {/* Video Player Modal */}
      <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />
    </MainLayout>
  );
};
