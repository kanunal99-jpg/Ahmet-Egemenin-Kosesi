import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../../hooks/useAuth';
import { useParent } from '../../hooks/useParent';
import { ROUTES } from '../../constants/routes.constants';
import { APP_CONFIG } from '../../constants/app.constants';
import { Heart, History, Shield, LogOut, User, Sparkles, Home, LogIn } from 'lucide-react';

export const Header: React.FC = () => {
  const { user, profile, role, signOut } = useAuth();
  const { isParentUnlocked, lockParentMode } = useParent();
  const location = useLocation();

  const isActive = (path: string) => location.pathname === path;

  return (
    <header className="sticky top-0 z-40 bg-white/95 backdrop-blur-md border-b border-amber-100 shadow-xs">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-20">
          {/* Logo */}
          <Link to={ROUTES.HOME} className="flex items-center gap-3 group">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-amber-400 via-orange-400 to-amber-500 flex items-center justify-center text-white shadow-md group-hover:scale-105 transition-transform">
              <Sparkles className="w-7 h-7 fill-white/20" />
            </div>
            <div>
              <span className="text-xl font-black tracking-tight text-slate-800 block">
                {APP_CONFIG.NAME}
              </span>
              <span className="text-xs font-semibold text-amber-600 tracking-wide uppercase">
                Güvenli Çocuk Medya
              </span>
            </div>
          </Link>

          {/* Navigation Links */}
          <nav className="hidden md:flex items-center gap-2">
            <Link
              to={ROUTES.HOME}
              className={`px-4 py-2.5 rounded-2xl font-bold text-sm transition-all flex items-center gap-2 ${
                isActive(ROUTES.HOME)
                  ? 'bg-amber-100 text-amber-900 shadow-xs'
                  : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
              }`}
            >
              <Home className="w-4 h-4" />
              Ana Sayfa
            </Link>

            {user && (
              <>
                <Link
                  to={ROUTES.FAVORITES}
                  className={`px-4 py-2.5 rounded-2xl font-bold text-sm transition-all flex items-center gap-2 ${
                    isActive(ROUTES.FAVORITES)
                      ? 'bg-rose-100 text-rose-900 shadow-xs'
                      : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
                  }`}
                >
                  <Heart className="w-4 h-4 text-rose-500" />
                  Favorilerim
                </Link>

                <Link
                  to={ROUTES.HISTORY}
                  className={`px-4 py-2.5 rounded-2xl font-bold text-sm transition-all flex items-center gap-2 ${
                    isActive(ROUTES.HISTORY)
                      ? 'bg-blue-100 text-blue-900 shadow-xs'
                      : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
                  }`}
                >
                  <History className="w-4 h-4 text-blue-500" />
                  İzleme Geçmişi
                </Link>
              </>
            )}

            {(role === 'parent' || role === 'admin') && (
              <Link
                to={ROUTES.PARENT_PANEL}
                className={`px-4 py-2.5 rounded-2xl font-bold text-sm transition-all flex items-center gap-2 border ${
                  isActive(ROUTES.PARENT_PANEL)
                    ? 'bg-purple-100 text-purple-900 border-purple-200 shadow-xs'
                    : isParentUnlocked
                    ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
                    : 'bg-slate-50 text-slate-700 border-slate-200 hover:bg-slate-100'
                }`}
              >
                <Shield className={`w-4 h-4 ${isParentUnlocked ? 'text-emerald-600' : 'text-purple-600'}`} />
                Ebeveyn Paneli
                {isParentUnlocked && (
                  <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" title="Kilit Açık" />
                )}
              </Link>
            )}
          </nav>

          {/* User Profile / Auth Action */}
          <div className="flex items-center gap-3">
            {user ? (
              <div className="flex items-center gap-3">
                <div className="flex items-center gap-2.5 bg-amber-50 px-3.5 py-1.5 rounded-full border border-amber-200">
                  <div className="w-8 h-8 rounded-full bg-amber-400 flex items-center justify-center text-amber-950 font-black text-sm shadow-xs">
                    {profile?.first_name ? profile.first_name[0].toUpperCase() : <User className="w-4 h-4" />}
                  </div>
                  <div className="text-left hidden sm:block">
                    <span className="text-xs font-bold text-slate-800 block leading-tight">
                      {profile?.first_name ? `${profile.first_name}` : 'Kullanıcı'}
                    </span>
                    <span className="text-[10px] font-semibold text-amber-700 uppercase tracking-wider block leading-tight">
                      {role === 'publisher'
                        ? 'Yayıncı'
                        : role === 'admin'
                        ? 'Yönetici'
                        : role === 'parent'
                        ? 'Ebeveyn'
                        : role === 'child'
                        ? 'Çocuk'
                        : 'Kullanıcı'}
                    </span>
                  </div>
                </div>

                {isParentUnlocked && (
                  <button
                    onClick={lockParentMode}
                    className="p-2 rounded-xl text-slate-500 hover:bg-amber-100 hover:text-amber-900 transition-colors"
                    title="Ebeveyn Modunu Kilitle"
                  >
                    <Shield className="w-5 h-5 text-emerald-600" />
                  </button>
                )}

                <button
                  onClick={() => signOut()}
                  className="p-2 rounded-xl text-slate-500 hover:bg-rose-50 hover:text-rose-600 transition-colors"
                  title="Çıkış Yap"
                >
                  <LogOut className="w-5 h-5" />
                </button>
              </div>
            ) : (
              <Link
                to={ROUTES.LOGIN}
                className="px-5 py-2.5 rounded-2xl bg-amber-500 hover:bg-amber-600 text-white font-bold text-sm shadow-md transition-all flex items-center gap-2"
              >
                <LogIn className="w-4 h-4" />
                Giriş Yap
              </Link>
            )}
          </div>
        </div>
      </div>
    </header>
  );
};
