import React from 'react';
import { Link } from 'react-router-dom';
import { MainLayout } from '../components/layout/MainLayout';
import { ROUTES } from '../constants/routes.constants';
import { Home, Compass } from 'lucide-react';

export const NotFoundPage: React.FC = () => {
  return (
    <MainLayout>
      <div className="text-center py-20 bg-white rounded-3xl border border-amber-100 p-8 max-w-lg mx-auto shadow-sm my-8">
        <div className="w-20 h-20 rounded-3xl bg-amber-100 text-amber-600 flex items-center justify-center mx-auto mb-4">
          <Compass className="w-10 h-10 animate-spin" />
        </div>
        <h1 className="text-4xl font-black text-slate-800">404</h1>
        <h2 className="text-lg font-bold text-slate-700 mt-2">Sayfa Bulunamadı</h2>
        <p className="text-xs text-slate-500 mt-2 leading-relaxed">
          Aradığınız sayfa mevcut değil veya taşınmış olabilir.
        </p>
        <Link
          to={ROUTES.HOME}
          className="inline-flex items-center gap-2 mt-6 px-6 py-3 rounded-2xl bg-amber-500 hover:bg-amber-600 text-white font-bold text-sm shadow-md transition-all"
        >
          <Home className="w-4 h-4" />
          Ana Sayfaya Dön
        </Link>
      </div>
    </MainLayout>
  );
};
