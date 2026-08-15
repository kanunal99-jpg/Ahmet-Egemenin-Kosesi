import React, { useState } from 'react';
import { ParentChild } from '../../types';
import { Users, UserPlus, UserCheck } from 'lucide-react';

interface ChildSelectorProps {
  childrenList: ParentChild[];
  selectedChildId: string | null;
  onSelectChild: (childId: string) => void;
  onLinkChild: (inviteCode: string) => Promise<{ success: boolean; error?: string }>;
  isLoading?: boolean;
}

export const ChildSelector: React.FC<ChildSelectorProps> = ({ childrenList, selectedChildId, onSelectChild, onLinkChild, isLoading = false }) => {
  const [showAddForm, setShowAddForm] = useState(false);
  const [inviteCodeInput, setInviteCodeInput] = useState('');
  const [isLinking, setIsLinking] = useState(false);
  const [linkError, setLinkError] = useState<string | null>(null);

  const handleAddChild = async (e: React.FormEvent) => {
    e.preventDefault();
    const code = inviteCodeInput.trim();
    if (!code) return;
    setIsLinking(true);
    setLinkError(null);
    const res = await onLinkChild(code);
    setIsLinking(false);
    if (res.success) {
      setInviteCodeInput('');
      setShowAddForm(false);
    } else {
      setLinkError(res.error || 'Çocuk hesabı bağlanamadı. Davet kodunu kontrol edin.');
    }
  };

  return (
    <div className="bg-white p-6 rounded-3xl border border-purple-100 shadow-sm space-y-4">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <div className="w-10 h-10 rounded-2xl bg-purple-100 text-purple-600 flex items-center justify-center">
            <Users className="w-5 h-5" />
          </div>
          <div>
            <h2 className="text-base font-bold text-slate-800">Bağlı Çocuk Hesapları</h2>
            <p className="text-xs text-slate-500 font-medium">Bağlı çocuğunuzu seçin veya çocuğun verdiği davet kodunu kullanın.</p>
          </div>
        </div>

        <button
          type="button"
          onClick={() => setShowAddForm(!showAddForm)}
          className="px-3.5 py-2 bg-purple-50 hover:bg-purple-100 text-purple-700 text-xs font-bold rounded-xl border border-purple-200 transition-all flex items-center gap-1.5"
        >
          <UserPlus className="w-4 h-4" />
          {showAddForm ? 'Vazgeç' : 'Çocuk Hesabı Bağla'}
        </button>
      </div>

      {showAddForm && (
        <form onSubmit={handleAddChild} className="p-4 bg-slate-50 rounded-2xl border border-slate-200 space-y-3">
          <label className="block text-xs font-bold text-slate-700">Çocuk Davet Kodu</label>
          <p className="text-[11px] text-slate-500">Çocuk hesabında oluşturulan tek kullanımlık kodu buraya girin. E-posta veya kullanıcı ID'si gerekmez.</p>
          <div className="flex flex-col sm:flex-row gap-2">
            <input
              type="text"
              required
              value={inviteCodeInput}
              onChange={(e) => setInviteCodeInput(e.target.value.toUpperCase())}
              placeholder="Örn: A1B2C3D4E5"
              inputMode="text"
              autoComplete="one-time-code"
              maxLength={16}
              className="flex-1 px-3.5 py-2 rounded-xl bg-white border border-slate-200 text-xs font-mono tracking-widest uppercase text-slate-800 focus:outline-none focus:ring-2 focus:ring-purple-500"
            />
            <button type="submit" disabled={isLinking || !inviteCodeInput.trim()} className="px-4 py-2 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white text-xs font-bold rounded-xl transition-all shadow-sm shrink-0">
              {isLinking ? 'Bağlanıyor...' : 'Bağla'}
            </button>
          </div>
          {linkError && <p className="text-xs font-semibold text-rose-600">{linkError}</p>}
        </form>
      )}

      {isLoading ? (
        <div className="py-4 text-center text-xs text-slate-400">Çocuk hesapları yükleniyor...</div>
      ) : childrenList.length === 0 ? (
        <div className="p-4 bg-amber-50 rounded-2xl border border-amber-200 text-amber-900 text-xs font-medium">
          Henüz bağlı bir çocuk hesabı bulunmuyor. Çocuk hesabında bir davet kodu oluşturup burada girerek hesabı bağlayabilirsiniz.
        </div>
      ) : (
        <div className="flex flex-wrap gap-2 pt-1">
          {childrenList.map((child) => {
            const isSelected = selectedChildId === child.childId;
            return (
              <button key={child.id} type="button" onClick={() => onSelectChild(child.childId)} className={`px-4 py-2.5 rounded-2xl text-xs font-bold border transition-all flex items-center gap-2 ${isSelected ? 'bg-purple-600 text-white border-purple-600 shadow-md scale-102' : 'bg-slate-50 hover:bg-slate-100 text-slate-700 border-slate-200'}`}>
                <UserCheck className={`w-4 h-4 ${isSelected ? 'text-white' : 'text-purple-600'}`} />
                <span>{child.childName || 'Çocuk Hesabı'}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
};
