import type { ReactNode } from "react";
import { Navigate } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { can, homePathFor, type Permission } from "../lib/roles";
import Layout from "./Layout";

/** Enveloppe les routes de la console : redirige vers /login tant qu'aucun
 * compte validateur/admin n'est authentifié. */
export default function ProtectedRoute() {
  const { user, isLoading } = useAuth();

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center text-gray-500" role="status">
        Chargement…
      </div>
    );
  }
  if (!user) return <Navigate to="/login" replace />;

  return <Layout />;
}

/** Bloque une page selon le rôle (le backend répondrait 403 de toute façon). */
export function RequirePermission({ permission, children }: { permission: Permission; children: ReactNode }) {
  const { user } = useAuth();
  if (can(user?.role, permission)) return <>{children}</>;
  return (
    <div className="rounded-2xl bg-white p-8 shadow-sm">
      <h2 className="text-lg font-semibold text-gray-900">Accès réservé</h2>
      <p className="mt-2 text-sm text-gray-600">
        Cette page est réservée aux administrateurs. Votre rôle vous donne accès à la gestion et à la validation du
        contenu de santé.
      </p>
    </div>
  );
}

/** `/` : tableau de bord pour un admin, base de réponses pour un validateur. */
export function HomeRedirect({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  if (can(user?.role, "dashboard")) return <>{children}</>;
  return <Navigate to={homePathFor(user?.role)} replace />;
}
