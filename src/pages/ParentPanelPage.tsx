import React, { useState } from 'react';
import { MainLayout } from '../components/layout/MainLayout';
import { ReportTimePeriod } from '../types';
import { Shield, Clock, Key, BarChart3, CheckCircle2 } from 'lucide-react';
import { parentService } from '../services/parent.service';
import { useAuth } from '../hooks/useAuth';

export const ParentPanelPage: React.FC = () => {
  const { user } = useAuth();
  const [selectedPeriod, setSelectedPeriod] = useState<ReportTimePeriod>('weekly');
  const [newPin, setNewPin] = useState<string>('');
  const [pinMessage, setPinMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

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
      setPinMessage({ type: 'error', text: 'PIN 4 haneli olmalıdır.' });
      return;
    }

    const res = await parentService.updatePin(user.id, newPin);
    if (res.success) {
      setPinMessage({ type: 'success', text: 'Ebeveyn PIN kodu başarıyla güncellendi!' });
      setNewPin('');
    } else {
      setPinMessage({ type: 'error', text: res.error || 'PIN güncellenemedi.' });
    }
  };

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
                Çocuğunuzun platform üzerindeki izleme alışkanlıklarını ve raporlarını inceleyin.
              </p>
            </div>
          </div>
          <div className="px-4 py-2 bg-purple-50 rounded-2xl border border-purple-200 text-purple-800 text-xs font-bold flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-purple-600" />
            Ebeveyn Doğrulaması Aktif
          </div>
        </div>

        {/* Time Period Selector for Reports */}
        <div className="bg-white p-6 rounded-3xl border border-amber-100 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-bold text-slate-800 flex items-center gap-2">
              <BarChart3 className="w-5 h-5 text-purple-600" />
              Kullanım Raporları
            </h2>
          </div>

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
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-4">
            <div className="p-4 rounded-2xl bg-amber-50/50 border border-amber-100">
              <span className="text-xs font-semibold text-amber-800 block">Toplam İzleme Süresi</span>
              <span className="text-2xl font-black text-slate-800 mt-1 block">0 dk</span>
            </div>
            <div className="p-4 rounded-2xl bg-blue-50/50 border border-blue-100">
              <span className="text-xs font-semibold text-blue-800 block">İzlenen Video Sayısı</span>
              <span className="text-2xl font-black text-slate-800 mt-1 block">0 adet</span>
            </div>
            <div className="p-4 rounded-2xl bg-emerald-50/50 border border-emerald-100">
              <span className="text-xs font-semibold text-emerald-800 block">Tamamlanan İçerikler</span>
              <span className="text-2xl font-black text-slate-800 mt-1 block">0 adet</span>
            </div>
          </div>
        </div>

        {/* Parent PIN Settings Form */}
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
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">Yeni 4 Haneli PIN</label>
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
              disabled={newPin.length < 4}
              className="w-full py-3 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white font-bold rounded-xl shadow-md transition-all text-xs"
            >
              PIN&apos;i Güncelle
            </button>
          </form>
        </div>
      </div>
    </MainLayout>
  );
};
