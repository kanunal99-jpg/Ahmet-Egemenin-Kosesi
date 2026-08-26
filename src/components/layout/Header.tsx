import React, { useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../../hooks/useAuth';
import { useParent } from '../../hooks/useParent';
import { ROUTES } from '../../constants/routes.constants';
import { APP_CONFIG } from '../../constants/app.constants';
import { profileService } from '../../services/profile.service';
import { supabase, isSupabaseConfigured } from '../../services/supabase.client';
import { Shield, LogOut, User, Sparkles, Home, LogIn, Heart, History, Camera, Loader2, X, Check, ZoomIn, ZoomOut } from 'lucide-react';

const AVATAR_MAX_BYTES = 2 * 1024 * 1024;
const AVATAR_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const AVATAR_SIZE = 250;

type CropState = {
  scale: number;
  x: number;
  y: number;
};

export const Header: React.FC = () => {
  const { user, profile, role, signOut } = useAuth();
  const { isParentUnlocked, lockParentMode } = useParent();
  const location = useLocation();
  const avatarInputRef = useRef<HTMLInputElement | null>(null);
  const avatarImageRef = useRef<HTMLImageElement | null>(null);
  const dragRef = useRef({ active: false, startX: 0, startY: 0, originX: 0, originY: 0 });
  const [avatarPath, setAvatarPath] = useState<string | null>(profile?.avatar_path ?? null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [cropFile, setCropFile] = useState<File | null>(null);
  const [cropPreviewUrl, setCropPreviewUrl] = useState<string | null>(null);
  const [cropState, setCropState] = useState<CropState>({ scale: 1, x: 0, y: 0 });
  const [baseScale, setBaseScale] = useState(1);
  const isActive = (path: string) => location.pathname === path;

  useEffect(() => {
    setAvatarPath(profile?.avatar_path ?? null);
  }, [profile?.avatar_path]);

  useEffect(() => () => {
    if (cropPreviewUrl) URL.revokeObjectURL(cropPreviewUrl);
  }, [cropPreviewUrl]);

  const navClass = (path: string) => `px-3.5 py-2.5 rounded-xl font-bold text-sm transition-all flex items-center gap-2 ${
    isActive(path) ? 'bg-slate-900 text-white shadow-sm' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900'
  }`;

  const avatarUrl = avatarPath
    ? supabase.storage.from('avatars').getPublicUrl(avatarPath).data.publicUrl
    : null;

  const openCropEditor = (file: File) => {
    if (!AVATAR_TYPES.has(file.type)) {
      setAvatarError('Profil fotoğrafı JPG, PNG veya WebP olmalıdır.');
      return;
    }
    if (file.size > AVATAR_MAX_BYTES) {
      setAvatarError('Profil fotoğrafı en fazla 2 MB olabilir.');
      return;
    }

    const nextUrl = URL.createObjectURL(file);
    setCropFile(file);
    setCropPreviewUrl(nextUrl);
    setCropState({ scale: 1, x: 0, y: 0 });
    setBaseScale(1);
    setAvatarError(null);
  };

  const closeCropEditor = () => {
    setCropFile(null);
    setCropPreviewUrl((current) => {
      if (current) URL.revokeObjectURL(current);
      return null;
    });
    setCropState({ scale: 1, x: 0, y: 0 });
    setBaseScale(1);
    if (avatarInputRef.current) avatarInputRef.current.value = '';
  };

  const clampCrop = (x: number, y: number, scale: number) => {
    const image = avatarImageRef.current;
    if (!image || !image.naturalWidth || !image.naturalHeight) return { x, y };

    const renderedWidth = image.naturalWidth * scale;
    const renderedHeight = image.naturalHeight * scale;
    const minX = Math.min(0, AVATAR_SIZE - renderedWidth);
    const minY = Math.min(0, AVATAR_SIZE - renderedHeight);
    return {
      x: Math.max(minX, Math.min(0, x)),
      y: Math.max(minY, Math.min(0, y)),
    };
  };

  const handleCropImageLoad = (event: React.SyntheticEvent<HTMLImageElement>) => {
    const image = event.currentTarget;
    avatarImageRef.current = image;
    const coverScale = Math.max(AVATAR_SIZE / image.naturalWidth, AVATAR_SIZE / image.naturalHeight);
    setBaseScale(coverScale);
    setCropState({ scale: coverScale, x: (AVATAR_SIZE - image.naturalWidth * coverScale) / 2, y: (AVATAR_SIZE - image.naturalHeight * coverScale) / 2 });
  };

  const handleCropZoom = (nextScale: number) => {
    const scale = Math.max(baseScale, Math.min(baseScale * 3, nextScale));
    const centerX = AVATAR_SIZE / 2;
    const centerY = AVATAR_SIZE / 2;
    setCropState((current) => {
      const relativeX = (current.x - centerX) * (scale / current.scale);
      const relativeY = (current.y - centerY) * (scale / current.scale);
      const next = clampCrop(centerX + relativeX, centerY + relativeY, scale);
      return { scale, ...next };
    });
  };

  const beginDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    dragRef.current = { active: true, startX: event.clientX, startY: event.clientY, originX: cropState.x, originY: cropState.y };
  };

  const moveDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!dragRef.current.active) return;
    const dx = event.clientX - dragRef.current.startX;
    const dy = event.clientY - dragRef.current.startY;
    const next = clampCrop(dragRef.current.originX + dx, dragRef.current.originY + dy, cropState.scale);
    setCropState((current) => ({ ...current, ...next }));
  };

  const endDrag = () => {
    dragRef.current.active = false;
  };

  const createCroppedAvatar = async (): Promise<File> => {
    const image = avatarImageRef.current;
    if (!image || !cropFile) throw new Error('Fotoğraf hazırlanamadı.');

    const canvas = document.createElement('canvas');
    canvas.width = AVATAR_SIZE;
    canvas.height = AVATAR_SIZE;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('Fotoğraf düzenleyicisi başlatılamadı.');

    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    context.drawImage(image, cropState.x, cropState.y, image.naturalWidth * cropState.scale, image.naturalHeight * cropState.scale);

    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/jpeg', 0.92));
    if (!blob) throw new Error('Fotoğraf işlenemedi.');
    return new File([blob], 'avatar.jpg', { type: 'image/jpeg' });
  };

  const handleAvatarChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;
    openCropEditor(file);
  };

  const saveCroppedAvatar = async () => {
    if (!user || !cropFile) return;
    if (!isSupabaseConfigured) {
      setAvatarError('Supabase henüz yapılandırılmadı.');
      return;
    }

    setAvatarUploading(true);
    setAvatarError(null);

    const previousPath = avatarPath;

    try {
      const croppedFile = await createCroppedAvatar();
      const token = typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      const newPath = `${user.id}/${token}.jpg`;

      const { error: uploadError } = await supabase.storage
        .from('avatars')
        .upload(newPath, croppedFile, {
          cacheControl: '3600',
          contentType: croppedFile.type,
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

      closeCropEditor();
    } catch (error: unknown) {
      setAvatarError(error instanceof Error ? error.message : 'Profil fotoğrafı yüklenemedi.');
    } finally {
      setAvatarUploading(false);
    }
  };

  return (
    <>
      <header className="sticky top-0 z-40 border-b border-slate-200 bg-white/95 backdrop-blur-md shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between min-h-[274px] py-3 gap-4">
            <div className="flex items-center min-w-0 shrink-0">
              <div className="flex items-center gap-4 group min-w-0">
                {user ? (
                  <>
                    <button
                      type="button"
                      onClick={() => avatarInputRef.current?.click()}
                      disabled={avatarUploading}
                      className="relative w-[250px] h-[250px] rounded-3xl bg-slate-900 flex items-center justify-center text-white font-black text-4xl overflow-hidden ring-2 ring-slate-200 shadow-xl hover:ring-blue-400 transition-all disabled:cursor-wait shrink-0"
                      title="Profil fotoğrafını yükle veya değiştir"
                      aria-label="Profil fotoğrafını yükle veya değiştir"
                    >
                      {avatarUrl ? (
                        <img src={avatarUrl} alt="Profil fotoğrafı" className="w-full h-full object-cover" />
                      ) : profile?.first_name ? (
                        profile.first_name[0].toUpperCase()
                      ) : (
                        <User className="w-16 h-16" />
                      )}
                      <span className="absolute inset-x-0 bottom-0 h-10 bg-slate-950/75 flex items-center justify-center">
                        {avatarUploading ? <Loader2 className="w-8 h-8 animate-spin" /> : <Camera className="w-8 h-8" />}
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
                    <span className="hidden sm:inline-flex mt-2 items-center gap-1 text-xs font-extrabold text-blue-700 group-hover:text-blue-800">
                      <Camera className="w-4 h-4" /> Fotoğrafı değiştir
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

      {cropFile && cropPreviewUrl && user && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-slate-950/80 p-4" role="dialog" aria-modal="true" aria-label="Profil fotoğrafını ayarla">
          <div className="w-full max-w-md rounded-3xl bg-white shadow-2xl overflow-hidden">
            <div className="flex items-center justify-between px-5 py-4 border-b border-slate-200">
              <div>
                <h2 className="font-black text-slate-900 text-lg">Profil Fotoğrafını Ayarla</h2>
                <p className="text-xs text-slate-500 mt-0.5">Fotoğrafı sürükle ve yakınlaştır.</p>
              </div>
              <button type="button" onClick={closeCropEditor} disabled={avatarUploading} className="p-2 rounded-xl hover:bg-slate-100 text-slate-500" aria-label="Kapat"><X className="w-5 h-5" /></button>
            </div>

            <div className="p-5 space-y-5">
              <div
                className="relative mx-auto w-[250px] h-[250px] overflow-hidden rounded-3xl bg-slate-900 ring-4 ring-slate-100 touch-none select-none cursor-grab active:cursor-grabbing"
                onPointerDown={beginDrag}
                onPointerMove={moveDrag}
                onPointerUp={endDrag}
                onPointerCancel={endDrag}
              >
                <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_center,transparent_0,transparent_48%,rgba(15,23,42,0.48)_49%,rgba(15,23,42,0.72)_100%)]" />
                <img
                  ref={avatarImageRef}
                  src={cropPreviewUrl}
                  alt="Profil fotoğrafı önizleme"
                  onLoad={handleCropImageLoad}
                  className="absolute max-w-none origin-top-left"
                  style={{
                    width: avatarImageRef.current?.naturalWidth || 'auto',
                    height: avatarImageRef.current?.naturalHeight || 'auto',
                    transform: `translate(${cropState.x}px, ${cropState.y}px) scale(${cropState.scale})`,
                  }}
                  draggable={false}
                />
                <div className="absolute inset-0 ring-2 ring-white/90 pointer-events-none rounded-3xl" />
              </div>

              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs font-bold text-slate-500">
                  <span className="flex items-center gap-1"><ZoomOut className="w-4 h-4" /> Uzaklaştır</span>
                  <span className="flex items-center gap-1">Yakınlaştır <ZoomIn className="w-4 h-4" /></span>
                </div>
                <input
                  type="range"
                  min={baseScale || 1}
                  max={(baseScale || 1) * 3}
                  step="0.01"
                  value={cropState.scale}
                  onChange={(event) => handleCropZoom(Number(event.target.value))}
                  className="w-full accent-blue-700"
                  aria-label="Fotoğraf yakınlaştırma"
                />
              </div>

              <div className="flex items-center justify-end gap-2">
                <button type="button" onClick={closeCropEditor} disabled={avatarUploading} className="px-4 py-2.5 rounded-xl font-bold text-slate-600 hover:bg-slate-100 disabled:opacity-50">İptal</button>
                <button type="button" onClick={saveCroppedAvatar} disabled={avatarUploading} className="px-5 py-2.5 rounded-xl bg-blue-700 hover:bg-blue-800 text-white font-bold flex items-center gap-2 disabled:opacity-60">
                  {avatarUploading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                  Kaydet
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
};