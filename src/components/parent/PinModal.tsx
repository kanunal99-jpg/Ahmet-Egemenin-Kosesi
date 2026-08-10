import React, { useState } from 'react';
import { useParent } from '../../hooks/useParent';
import { Shield, Lock, AlertCircle, X } from 'lucide-react';

interface PinModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export const PinModal: React.FC<PinModalProps> = ({ isOpen, onClose, onSuccess }) => {
  const { unlockParentMode, isLockedOut, lockoutRemainingSeconds } = useParent();
  const [pin, setPin] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);

  if (!isOpen) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pin || pin.length < 4) {
      setError('Lütfen 4 haneli PIN kodunuzu eksiksiz girin.');
      return;
    }

    setIsSubmitting(true);
    setError(null);

    const result = await unlockParentMode(pin);
    setIsSubmitting(false);

    if (result.success) {
      setPin('');
      setError(null);
      if (onSuccess) onSuccess();
      onClose();
    } else {
      setError(result.error || 'PIN doğrulanamadı.');
      setPin('');
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fade-in">
      <div className="bg-white rounded-3xl max-w-sm w-full p-6 shadow-2xl border border-amber-100 relative">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-slate-400 hover:text-slate-600 p-1.5 rounded-full hover:bg-slate-100 transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        <div className="text-center mb-6">
          <div className="w-16 h-16 rounded-2xl bg-purple-100 text-purple-600 flex items-center justify-center mx-auto mb-3 shadow-inner">
            <Shield className="w-8 h-8" />
          </div>
          <h3 className="text-xl font-black text-slate-800">Ebeveyn Doğrulaması</h3>
          <p className="text-xs text-slate-500 mt-1">
            Devam etmek için 4 haneli Ebeveyn PIN kodunuzu girin.
          </p>
        </div>

        {error && (
          <div className="mb-4 p-3 rounded-2xl bg-rose-50 border border-rose-200 flex items-start gap-2 text-rose-700 text-xs font-semibold">
            <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
            <span>{error}</span>
          </div>
        )}

        {isLockedOut ? (
          <div className="text-center py-4 bg-amber-50 rounded-2xl border border-amber-200 mb-4">
            <Lock className="w-8 h-8 text-amber-600 mx-auto mb-1 animate-bounce" />
            <p className="text-xs font-bold text-amber-900">Güvenlik Kilidi Aktif</p>
            <p className="text-xs text-amber-700 mt-1">
              Kalan Süre: <span className="font-mono font-black text-sm">{lockoutRemainingSeconds}s</span>
            </p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <input
                type="password"
                maxLength={4}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
                placeholder="••••"
                className="w-full text-center text-3xl tracking-widest font-mono font-bold py-3 px-4 rounded-2xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:bg-white transition-all"
                autoFocus
              />
            </div>

            <button
              type="submit"
              disabled={isSubmitting || pin.length < 4}
              className="w-full py-3.5 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white font-bold rounded-2xl shadow-lg transition-all flex items-center justify-center gap-2"
            >
              {isSubmitting ? (
                <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                <>
                  <Lock className="w-4 h-4" />
                  Kilit Aç
                </>
              )}
            </button>
          </form>
        )}
      </div>
    </div>
  );
};
