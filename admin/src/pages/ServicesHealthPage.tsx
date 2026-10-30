import { useEffect } from "react";
import { fetchServicesHealth } from "../api/admin";
import type { ServicesHealth } from "../api/types";
import { Alert, PageHeader } from "../components/ui";
import { btnSecondary } from "../lib/styles";
import { useAsync } from "../lib/useAsync";

const KNOWN: { key: string; label: string; description: string }[] = [
  { key: "status", label: "API core-service", description: "Réponse globale du serveur" },
  { key: "database", label: "Base de données", description: "Connexion à la base" },
  { key: "translation_model_loaded", label: "Modèle de traduction", description: "Traduction fr ↔ mos / dyu" },
  { key: "speech_model_loaded", label: "Modèle vocal", description: "Reconnaissance et synthèse vocale" },
  { key: "fast_mode_available", label: "Mode rapide", description: "Traduction rapide pour les agents" },
];

type State = "up" | "down" | "unknown";

function stateOf(value: unknown): State {
  if (value === true || value === "ok") return "up";
  if (value === false || value === "error" || value === "down") return "down";
  if (value && typeof value === "object" && "status" in value) return stateOf((value as { status: unknown }).status);
  if (value && typeof value === "object" && "ok" in value) return stateOf((value as { ok: unknown }).ok);
  return "unknown";
}

function describe(value: unknown): string {
  if (value === null || value === undefined) return "—";
  if (typeof value === "boolean") return value ? "Disponible" : "Indisponible";
  if (typeof value === "string" || typeof value === "number") return String(value);
  return JSON.stringify(value);
}

function StateDot({ state }: { state: State }) {
  const color = state === "up" ? "bg-green-600" : state === "down" ? "bg-red-600" : "bg-gray-400";
  return <span aria-hidden="true" className={`h-2.5 w-2.5 shrink-0 rounded-full ${color}`} />;
}

export default function ServicesHealthPage() {
  const {
    data,
    error,
    reload: refresh,
  } = useAsync(async () => ({ health: await fetchServicesHealth(), checkedAt: new Date() }), "health");
  const health: ServicesHealth | null = data?.health ?? null;
  const lastChecked = data?.checkedAt ?? null;

  // Rafraîchi toutes les 30 s : une page d'état qui montre l'état d'il y a
  // vingt minutes peut afficher « tout va bien » alors qu'un service est tombé.
  useEffect(() => {
    const interval = setInterval(refresh, 30_000);
    return () => clearInterval(interval);
  }, [refresh]);

  const extraKeys = health ? Object.keys(health).filter((k) => !KNOWN.some((item) => item.key === k)) : [];

  return (
    <div className="space-y-6">
      <PageHeader
        title="État des services"
        description="Rafraîchi automatiquement toutes les 30 secondes."
        actions={
          <button type="button" onClick={refresh} className={btnSecondary}>
            Rafraîchir
          </button>
        }
      />

      {error && <Alert>{error}</Alert>}

      <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {[...KNOWN.map((k) => ({ ...k, value: health?.[k.key] })), ...extraKeys.map((key) => ({ key, label: key, description: "Vérification complémentaire", value: health?.[key] }))].map(
          (item) => {
            const state: State = health ? stateOf(item.value) : "unknown";
            return (
              <li key={item.key} className="rounded-2xl bg-white p-5 shadow-sm">
                <div className="flex items-center gap-2">
                  <StateDot state={state} />
                  <p className="font-semibold text-gray-900">{item.label}</p>
                </div>
                <p className="mt-1 text-sm text-gray-600">{item.description}</p>
                <p className="mt-3 text-sm font-medium break-words">
                  {!health ? (
                    <span className="text-gray-500">{error ? "Inconnu" : "Vérification…"}</span>
                  ) : state === "up" ? (
                    <span className="text-green-700">Disponible{typeof item.value === "string" && item.value !== "ok" ? ` (${item.value})` : ""}</span>
                  ) : state === "down" ? (
                    <span className="text-red-700">Indisponible</span>
                  ) : (
                    <span className="text-gray-700">{describe(item.value)}</span>
                  )}
                </p>
              </li>
            );
          },
        )}
      </ul>

      {lastChecked && (
        <p className="text-xs text-gray-500">Dernière vérification : {lastChecked.toLocaleTimeString("fr-FR")}</p>
      )}
    </div>
  );
}
