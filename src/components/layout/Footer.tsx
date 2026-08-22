import React from 'react';
import { APP_CONFIG } from '../../constants/app.constants';
import { Heart, ShieldCheck, Sparkles } from 'lucide-react';

export const Footer: React.FC = () => {
  return (
    <footer className="bg-slate-950 text-slate-300 py-10 border-t border-slate-800 mt-10">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-700 flex items-center justify-center text-white shadow-sm">
              <Sparkles className="w-5 h-5" />
            </div>
            <div>
              <span className="text-lg font-black text-white block">{APP_CONFIG.NAME}</span>
              <span className="text-xs text-slate-400">Çocuk Dostu Medya ve İçerik Platformu</span>
            </div>
          </div>

          <div className="flex items-center gap-5 text-xs sm:text-sm font-semibold text-slate-400">
            <span className="flex items-center gap-1.5 text-cyan-300">
              <ShieldCheck className="w-4 h-4" /> Güvenli İçerik
            </span>
            <span className="flex items-center gap-1.5 text-blue-300">
              <Heart className="w-4 h-4 fill-blue-300" /> Aile Dostu
            </span>
          </div>
        </div>

        <div className="mt-8 pt-6 border-t border-slate-800 text-center text-xs text-slate-500">
          © {new Date().getFullYear()} {APP_CONFIG.NAME}. Tüm hakları saklıdır.
        </div>
      </div>
    </footer>
  );
};
