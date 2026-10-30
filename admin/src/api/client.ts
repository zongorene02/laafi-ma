import axios from "axios";
import { describeHttpError } from "../lib/errors.ts";

// Redéfinissable au build via une variable d'environnement Vite (voir
// .env.example) : l'URL de core-service change entre local et production.
export const API_BASE_URL: string = import.meta.env.VITE_API_BASE_URL ?? "http://127.0.0.1:8000";

const TOKEN_STORAGE_KEY = "laafi_ma_admin_token";

export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_STORAGE_KEY);
  } catch {
    return null;
  }
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_STORAGE_KEY, token);
}

export function clearToken(): void {
  try {
    localStorage.removeItem(TOKEN_STORAGE_KEY);
  } catch {
    // stockage indisponible (navigation privée stricte) : rien à effacer
  }
}

export const apiClient = axios.create({ baseURL: API_BASE_URL });

apiClient.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Session expirée (JWT de 60 min par défaut) : on efface le jeton et on
// renvoie vers la connexion. Exclus : `/auth/login` (401 = mauvais mot de
// passe, le message doit rester affiché) et la page publique, qui n'a pas
// besoin de compte.
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    const isLoginAttempt = String(error?.config?.url ?? "").includes("/auth/login");
    const path = window.location.pathname;
    if (error?.response?.status === 401 && !isLoginAttempt && !path.startsWith("/public")) {
      clearToken();
      if (path !== "/login") {
        window.location.assign("/login?expired=1");
      }
    }
    return Promise.reject(error);
  },
);

/** Message d'erreur lisible en français : `detail` du backend FastAPI quand il
 * existe, sinon un message selon le code HTTP. */
export function apiErrorMessage(error: unknown): string {
  if (axios.isAxiosError(error)) {
    if (!error.response) {
      return "Impossible de joindre le serveur Laafi Ma. Vérifiez votre connexion ou que core-service est démarré.";
    }
    const data = error.response.data as { detail?: unknown } | undefined;
    return describeHttpError(error.response.status, data?.detail);
  }
  if (error instanceof Error && error.message) return error.message;
  return "Une erreur inattendue s'est produite.";
}

/** Les fichiers audio sont servis en chemins relatifs (`/media/...`). */
export function mediaUrl(path: string | null | undefined): string | null {
  if (!path) return null;
  if (/^https?:\/\//.test(path)) return path;
  return `${API_BASE_URL.replace(/\/$/, "")}${path.startsWith("/") ? "" : "/"}${path}`;
}
