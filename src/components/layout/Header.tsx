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
        <div className="flex items-center justify-between min-h-32 py-3 gap-4">
          <div className="flex items-center min-w-0 shrink-0">
            <div className="flex items-center gap-4 group min-w-0">
              {user ? (
                <>
                  <button
                    type="button"
                    onClick={() => avatarInputRef.current?.click()}
                    disabled={avatarUploading}
                    className="relative w-32 h-32 rounded-3xl bg-slate-900 flex items-center justify-center text-white font-black text-2xl overflow-hidden ring-2 ring-slate-200 shadow-lg hover:ring-blue-400 transition-all disabled:cursor-wait shrink-0"
                    title="Profil fotoğrafını yükle veya değiştir"
                    aria-label="Profil fotoğrafını yükle veya değiştir"
                  >
                    {avatarUrl ? (
                      <img src={avatarUrl} alt="Profil fotoğrafı" className="w-full h-full object-cover" />
                    ) : profile?.first_name ? (
                      profile.first_name[0].toUpperCase()
                    ) : (
                      <User className="w-10 h-10" />
                    )}
                    <span className="absolute inset-x-0 bottom-0 h-8 bg-slate-950/75 flex items-center justify-center">
                      {avatarUploading ? <Loader2 className="w-6 h-6 animate-spin" /> : <Camera className="w-6 h-6" />}
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
                </>
              ) : (
                <div className="w-11 h-11 rounded-2xl bg-slate-900 flex items-center justify-center text-white shadow-sm shrink-0">
                  <Sparkles className="w-6 h-6" />
                </div>
              )}

              <Link to={ROUTES.HOME} className="min-w-0 group">
                <span className="text-base sm:text-lg font-black tracking-tight text-slate-900 block truncate">{APP_CONFIG.NAME}</span>
                <span className="text-[10px] sm:text-xs font-bold text-blue-700 tracking-wide uppercase block">Güvenli Çocuk Medya</span>
                {user && (
                  <span className="hidden sm:inline-flex mt-1 items-center gap-1 text-[10px] font-extrabold text-blue-700 group-hover:text-blue-800">
                    <Camera className="w-3 h-3" /> Fotoğrafı değiştir
                  </span>
                )}
              </Link>
            </div>
          </div>

          <nav className="hidden md:flex flex-1 justify-center items-center gap-1.5 min-w-0" aria-label="Ana navigasyon">
            <Link to={ROUTES.HOME} className={navClass(ROUTES.HOME)}><Home className="w-4 h-4" /> Ana Sayfa</Link>
            {user && <>
              <Link to={ROUTES.FAVORITES} className={navClass(ROUTES.FAVORITES)}><Heart className="w-4 h-4" /> Favoriler</Link>
              <Link to={ROUTES.HISTORY} className={navClass(ROUTES.HISTORY)}><History className="w-4 h-4" /> Geçmiş</Link>
            </>}
            {(role === 'parent' || role === 'admin') && (
              <Link to={ROUTES.PARENT_PANEL} className={`px-4 py-2.5 rounded-xl font-bold text-sm transition-all flex items-center gap-2 border ${
                isActive(ROUTES.PARENT_PANEL) ? 'bg-blue-700 text-white border-blue-700' : isParentUnlocked ? 'bg-emerald-50 text-emerald-800 border-emerald-200' : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'
              }`}>
                <Shield className="w-4 h-4" /> Ebeveyn Paneli
                {isParentUnlocked && <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" title="Kilit Açık" />}
              </Link>
            )}
          </nav>

          <div className="flex items-center gap-2 shrink-0">
            {user ? (
              <>
                {isParentUnlocked && <button onClick={lockParentMode} className="p-2 rounded-xl text-slate-500 hover:bg-emerald-50 hover:text-emerald-700 transition-colors" title="Ebeveyn Modunu Kilitle"><Shield className="w-5 h-5 text-emerald-600" /></button>}
                <button onClick={() => signOut()} className="p-2 rounded-xl text-slate-500 hover:bg-slate-100 hover:text-slate-900 transition-colors" title="Çıkış Yap"><LogOut className="w-5 h-5" /></button>
              </>
            ) : (
              <Link to={ROUTES.LOGIN} className="px-4 sm:px-5 py-2.5 rounded-xl bg-blue-700 hover:bg-blue-800 text-white font-bold text-sm shadow-sm transition-all flex items-center gap-2"><LogIn className="w-4 h-4" /> Giriş Yap</Link>
            )}
          </div>
        </div>

        {avatarError && user && (
          <div className="pb-2 text-left text-xs font-semibold text-red-700" role="status" aria-live="polite">
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