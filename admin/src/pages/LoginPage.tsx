import { useState, type FormEvent } from "react";
import { Link, Navigate, useSearchParams } from "react-router-dom";
import { apiErrorMessage } from "../api/client";
import { Alert } from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { homePathFor } from "../lib/roles";
import { btnPrimary, inputClass, labelClass } from "../lib/styles";

export default function LoginPage() {
  const { user, isLoading, login } = useAuth();
  const [params] = useSearchParams();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (!isLoading && user) return <Navigate to={homePathFor(user.role)} replace />;

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await login(email.trim(), password);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-brand-50 px-4 py-8">
      <main className="w-full max-w-sm rounded-2xl bg-white p-6 shadow-sm sm:p-8">
        <h1 className="text-2xl font-bold text-gray-900">Laafi Ma</h1>
        <p className="mt-1 text-sm text-gray-600">
          Console de gestion — réservée aux validateurs (sages-femmes, médecins) et aux administrateurs.
        </p>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4" noValidate={false}>
          {params.get("expired") && !error && (
            <Alert kind="info">Votre session a expiré. Reconnectez-vous.</Alert>
          )}
          {error && <Alert>{error}</Alert>}
          <div>
            <label htmlFor="login-email" className={labelClass}>
              Adresse e-mail
            </label>
            <input
              id="login-email"
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className={inputClass}
            />
          </div>
          <div>
            <label htmlFor="login-password" className={labelClass}>
              Mot de passe
            </label>
            <input
              id="login-password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={inputClass}
            />
          </div>
          <button type="submit" disabled={submitting} className={`${btnPrimary} w-full py-2.5`}>
            {submitting ? "Connexion…" : "Se connecter"}
          </button>
        </form>
      </main>

      <p className="mt-6 text-center text-sm text-gray-700">
        <Link to="/public" className="font-semibold text-brand-700 hover:underline">
          Voir les statistiques publiques (sans compte)
        </Link>
      </p>
    </div>
  );
}
