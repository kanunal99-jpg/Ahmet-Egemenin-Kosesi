import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { AuthProvider } from './contexts/AuthContext';
import { ParentProvider } from './contexts/ParentContext';
import { ROUTES } from './constants/routes.constants';

import { HomePage } from './pages/HomePage';
import { FavoritesPage } from './pages/FavoritesPage';
import { WatchHistoryPage } from './pages/WatchHistoryPage';
import { ParentPanelPage } from './pages/ParentPanelPage';
import { LoginPage } from './pages/LoginPage';
import { RegisterPage } from './pages/RegisterPage';
import { NotFoundPage } from './pages/NotFoundPage';

import { ProtectedRoute } from './guards/ProtectedRoute';
import { ParentRoute } from './guards/ParentRoute';

export default function App() {
  return (
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      <AuthProvider>
        <ParentProvider>
          <Routes>
            <Route path={ROUTES.HOME} element={<HomePage />} />
            <Route path={ROUTES.CATEGORY} element={<HomePage />} />
            <Route
              path={ROUTES.FAVORITES}
              element={
                <ProtectedRoute>
                  <FavoritesPage />
                </ProtectedRoute>
              }
            />
            <Route
              path={ROUTES.HISTORY}
              element={
                <ProtectedRoute>
                  <WatchHistoryPage />
                </ProtectedRoute>
              }
            />
            <Route
              path={ROUTES.PARENT_PANEL}
              element={
                <ParentRoute>
                  <ParentPanelPage />
                </ParentRoute>
              }
            />
            <Route path={ROUTES.LOGIN} element={<LoginPage />} />
            <Route path={ROUTES.REGISTER} element={<RegisterPage />} />
            <Route path={ROUTES.NOT_FOUND} element={<NotFoundPage />} />
          </Routes>
        </ParentProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
