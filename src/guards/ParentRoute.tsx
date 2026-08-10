import React from 'react';
import { Navigate, useLocation, Link } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { useParent } from '../hooks/useParent';
import { ROUTES } from '../constants/routes.constants';
import { PinModal } from '../components/parent/PinModal';
import { MainLayout } from '../components/layout/MainLayout';
import { ShieldAlert } from 'lucide-react';

interface ParentRouteProps {
  children: React.ReactElement;
}

export const ParentRoute: React.FC<ParentRouteProps> = ({ children }) => {
  const { user, role, isLoading: isAuthLoading } = useAuth();
  const { isParentUnlocked } = useParent();
  const location = useLocation();
  const [showPinModal, setShowPinModal] = React.useState<boolean>(!isParentUnlocked);

  if (isAuthLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-amber-50">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-amber-500 border-t-transparent" />
      </div>
    );
  }

  // Guest users cannot access Parent Panel at all
  if (!user) {
    return <Navigate to={ROUTES.LOGIN} state={{ from: location }} replace />;
  }

  // Child accounts CANNOT access Parent Panel under any circumstances
  if (role === 'child') {
    return (
      <MainLayout>
        <div className="max-w-md mx-auto my-12 bg-white p-8 rounded-3xl border border-rose-100 text-center shadow-xl">
          <div className="w-14 h-14 rounded-2xl bg-rose-100 text-rose-600 flex items-center justify-center mx-auto mb-3">
            <ShieldAlert className="w-8 h-8" />
          </div>
          <h2 className="text-xl font-bold text-slate-800 mb-2">Erişim Engellendi</h2>
          <p className="text-sm text-slate-600 mb-6">
            Çocuk hesaplarının ebeveyn paneline erişim yetkisi yoktur.
          </p>
          <Link
            to={ROUTES.HOME}
            className="inline-block px-6 py-3 bg-amber-500 hover:bg-amber-600 text-white font-bold rounded-2xl shadow-md transition-colors text-sm"
          >
            Ana Sayfaya Dön
          </Link>
        </div>
      </MainLayout>
    );
  }

  if (!isParentUnlocked) {
    return (
      <div className="min-h-screen bg-amber-50/50 p-6 flex flex-col items-center justify-center">
        <div className="max-w-md w-full text-center bg-white p-8 rounded-3xl shadow-xl border border-amber-100">
          <h2 className="text-2xl font-bold text-slate-800 mb-2">Ebeveyn Paneli Kilitli</h2>
          <p className="text-slate-600 mb-6">
            Ebeveyn alanına erişmek için güvenlik PIN kodunuzu doğrulamanız gerekmektedir.
          </p>
          <button
            onClick={() => setShowPinModal(true)}
            className="w-full py-3 bg-amber-500 hover:bg-amber-600 text-white font-bold rounded-2xl shadow-md transition-colors"
          >
            PIN Gir
          </button>
        </div>

        <PinModal
          isOpen={showPinModal}
          onClose={() => setShowPinModal(false)}
          onSuccess={() => setShowPinModal(false)}
        />
      </div>
    );
  }

  return children;
};
