import React from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { UserRole } from '../types';
import { ROUTES } from '../constants/routes.constants';

interface RoleGuardProps {
  allowedRoles: UserRole[];
  children: React.ReactElement;
  fallbackRoute?: string;
}

export const RoleGuard: React.FC<RoleGuardProps> = ({
  allowedRoles,
  children,
  fallbackRoute = ROUTES.HOME,
}) => {
  const { role, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-amber-50">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-amber-500 border-t-transparent" />
      </div>
    );
  }

  if (!allowedRoles.includes(role)) {
    return <Navigate to={fallbackRoute} replace />;
  }

  return children;
};
