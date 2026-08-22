import React, { useState } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { MainLayout } from '../components/layout/MainLayout';
import { ROUTES } from '../constants/routes.constants';
import { supabase, isSupabaseConfigured } from '../services/supabase.client';
import { useAuth } from '../hooks/useAuth';
import { LogIn, Sparkles, AlertCircle } from 'lucide-react';

export const LoginPage: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { refreshSession } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const from = (location.state as { from?: { pathname?: string } })?.from?.pathname || ROUTES.HOME;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) return setError('Lütfen e-posta ve şifrenizi girin.');
    if (!isSupabaseConfigured) return setError('Supabase henüz yapılandırılmadı.');
    setIsLoading(true); setError(null);
    try {
      const { error: authError } = await supabase.auth.signInWithPassword({ email, password });
      if (authError) { setError(authError.message); setIsLoading(false); }
      else { await refreshSession(); navigate(from, { replace: true }); }
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Giriş yapılamadı');
      setIsLoading(false);
    }
  };

  return (
    <MainLayout>
      <div className="max-w-md mx-auto my-8 sm:my-12 bg-white p-6 sm:p-8 rounded-[2rem] border border-slate-200 shadow-xl">
        <div className="text-center mb-7">
          <div className="w-14 h-14 rounded-2xl bg-slate-900 text-white flex items-center justify-center mx-auto mb-4 shadow-sm">
            <Sparkles className="w-7 h-7" />
          </div>
          <h1 className="text-2xl font-black text-slate-900">Hoş Geldiniz</h1>
          <p className="text-sm text-slate-500 mt-2 leading-relaxed">Favorilerinize ve izleme geçmişinize erişmek için hesabınıza giriş yapın.</p>
        </div>
        {error && <div className="mb-5 p-3.5 rounded-xl bg-red-50 border border-red-200 text-red-700 text-xs font-semibold flex items-center gap-2"><AlertCircle className="w-4 h-4 shrink-0" /><span>{error}</span></div>}
        <form onSubmit={handleSubmit} className="space-y-4">
          <div><label className="block text-xs font-bold text-slate-700 mb-1.5">E-Posta Adresi</label><input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="ornek@eposta.com" className="w-full px-4 py-3.5 rounded-xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-600/25 focus:border-blue-600 text-sm font-medium transition-all" /></div>
          <div><label className="block text-xs font-bold text-slate-700 mb-1.5">Şifre</label><input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" className="w-full px-4 py-3.5 rounded-xl bg-slate-50 border border-slate-200 focus:outline-none focus:ring-2 focus:ring-blue-600/25 focus:border-blue-600 text-sm font-medium transition-all" /></div>
          <button type="submit" disabled={isLoading} className="w-full py-3.5 bg-blue-700 hover:bg-blue-800 disabled:opacity-60 text-white font-bold rounded-xl shadow-sm transition-all flex items-center justify-center gap-2 text-sm">{isLoading ? <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" /> : <><LogIn className="w-4 h-4" />Giriş Yap</>}</button>
        </form>
        <div className="mt-6 text-center text-sm text-slate-500">Hesabınız yok mu? <Link to={ROUTES.REGISTER} className="font-bold text-blue-700 hover:text-blue-800 hover:underline">Kayıt Olun</Link></div>
      </div>
    </MainLayout>
  );
};
