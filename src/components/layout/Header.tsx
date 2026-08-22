import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../../hooks/useAuth';
import { useParent } from '../../hooks/useParent';
import { ROUTES } from '../../constants/routes.constants';
import { APP_CONFIG } from '../../constants/app.constants';
import { Shield, LogOut, User, Sparkles, Home, LogIn, Heart, History } from 'lucide-react';

export const Header: React.FC = () => {
  const { user, profile, role, signOut } = useAuth();
  const { isParentUnlocked, lockParentMode } = useParent();
  const location = useLocation();
  const isActive = (path: string) => location.pathname === path;

  const navClass = (path: string) => `px-3.5 py-2.5 rounded-xl font-bold text-sm transition-all flex items-center gap-2 ${
    isActive(path) ? 'bg-slate-900 text-white shadow-sm' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
  }`;

  return (
    <header className="sticky top-0 z-40 border-b border-slate-200 bg-white/95 backdrop-blur-md shadow-sm">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between min-h-18 py-3 gap-3">
          <Link to={ROUTES.HOME} className="flex items-center gap-3 group min-w-0">
            <div className="w-11 h-11 rounded-2xl bg-slate-900 flex items-center justify-center text-white shadow-sm group-hover:bg-blue-700 transition-colors shrink-0">
              <Sparkles className="w-6 h-6" />
            </div>
            <div className="min-w-0">
              <span className="text-base sm:text-lg font-black tracking-tight text-slate-900 block truncate">{APP_CONFIG.NAME}</span>
              <span className="text-[10px] sm:text-xs font-bold text-blue-700 tracking-wide uppercase">Güvenli Çocuk Medya</span>
            </div>
          </Link>

          <nav className="hidden md:flex items-center gap-1.5" aria-label="Ana navigasyon">
            <Link to={ROUTES.HOME} className={navClass(ROUTES.HOME)}><Home className="w-4 h-4" /> Ana Sayfa</Link>
            {user && <>
              <Link to={ROUTES.FAVORITES} className={navClass(ROUTES.FAVORITES)}><Heart className="w-4 h-4" /> Favoriler</Link>
              <Link to={ROUTES.HISTORY} className={navClass(ROUTES.HISTORY)}><History className="w-4 h-4" /> Geçmiş</Link>
            </>}
            {(role === 'parent' || role === 'admin') && (
              <Link to={ROUTES.PARENT_PANEL} className={`px-4 py-2.5 rounded-xl font-bold text-sm transition-all flex items-center gap-2 border ${
                isActive(ROUTES.PARENT_PANEL) ? 'bg-blue-700 text-white border-blue-700 shadow-sm' : isParentUnlocked ? 'bg-emerald-50 text-emerald-800 border-emerald-200' : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'
              }`}>
                <Shield className={`w-4 h-4 ${isParentUnlocked ? 'text-emerald-600' : isActive(ROUTES.PARENT_PANEL) ? 'text-white' : 'text-blue-700'}`} />
                Ebeveyn Paneli
                {isParentUnlocked && <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" title="Kilit Açık" />}
              </Link>
            )}
          </nav>

          <div className="flex items-center gap-2 shrink-0">
            {user ? (
              <div className="flex items-center gap-2">
                <div className="flex items-center gap-2 bg-slate-50 px-2.5 py-1.5 rounded-xl border border-slate-200">
                  <div className="w-8 h-8 rounded-full bg-slate-900 flex items-center justify-center text-white font-black text-sm">
                    {profile?.first_name ? profile.first_name[0].toUpperCase() : <User className="w-4 h-4" />}
                  </div>
                  <div className="text-left hidden sm:block">
                    <span className="text-xs font-bold text-slate-900 block leading-tight">{profile?.first_name ? profile.first_name : 'Kullanıcı'}</span>
                    <span className="text-[10px] font-bold text-blue-700 uppercase tracking-wider block leading-tight">
                      {role === 'publisher' ? 'Yayıncı' : role === 'admin' ? 'Yönetici' : role === 'parent' ? 'Ebeveyn' : role === 'child' ? 'Çocuk' : 'Kullanıcı'}
                    </span>
                  </div>
                </div>
                {isParentUnlocked && <button onClick={lockParentMode} className="p-2 rounded-xl text-slate-500 hover:bg-emerald-50 hover:text-emerald-700 transition-colors" title="Ebeveyn Modunu Kilitle"><Shield className="w-5 h-5 text-emerald-600" /></button>}
                <button onClick={() => signOut()} className="p-2 rounded-xl text-slate-500 hover:bg-slate-100 hover:text-slate-900 transition-colors" title="Çıkış Yap"><LogOut className="w-5 h-5" /></button>
              </div>
            ) : <Link to={ROUTES.LOGIN} className="px-4 sm:px-5 py-2.5 rounded-xl bg-blue-700 hover:bg-blue-800 text-white font-bold text-sm shadow-sm transition-all flex items-center gap-2"><LogIn className="w-4 h-4" /> Giriş Yap</Link>}
          </div>
        </div>

        <nav className="md:hidden -mx-4 px-4 pb-3 flex items-center gap-2 overflow-x-auto" aria-label="Mobil navigasyon">
          <Link to={ROUTES.HOME} className={navClass(ROUTES.HOME)}><Home className="w-4 h-4" /> Ana Sayfa</Link>
          {user && <>
            <Link to={ROUTES.FAVORITES} className={navClass(ROUTES.FAVORITES)}><Heart className="w-4 h-4" /> Favoriler</Link>
            <Link to={ROUTES.HISTORY} className={navClass(ROUTES.HISTORY)}><History className="w-4 h-4" /> Geçmiş</Link>
          </>}
          {(role === 'parent' || role === 'admin') && <Link to={ROUTES.PARENT_PANEL} className={navClass(ROUTES.PARENT_PANEL)}><Shield className="w-4 h-4" /> Ebeveyn</Link>}
        </nav>
      </div>
    </header>
  );
};
