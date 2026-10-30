import { useCallback, useEffect, useState } from "react";
import { apiErrorMessage } from "../api/client";

interface Settled<T> {
  key: string;
  base: string;
  data: T | null;
  error: string | null;
}

/** Charge une ressource quand `key` change (ou sur `reload()`).
 *
 * `isLoading` est dérivé (aucun setState synchrone dans l'effet) ; en cas
 * d'erreur, les dernières données reçues restent affichées. `mutate` met à
 * jour localement la donnée après une action (création, suppression…). */
export function useAsync<T>(fetcher: () => Promise<T>, key: string) {
  const [version, setVersion] = useState(0);
  const fullKey = `${key}#${version}`;
  const [settled, setSettled] = useState<Settled<T> | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetcher().then(
      (data) => {
        if (!cancelled) setSettled({ key: fullKey, base: key, data, error: null });
      },
      (err: unknown) => {
        if (!cancelled) {
          setSettled((prev) => ({
            key: fullKey,
            base: key,
            // Même ressource rechargée : on garde l'affichage précédent.
            data: prev?.base === key ? prev.data : null,
            error: apiErrorMessage(err),
          }));
        }
      },
    );
    return () => {
      cancelled = true;
    };
    // `fetcher` est recréé à chaque rendu : `key` décrit à lui seul ses paramètres.
    // oxlint-disable-next-line react-hooks/exhaustive-deps
  }, [fullKey]);

  const reload = useCallback(() => setVersion((v) => v + 1), []);
  const mutate = useCallback((updater: (current: T | null) => T | null) => {
    setSettled((prev) => (prev ? { ...prev, data: updater(prev.data) } : prev));
  }, []);

  return {
    data: settled?.data ?? null,
    error: settled?.error ?? null,
    isLoading: settled?.key !== fullKey,
    reload,
    mutate,
  };
}
