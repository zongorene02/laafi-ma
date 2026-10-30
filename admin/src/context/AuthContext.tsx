import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { fetchCurrentUser, login as loginRequest } from "../api/auth";
import { clearToken, getToken, setToken } from "../api/client";
import type { CurrentUser } from "../api/types";
import { canAccessConsole, consoleAccessDeniedMessage } from "../lib/roles";

interface AuthState {
  user: CurrentUser | null;
  isLoading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<CurrentUser | null>(null);
  // Chargement seulement si un jeton est déjà stocké (session précédente).
  const [isLoading, setIsLoading] = useState(() => getToken() !== null);

  useEffect(() => {
    if (!getToken()) return;
    let cancelled = false;
    fetchCurrentUser()
      .then((currentUser) => {
        if (cancelled) return;
        if (canAccessConsole(currentUser.role)) {
          setUser(currentUser);
        } else {
          clearToken();
          setUser(null);
        }
      })
      .catch(() => {
        // Jeton expiré/invalide : on nettoie plutôt que de rester dans un
        // état « connecté » qui ne fonctionne plus.
        if (cancelled) return;
        clearToken();
        setUser(null);
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const token = await loginRequest(email, password);
    setToken(token);
    let currentUser: CurrentUser;
    try {
      currentUser = await fetchCurrentUser();
    } catch (err) {
      clearToken();
      throw err;
    }
    if (!canAccessConsole(currentUser.role)) {
      clearToken();
      setUser(null);
      throw new Error(consoleAccessDeniedMessage(currentUser.role));
    }
    setUser(currentUser);
  }, []);

  const logout = useCallback(() => {
    clearToken();
    setUser(null);
  }, []);

  return <AuthContext.Provider value={{ user, isLoading, login, logout }}>{children}</AuthContext.Provider>;
}

// oxlint-disable-next-line react/only-export-components -- hook couplé au provider
export function useAuth(): AuthState {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth doit être utilisé à l'intérieur de <AuthProvider>");
  return context;
}
