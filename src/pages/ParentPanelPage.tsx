import React, { useEffect, useState } from 'react';
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
import { ParentVideoManager } from '../components/parent/ParentVideoManager';

type ParentPanelTab = 'videos' | 'reports' | 'history' | 'favorites' | 'controls' | 'pin';

export const ParentPanelPage: React.FC = () => {
  const { user } = useAuth();
  const { refreshSettings, lockParentMode } = useParent();
  const [activeTab, setActiveTab] = useState<ParentPanelTab>('videos');
  const [activeVideo, setActiveVideo] = useState<Video | null>(null);
  const [selectedPeriod, setSelectedPeriod] = useState<ReportTimePeriod>('weekly');
  const [reportData, setReportData] = useState<UsageReportData | null>(null);
  const [isLoadingReport, setIsLoadingReport] = useState(false);
  const { favorites, isLoading: isLoadingFavorites, refetch: refetchFavorites } = useFavorites();
  const { history, isLoading: isLoadingHistory, refetch: refetchHistory } = useWatchHistory();
  const [currentPin, setCurrentPin] = useState('');
  const [newPin, setNewPin] = useState('');
  const [hasExistingPin, setHasExistingPin] = useState(true);
  const [pinMessage, setPinMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [isUpdatingPin, setIsUpdatingPin] = useState(false);
  const [dailyTimeLimitMinutes, setDailyTimeLimitMinutes] = useState<number | null>(null);
  const [allowedCategories, setAllowedCategories] = useState<string[]>([]);
  const [bedtimeStart, setBedtimeStart] = useState('');
  const [bedtimeEnd, setBedtimeEnd] = useState('');
  const [settingsMessage, setSettingsMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);
  const [isSavingSettings, setIsSavingSettings] = useState(false);
  const [isLoadingSettings, setIsLoadingSettings] = useState(false);

  const favoriteVideos = favorites
    .map((f) => f.video)
    .filter((v): v is Video => Boolean(v && !v.is_deleted));
  const historyVideos = history
    .map((h) => h.video)
    .filter((v): v is Video => Boolean(v && !v.is_deleted));

  useEffect(() => {
    if (!user?.id) return;
    let isMounted = true;
    setIsLoadingReport(true);

    parentService
      .getUsageReport(user.id, selectedPeriod)
      .then((data) => {
        if (isMounted) setReportData(data);
      })
      .catch(() => {
        if (isMounted) setReportData(null);
      })
      .finally(() => {
        if (isMounted) setIsLoadingReport(false);
      });

    return () => {
      isMounted = false;
    };
  }, [user?.id, selectedPeriod]);

  useEffect(() => {
    if (!user?.id) return;
    let isMounted = true;
    setIsLoadingSettings(true);

    parentService
      .getSettings(user.id)
      .then((settings) => {
        if (isMounted && settings) {
          setHasExistingPin(settings.has_pin !== false);
          setDailyTimeLimitMinutes(settings.daily_time_limit_minutes ?? null);
          setAllowedCategories(settings.allowed_categories || []);
          setBedtimeStart(settings.bedtime_start || '');
          setBedtimeEnd(settings.bedtime_end || '');
        }
        if (isMounted) setIsLoadingSettings(false);
      })
      .catch(() => {
        if (isMounted) setIsLoadingSettings(false);
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

    try {
      const res = await parentService.updatePin(user.id, newPin, hasExistingPin ? currentPin : undefined);
      if (res.success) {
        setPinMessage({ type: 'success', text: 'Ebeveyn PIN kodu başarıyla güncellendi!' });
        setNewPin('');
        setCurrentPin('');
        setHasExistingPin(true);
        await refreshSettings();
      } else {
        setPinMessage({ type: 'error', text: res.error || 'PIN güncellenemedi.' });
      }
    } catch {
      setPinMessage({ type: 'error', text: 'PIN güncellenirken beklenmeyen bir hata oluştu.' });
    } finally {
      setIsUpdatingPin(false);
    }
  };

  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user?.id) return;

    setIsSavingSettings(true);
    setSettingsMessage(null);

    try {
      const res = await parentService.updateSettings(user.id, {
        daily_time_limit_minutes: dailyTimeLimitMinutes,
        allowed_categories: allowedCategories.length > 0 ? allowedCategories : null,
        bedtime_start: bedtimeStart || null,
        bedtime_end: bedtimeEnd || null,
      });

      if (res.success) {
        setSettingsMessage({ type: 'success', text: 'Ebeveyn kontrol ayarları başarıyla kaydedildi!' });
        await refreshSettings();
      } else {
        setSettingsMessage({ type: 'error', text: res.error || 'Ayarlar kaydedilemedi.' });
      }
    } catch {
      setSettingsMessage({ type: 'error', text: 'Ayarlar kaydedilirken beklenmeyen bir hata oluştu.' });
    } finally {
      setIsSavingSettings(false);
    }
  };

  const toggleCategory = (categoryId: string) => {
    setAllowedCategories((prev) =>
      prev.includes(categoryId)
        ? prev.filter((id) => id !== categoryId)
        : [...prev, categoryId],
    );
  };

  const tabs: { id: ParentPanelTab; label: string; icon: React.FC<{ className?: string }> }[] = [
    { id: 'videos', label: 'Video Yönetimi', icon: Film },
    { id: 'reports', label: 'Kullanım Raporları', icon: BarChart3 },
    { id: 'history', label: 'İzleme Geçmişi', icon: History },
    { id: 'favorites', label: 'Favoriler', icon: Heart },
    { id: 'controls', label: 'Kısıtlamalar ve Süre', icon: Sliders },
    { id: 'pin', label: 'PIN Yönetimi', icon: Key },
  ];

  return (
    <MainLayout>
      <div className="space-y-8">
        <div className="bg-white p-8 rounded-3xl border border-blue-100 shadow-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-2xl bg-blue-50 text-blue-600 flex items-center justify-center shadow-inner">
              <Shield className="w-8 h-8" />
            </div>
            <div>
              <h1 className="text-2xl font-black text-slate-800">Ebeveyn Yönetim Paneli</h1>
              <p className="text-xs text-slate-500 font-medium">
                Videolarınızı ekleyin, izleme geçmişini, favorileri, kullanım raporlarını ve güvenlik kısıtlamalarını yönetin.
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <div className="px-4 py-2 bg-blue-50 rounded-2xl border border-blue-200 text-blue-800 text-xs font-bold flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4 text-blue-600" />
              Ebeveyn Doğrulaması Aktif
            </div>
            <button
              onClick={lockParentMode}
              className="p-2 bg-slate-100 hover:bg-rose-50 hover:text-rose-600 text-slate-600 rounded-2xl border border-slate-200 transition-all text-xs font-bold flex items-center gap-1.5"
              title="Ebeveyn Panelini Kilitle"
            >
              <Lock className="w-4 h-4" />
              <span className="hidden sm:inline">Kilitle</span>
            </button>
          </div>
        </div>

        <div className="flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none border-b border-slate-200">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                aria-current={isActive ? 'page' : undefined}
                className={`px-5 py-3 rounded-2xl text-xs font-bold shrink-0 transition-all flex items-center gap-2 mb-2 ${
                  isActive
                    ? 'bg-blue-600 text-white shadow-md'
                    : 'bg-white text-slate-600 border border-slate-200 hover:bg-blue-50 hover:text-blue-700'
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>

        {activeTab === 'videos' && <ParentVideoManager />}

        {activeTab === 'reports' && (
          <div className="bg-white p-6 rounded-3xl border border-blue-100 shadow-sm space-y-6">
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
              <BarChart3 className="w-5 h-5 text-blue-600" />
              Kullanım Raporları
            </h2>

            <div className="flex items-center gap-2 overflow-x-auto pb-2 scrollbar-none">
              {periods.map((period) => (
                <button
                  key={period.id}
                  onClick={() => setSelectedPeriod(period.id)}
                  className={`px-4 py-2 rounded-xl text-xs font-bold shrink-0 transition-all ${
                    selectedPeriod === period.id
                      ? 'bg-blue-600 text-white shadow-md'
                      : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                  }`}
                >
                  {period.label}
                </button>
              ))}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-2">
              <div className="p-4 rounded-2xl bg-blue-50/50 border border-blue-100">
                <span className="text-xs font-semibold text-blue-800 block">Toplam İzleme Süresi</span>
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

            <div className="pt-4 border-t border-slate-100">
              <h3 className="text-sm font-bold text-slate-800 mb-3">Kategoriye Göre İzleme Dağılımı</h3>
              {isLoadingReport ? (
                <div className="text-center py-6 text-slate-400 text-xs">Yükleniyor...</div>
              ) : reportData?.categoryStats && reportData.categoryStats.length > 0 ? (
                <div className="space-y-3">
                  {reportData.categoryStats.map((category) => {
                    const percentage = category.percentage ?? 0;
                    return (
                      <div key={category.categoryId} className="space-y-1">
                        <div className="flex justify-between text-xs font-bold text-slate-700">
                          <span>{category.categoryName}</span>
                          <span>{formatDurationHuman(category.watchTimeSeconds)} ({percentage}%)</span>
                        </div>
                        <div className="w-full h-2 rounded-full bg-slate-100 overflow-hidden">
                          <div className="h-full bg-blue-500 rounded-full" style={{ width: `${percentage}%` }} />
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="text-center py-6 text-slate-400 text-xs bg-slate-50 rounded-2xl">
                  Bu dönem için izleme verisi bulunamadı.
                </div>
              )}
            </div>
          </div>
        )}

        {activeTab === 'history' && (
          <div className="space-y-4">
            <div className="bg-white p-6 rounded-3xl border border-slate-100 shadow-sm flex items-center justify-between">
              <div>
                <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
                  <History className="w-5 h-5 text-blue-600" />
                  İzleme Geçmişi
                </h2>
                <p className="text-xs text-slate-500 mt-0.5">Daha önce izlenen tüm videolar ve izleme ilerlemeleri.</p>
              </div>
              <button onClick={refetchHistory} className="px-3 py-1.5 text-xs font-bold bg-slate-50 hover:bg-slate-100 text-slate-600 rounded-xl border border-slate-200">
                Yenile
              </button>
            </div>
            {isLoadingHistory ? (
              <div className="text-center py-12 bg-white rounded-3xl border border-slate-100 text-slate-400 text-sm">Geçmiş yükleniyor...</div>
            ) : historyVideos.length === 0 ? (
              <div className="text-center py-12 bg-white rounded-3xl border border-slate-100 text-slate-400 text-sm">Henüz izlenmiş video geçmişi bulunmuyor.</div>
            ) : (
              <VideoGrid videos={historyVideos} onPlayVideo={setActiveVideo} />
            )}
          </div>
        )}

        {activeTab === 'favorites' && (
          <div className="space-y-4">
            <div className="bg-white p-6 rounded-3xl border border-slate-100 shadow-sm flex items-center justify-between">
              <div>
                <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
                  <Heart className="w-5 h-5 text-rose-500" />
                  Favori Videolar
                </h2>
                <p className="text-xs text-slate-500 mt-0.5">Favorilere eklenen tüm içerikler.</p>
              </div>
              <button onClick={refetchFavorites} className="px-3 py-1.5 text-xs font-bold bg-slate-50 hover:bg-slate-100 text-slate-600 rounded-xl border border-slate-200">
                Yenile
              </button>
            </div>
            {isLoadingFavorites ? (
              <div className="text-center py-12 bg-white rounded-3xl border border-slate-100 text-slate-400 text-sm">Favoriler yükleniyor...</div>
            ) : favoriteVideos.length === 0 ? (
              <div className="text-center py-12 bg-white rounded-3xl border border-slate-100 text-slate-400 text-sm">Henüz favorilere eklenmiş bir video yok.</div>
            ) : (
              <VideoGrid videos={favoriteVideos} onPlayVideo={setActiveVideo} />
            )}
          </div>
        )}

        {activeTab === 'controls' && (
          <div className="bg-white p-6 rounded-3xl border border-blue-100 shadow-sm space-y-6">
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
              <Sliders className="w-5 h-5 text-blue-600" />
              Kullanım Kısıtlamaları ve Süre Sınırı
            </h2>

            {settingsMessage && (
              <div className={`p-4 rounded-2xl text-xs font-bold flex items-center gap-2 ${
                settingsMessage.type === 'success'
                  ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                  : 'bg-rose-50 text-rose-800 border border-rose-200'
              }`}>
                {settingsMessage.type === 'success' ? <CheckCircle2 className="w-4 h-4 text-emerald-600" /> : <Key className="w-4 h-4 text-rose-600" />}
                {settingsMessage.text}
              </div>
            )}

            {isLoadingSettings ? (
              <div className="text-center py-6 text-slate-400 text-xs">Ayarlar yükleniyor...</div>
            ) : (
              <form onSubmit={handleSaveSettings} className="space-y-6">
                <div className="space-y-3">
                  <div className="flex items-center gap-2">
                    <Clock className="w-4 h-4 text-blue-600" />
                    <span className="text-sm font-bold text-slate-800">Günlük İzleme Süre Sınırı</span>
                  </div>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {[
                      { val: null, label: 'Sınırsız' },
                      { val: 30, label: '30 Dakika' },
                      { val: 60, label: '1 Saat' },
                      { val: 120, label: '2 Saat' },
                    ].map((option) => (
                      <button
                        type="button"
                        key={String(option.val)}
                        onClick={() => setDailyTimeLimitMinutes(option.val)}
                        className={`p-3 rounded-2xl border text-xs font-bold transition-all ${
                          dailyTimeLimitMinutes === option.val
                            ? 'bg-blue-600 text-white border-blue-600 shadow-sm'
                            : 'bg-slate-50 text-slate-700 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="space-y-3 pt-4 border-t border-slate-100">
                  <div className="flex items-center gap-2">
                    <Moon className="w-4 h-4 text-blue-600" />
                    <span className="text-sm font-bold text-slate-800">Uyku Saati Kısıtlaması</span>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <label className="block text-xs font-semibold text-slate-600">
                      Başlangıç Saati
                      <input type="time" value={bedtimeStart} onChange={(e) => setBedtimeStart(e.target.value)} className="mt-1 w-full px-4 py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-700 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500" />
                    </label>
                    <label className="block text-xs font-semibold text-slate-600">
                      Bitiş Saati
                      <input type="time" value={bedtimeEnd} onChange={(e) => setBedtimeEnd(e.target.value)} className="mt-1 w-full px-4 py-2.5 rounded-2xl border border-slate-200 text-xs font-bold text-slate-700 bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500" />
                    </label>
                  </div>
                </div>

                <div className="space-y-3 pt-4 border-t border-slate-100">
                  <span className="text-sm font-bold text-slate-800 block">İzin Verilen Kategoriler</span>
                  <p className="text-xs text-slate-500">Hiçbir kategori seçilmezse tüm kategoriler varsayılan olarak serbesttir.</p>
                  <div className="flex flex-wrap gap-2">
                    {DEFAULT_CATEGORIES.map((category) => {
                      const isAllowed = allowedCategories.includes(category.id);
                      return (
                        <button
                          type="button"
                          key={category.id}
                          onClick={() => toggleCategory(category.id)}
                          className={`px-4 py-2 rounded-2xl border text-xs font-bold transition-all flex items-center gap-1.5 ${
                            isAllowed
                              ? 'bg-blue-600 text-white border-blue-600 shadow-sm'
                              : 'bg-slate-50 text-slate-700 border-slate-200 hover:bg-slate-100'
                          }`}
                        >
                          {isAllowed && <Check className="w-3.5 h-3.5" />}
                          {category.title}
                        </button>
                      );
                    })}
                  </div>
                </div>

                <div className="pt-4 border-t border-slate-100 flex justify-end">
                  <button type="submit" disabled={isSavingSettings} className="px-6 py-3 bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white rounded-2xl text-xs font-black shadow-md transition-all disabled:opacity-50">
                    {isSavingSettings ? 'Kaydediliyor...' : 'Kısıtlamaları Kaydet'}
                  </button>
                </div>
              </form>
            )}
          </div>
        )}

        {activeTab === 'pin' && (
          <div className="bg-white p-6 rounded-3xl border border-blue-100 shadow-sm max-w-xl space-y-6">
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
              <Key className="w-5 h-5 text-blue-600" />
              Ebeveyn PIN Kodu Yönetimi
            </h2>
            <p className="text-xs text-slate-500 leading-relaxed">
              Ebeveyn panelini, kısıtlamaları ve video yönetimini korumak için 4 haneli PIN kodunuzu güncelleyin.
            </p>

            {pinMessage && (
              <div className={`p-4 rounded-2xl text-xs font-bold flex items-center gap-2 ${
                pinMessage.type === 'success'
                  ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
                  : 'bg-rose-50 text-rose-800 border border-rose-200'
              }`}>
                {pinMessage.type === 'success' ? <CheckCircle2 className="w-4 h-4 text-emerald-600" /> : <Key className="w-4 h-4 text-rose-600" />}
                {pinMessage.text}
              </div>
            )}

            <form onSubmit={handleUpdatePin} className="space-y-4">
              {hasExistingPin && (
                <label className="block text-xs font-bold text-slate-700">
                  Mevcut PIN Kodu (4 Hane)
                  <input type="password" inputMode="numeric" autoComplete="current-password" maxLength={4} value={currentPin} onChange={(e) => setCurrentPin(e.target.value.replace(/\D/g, ''))} placeholder="••••" className="mt-1 w-full px-4 py-3 rounded-2xl border border-slate-200 text-center tracking-widest text-lg font-black bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500" />
                </label>
              )}
              <label className="block text-xs font-bold text-slate-700">
                Yeni PIN Kodu (4 Hane)
                <input type="password" inputMode="numeric" autoComplete="new-password" maxLength={4} value={newPin} onChange={(e) => setNewPin(e.target.value.replace(/\D/g, ''))} placeholder="••••" className="mt-1 w-full px-4 py-3 rounded-2xl border border-slate-200 text-center tracking-widest text-lg font-black bg-slate-50 focus:bg-white focus:outline-none focus:ring-2 focus:ring-blue-500" />
              </label>
              <button type="submit" disabled={isUpdatingPin} className="w-full py-3.5 bg-blue-600 hover:bg-blue-700 active:bg-blue-800 text-white rounded-2xl text-xs font-black shadow-md transition-all disabled:opacity-50">
                {isUpdatingPin ? 'Güncelleniyor...' : hasExistingPin ? 'PIN Kodunu Güncelle' : 'PIN Kodu Oluştur'}
              </button>
            </form>
          </div>
        )}

        {activeVideo && <VideoPlayerModal video={activeVideo} onClose={() => setActiveVideo(null)} />}
      </div>
    </MainLayout>
  );
};