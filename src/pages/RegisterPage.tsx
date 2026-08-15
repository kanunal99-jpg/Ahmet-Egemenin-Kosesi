import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { MainLayout } from '../components/layout/MainLayout';
import { ROUTES } from '../constants/routes.constants';
import { supabase, isSupabaseConfigured } from '../services/supabase.client';
import { useAuth } from '../hooks/useAuth';
import { UserPlus, Sparkles, AlertCircle, CheckCircle2 } from 'lucide-react';

export const RegisterPage: React.FC = () => {
  const navigate = useNavigate();
  const { refreshSession } = useAuth();
  const [firstName, setFirstName] = useState('');
  const [lastName, setLastName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isSuccess, setIsSuccess] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password || !firstName) {
      setError('Lütfen zorunlu alanları doldurun.');
      return;
    }

    if (!isSupabaseConfigured) {
      setError('Supabase henüz yapılandırılmadı.');
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      // Single Account Architecture: All new registrations are created as 'parent'
      const { data, error: authError } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            first_name: firstName,
            last_name: lastName,
            role: 'parent',
          },
        },
      });

      if (authError) {
        setError(authError.message);
        setIsLoading(false);
      } else {
        if (data.session) {
          await refreshSession();
          setIsLoading(false);
          navigate(ROUTES.HOME, { replace: true });
        } else {
          setIsSuccess(true);
          setIsLoading(false);
        }
      }
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Kayıt gerçekleştirilemedi';
      setError(msg);
      setIsLoading(false);
    }
  };

  return (
    <MainLayout>
      <div className="max-w-md mx-auto my-12 bg-white p-8 rounded-3xl border border-amber-100 shadow-xl">
        <div className="text-center mb-6">
          <div className="w-14 h-14 rounded-2xl bg-amber-400 text-amber-950 flex items-center justify-center mx-auto mb-3 shadow-md">
            <Sparkles className="w-8 h-8" />
          </div>
          <h1 className="text-2xl font-black text-slate-800">Yeni Hesap Oluştur</h1>
          <p className="text-xs text-slate-500 mt-1">
            Ahmet Egemen&apos;in Köşesi platformuna katılarak içeriklerinizi yönetin.
          </p>
        </div>

        {error && (
          <div className="mb-4 p-3 rounded-2xl bg-rose-50 border border-rose-200 text-rose-700 text-xs font-semibold flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {isSuccess ? (
          <div className="text-center py-4 space-y-4">
            <div className="w-14 h-14 rounded-2xl bg-emerald-100 text-emerald-600 flex items-center justify-center mx-auto shadow-sm">
              <CheckCircle2 className="w-8 h-8" />
            </div>
            <h2 className="text-xl font-bold text-slate-800">E-Posta Doğrulaması Gerekli</h2>
            <p className="text-xs text-slate-600 leading-relaxed max-w-sm mx-auto">
              Kayıt işleminiz başarıyla tamamlandı. Lütfen <strong>{email}</strong> adresinize gönderilen doğrulama e-postasını kontrol edin ve hesabınızı aktifleştirin.
            </p>
            <div className="pt-2">
              <Link
                to={ROUTES.LOGIN}
                className="inline-flex items-center justify-center w-full py-3.5 bg-amber-500 hover:bg-amber-600 text-white font-bold rounded-2xl text-xs shadow-md transition-all"
              >
                Giriş Sayfasına Git
              </Link>
            </div>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">Adınız *</label>
                <input
                  type="text"
                  required
                  value={firstName}
                  onChange={(e) => setFirstName(e.target.value)}
                  placeholder="Ahmet"
                  className="w-full px-4 py-3 rounded-2xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-amber-500 text-sm font-medium"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">Soyadınız</label>
                <input
                  type="text"
                  value={lastName}
                  onChange={(e) => setLastName(e.target.value)}
                  placeholder="Yılmaz"
                  className="w-full px-4 py-3 rounded-2xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-amber-500 text-sm font-medium"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">E-Posta Adresi *</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="ornek@eposta.com"
                className="w-full px-4 py-3 rounded-2xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-amber-500 text-sm font-medium"
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">Şifre *</label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                className="w-full px-4 py-3 rounded-2xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-amber-500 text-sm font-medium"
              />
            </div>

            <button
              type="submit"
              disabled={isLoading}
              className="w-full py-3.5 bg-amber-500 hover:bg-amber-600 text-white font-bold rounded-2xl shadow-md transition-all flex items-center justify-center gap-2 text-sm"
            >
              {isLoading ? (
                <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                <>
                  <UserPlus className="w-4 h-4" />
                  Hesap Oluştur
                </>
              )}
            </button>
          </form>
        )}

        <div className="mt-6 text-center text-xs text-slate-500">
          Zaten hesabınız var mı?{' '}
          <Link to={ROUTES.LOGIN} className="font-bold text-amber-600 hover:underline">
            Giriş Yapın
          </Link>
        </div>
      </div>
    </MainLayout>
  );
};
