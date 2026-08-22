import React from 'react';
import { Link } from 'react-router-dom';
import { MainLayout } from '../components/layout/MainLayout';
import { ROUTES } from '../constants/routes.constants';
import { Home, Compass } from 'lucide-react';

export const NotFoundPage: React.FC = () => (
  <MainLayout>
    <div className="text-center py-20 bg-white rounded-3xl border border-slate-200 p-8 max-w-lg mx-auto shadow-sm my-8">
      <div className="w-20 h-20 rounded-3xl bg-blue-50 text-blue-700 flex items-center justify-center mx-auto mb-4">
        <Compass className="w-10 h-10" />
      </div>
      <p className="text-xs font-black uppercase tracking-widest text-blue-700">Bir şeyler ters gitti</p>
      <h1 className="text-5xl font-black text-slate-900 mt-2">404</h1>
      <h2 className="text-lg font-bold text-slate-700 mt-2">Sayfa Bulunamadı</h2>
      <p className="text-sm text-slate-500 mt-2 leading-relaxed">Aradığınız sayfa mevcut değil veya taşınmış olabilir.</p>
      <Link to={ROUTES.HOME} className="inline-flex items-center gap-2 mt-6 px-6 py-3 rounded-xl bg-blue-700 hover:bg-blue-800 text-white font-bold text-sm shadow-sm transition-all"><Home className="w-4 h-4" /> Ana Sayfaya Dön</Link>
    </div>
  </MainLayout>
);
