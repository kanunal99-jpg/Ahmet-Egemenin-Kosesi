import React from 'react';
import { APP_CONFIG } from '../../constants/app.constants';
import { Heart, ShieldCheck, Sparkles } from 'lucide-react';

export const Footer: React.FC = () => {
  return (
    <footer className="bg-slate-900 text-slate-300 py-12 border-t border-slate-800">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-amber-500 flex items-center justify-center text-slate-950 font-bold shadow-xs">
              <Sparkles className="w-6 h-6 fill-slate-950/20" />
            </div>
            <div>
              <span className="text-lg font-black text-white block">{APP_CONFIG.NAME}</span>
              <span className="text-xs text-slate-400">Çocuk Dostu Medya ve İçerik Platformu</span>
            </div>
          </div>

          <div className="flex items-center gap-6 text-sm font-semibold text-slate-400">
            <span className="flex items-center gap-1.5 text-amber-400">
              <ShieldCheck className="w-4 h-4" /> Güvenli İçerik
            </span>
            <span className="flex items-center gap-1.5 text-rose-400">
              <Heart className="w-4 h-4 fill-rose-400" /> Aile Dostu
            </span>
          </div>
        </div>

        <div className="mt-8 pt-8 border-t border-slate-800 text-center text-xs text-slate-500">
          © {new Date().getFullYear()} {APP_CONFIG.NAME}. Tüm hakları saklıdır.
        </div>
      </div>
    </footer>
  );
};
