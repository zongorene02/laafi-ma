// Sans dépendance (ni axios ni DOM) pour rester testable avec `node --test`.

const STATUS_MESSAGES: Record<number, string> = {
  400: "Requête invalide.",
  401: "Session expirée ou identifiants incorrects. Reconnectez-vous.",
  403: "Accès refusé : votre rôle ne permet pas cette action.",
  404: "Élément introuvable (il a peut-être été supprimé).",
  409: "Action impossible dans l'état actuel de l'élément.",
  413: "Fichier trop volumineux.",
  422: "Données invalides : vérifiez les champs du formulaire.",
  429: "Trop de tentatives. Patientez une minute puis réessayez.",
  503: "Service temporairement indisponible.",
};

/** Construit un message lisible à partir du code HTTP et du `detail` FastAPI
 * (chaîne, ou liste d'erreurs de validation Pydantic pour un 422). */
export function describeHttpError(status: number, detail: unknown): string {
  if (typeof detail === "string" && detail.trim()) return detail;
  if (Array.isArray(detail) && detail.length > 0) {
    const parts = detail
      .map((item) => {
        if (!item || typeof item !== "object") return null;
        const { msg, loc } = item as { msg?: unknown; loc?: unknown };
        if (typeof msg !== "string") return null;
        const field = Array.isArray(loc) ? loc.filter((p) => p !== "body").join(".") : "";
        return field ? `${field} : ${msg}` : msg;
      })
      .filter((p): p is string => Boolean(p));
    if (parts.length > 0) return `Données invalides — ${parts.join(" ; ")}`;
  }
  if (STATUS_MESSAGES[status]) return STATUS_MESSAGES[status];
  if (status >= 500) return `Erreur du serveur (${status}). Réessayez plus tard.`;
  return `Erreur inattendue (${status}).`;
}
