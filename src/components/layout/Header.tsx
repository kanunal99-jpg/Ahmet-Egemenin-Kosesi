import React, { useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../../hooks/useAuth';
import { useParent } from '../../hooks/useParent';
import { ROUTES } from '../../constants/routes.constants';
import { APP_CONFIG } from '../../constants/app.constants';
import { profileService } from '../../services/profile.service';
import { supabase, isSupabaseConfigured } from '../../services/supabase.client';
import { Shield, LogOut, User, Sparkles, Home, LogIn, Heart, History, Camera, Loader2 } from 'lucide-react';

const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
const AVATAR_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

export const Header: React.FC = () => {
  const { user, profile, role, signOut } = useAuth();
  const { isParentUnlocked, lockParentMode } = useParent();
  const location = useLocation();
  const avatarInputRef = useRef<HTMLInputElement | null>(null);
  const [avatarPath, setAvatarPath] = useState<string | null>(profile?.avatar_path ?? null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const isActive = (path: string) => location.pathname === path;

  useEffect(() => {
    setAvatarPath(profile?.avatar_path ?? null);
  }, [profile?.avatar_path]);

  const navClass = (path: string) => `px-3.5 py-2.5 rounded-xl font-bold text-sm transition-all flex items-center gap-2 ${
    isActive(path) ? 'bg-slate-900 text-white shadow-sm' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
  }`;

  const avatarUrl = avatarPath
    ? supabase.storage.from('avatars').getPublicUrl(avatarPath).data.publicUrl
    : null;

  const handleAvatarChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = '';

    if (!file || !user) return;
    if (!isSupabaseConfigured) {
      setAvatarError('Supabase henüz yapılandırılmadı.');
      return;
    }
    if (!AVATAR_TYPES.has(file.type)) {
      setAvatarError('Profil fotoğrafı JPG, PNG veya WebP olmalıdır.');
      return;
    }
    if (file.size > AVATAR_MAX_BYTES) {
      setAvatarError('Profil fotoğrafı en fazla 2 MB olabilir.');
      return;
    }

    setAvatarUploading(true);
    setAvatarError(null);

    const extension = file.type === 'image/jpeg' ? 'jpg' : file.type === 'image/png' ? 'png' : 'webp';
    const token = typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const newPath = `${user.id}/${token}.${extension}`;
    const previousPath = avatarPath;

    try {
      const { error: uploadError } = await supabase.storage
        .from('avatars')
        .upload(newPath, file, {
          cacheControl: '3600',
          contentType: file.type,
          upsert: false,
        });

      if (uploadError) throw uploadError;

      const updateResult = await profileService.updateAvatarPath(user.id, newPath);
      if (!updateResult.success) {
        await supabase.storage.from('avatars').remove([newPath]);
        throw new Error(updateResult.error || 'Profil fotoğrafı kaydedilemedi.');
      }

      setAvatarPath(newPath);

      if (previousPath && previousPath !== newPath) {
        const { error: cleanupError } = await supabase.storage.from('avatars').remove([previousPath]);
        if (cleanupError) {
          console.warn('[ProfileAvatar] Previous avatar cleanup failed:', cleanupError.message);
        }
      }
    } catch (error: unknown) {
      setAvatarError(error instanceof Error ? error.message : 'Profil fotoğrafı yüklenemedi.');
    } finally {
      setAvatarUploading(false);
    }
  };

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
                  <button
                    type="button"
                    onClick={() => avatarInputRef.current?.click()}
                    disabled={avatarUploading}
                    className="relative w-8 h-8 rounded-full bg-slate-900 flex items-center justify-center text-white font-black text-sm overflow-hidden ring-1 ring-slate-200 hover:ring-blue-400 transition-colors disabled:cursor-wait"
                    title="Profil fotoğrafını değiştir"
                    aria-label="Profil fotoğrafını değiştir"
                  >
                    {avatarUrl ? (
                      <img src={avatarUrl} alt="Profil fotoğrafı" className="w-full h-full object-cover" />
                    ) : profile?.first_name ? (
                      profile.first_name[0].toUpperCase()
                    ) : (
                      <User className="w-4 h-4" />
                    )}
                    <span className="absolute inset-0 bg-slate-900/45 opacity-0 hover:opacity-100 flex items-center justify-center transition-opacity">
                      {avatarUploading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Camera className="w-4 h-4" />}
                    </span>
                  </button>
                  <input
                    ref={avatarInputRef}
                    type="file"
                    accept="image/jpeg,image/png,image/webp"
                    className="hidden"
                    onChange={handleAvatarChange}
                    disabled={avatarUploading}
                  />
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

        {avatarError && user && (
          <div className="pb-2 text-right text-xs font-semibold text-red-700" role="status" aria-live="polite">
            {avatarError}
          </div>
        )}

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
