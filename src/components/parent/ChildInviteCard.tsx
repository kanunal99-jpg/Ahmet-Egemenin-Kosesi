import React, { useState } from 'react';
import { Copy, KeyRound, RefreshCw, CheckCircle2 } from 'lucide-react';
import { parentService } from '../../services/parent.service';

export const ChildInviteCard: React.FC = () => {
  const [code, setCode] = useState<string | null>(null);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);

  const generate = async () => {
    setLoading(true);
    setError(null);
    setCopied(false);
    const result = await parentService.generateChildLinkInvite();
    setLoading(false);
    if (!result.success || !result.code) {
      setError(result.error || 'Davet kodu oluşturulamadı.');
      return;
    }
    setCode(result.code);
    setExpiresAt(result.expiresAt || null);
  };

  const copy = async () => {
    if (!code) return;
    await navigator.clipboard.writeText(code);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1500);
  };

  return (
    <div className="mb-8 bg-white p-6 rounded-3xl border border-emerald-100 shadow-sm">
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-2xl bg-emerald-100 text-emerald-700 flex items-center justify-center shrink-0">
          <KeyRound className="w-5 h-5" />
        </div>
        <div className="flex-1">
          <h2 className="text-base font-bold text-slate-800">Ebeveyn Hesabına Bağlan</h2>
          <p className="text-xs text-slate-500 mt-1">Ebeveynine vermek için 30 dakika geçerli tek kullanımlık bir kod oluştur.</p>

          {error && <p className="mt-3 text-xs font-semibold text-rose-600">{error}</p>}

          {code && (
            <div className="mt-4 p-4 rounded-2xl bg-emerald-50 border border-emerald-200">
              <div className="text-[11px] font-bold text-emerald-800">Davet Kodu</div>
              <div className="mt-1 flex items-center gap-2">
                <code className="flex-1 text-xl sm:text-2xl font-black tracking-[0.25em] text-emerald-950 font-mono">{code}</code>
                <button type="button" onClick={copy} className="p-2 rounded-xl bg-white border border-emerald-200 text-emerald-700" title="Kodu kopyala">
                  {copied ? <CheckCircle2 className="w-5 h-5" /> : <Copy className="w-5 h-5" />}
                </button>
              </div>
              {expiresAt && <p className="mt-2 text-[11px] text-emerald-700">30 dakika içinde kullanılmalı.</p>}
            </div>
          )}

          <button type="button" onClick={generate} disabled={loading} className="mt-4 inline-flex items-center gap-2 px-4 py-2.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 disabled:opacity-50 text-white text-xs font-bold">
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            {code ? 'Yeni Kod Oluştur' : 'Bağlantı Kodu Oluştur'}
          </button>
        </div>
      </div>
    </div>
  );
};
