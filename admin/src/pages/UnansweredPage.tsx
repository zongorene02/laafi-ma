import { useState } from "react";
import { Link } from "react-router-dom";
import { apiErrorMessage } from "../api/client";
import { listUnanswered, resolveUnanswered } from "../api/kb";
import type { UnansweredQuestion } from "../api/types";
import { Alert, Badge, EmptyState, Loading, PageHeader } from "../components/ui";
import { formatDateTime, langLabel } from "../lib/labels";
import { useAsync } from "../lib/useAsync";
import { btnPrimary, btnSecondary, cardClass } from "../lib/styles";

export default function UnansweredPage() {
  const [resolved, setResolved] = useState(false);
  const { data, error: loadError, isLoading, mutate } = useAsync(() => listUnanswered(resolved), String(resolved));
  const questions: UnansweredQuestion[] = data ?? [];
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function handleResolve(question: UnansweredQuestion) {
    setBusyId(question.id);
    setError(null);
    try {
      await resolveUnanswered(question.id);
      mutate((prev) => (prev ?? []).filter((q) => q.id !== question.id));
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Questions sans réponse"
        description="Questions posées à l'assistant sans réponse suffisamment proche dans la base. Enregistrées anonymement (texte traduit en français, langue, date)."
      />

      <div role="radiogroup" aria-label="Afficher" className="inline-flex rounded-lg border border-gray-300 bg-white p-1">
        {[
          { value: false, label: "À traiter" },
          { value: true, label: "Résolues" },
        ].map((option) => (
          <button
            key={String(option.value)}
            type="button"
            role="radio"
            aria-checked={resolved === option.value}
            onClick={() => setResolved(option.value)}
            className={`rounded-md px-4 py-1.5 text-sm font-medium ${
              resolved === option.value ? "bg-brand-600 text-white" : "text-gray-700 hover:bg-gray-100"
            }`}
          >
            {option.label}
          </button>
        ))}
      </div>

      {loadError && <Alert>{loadError}</Alert>}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}

      {isLoading ? (
        <Loading />
      ) : questions.length === 0 && !loadError ? (
        <EmptyState title={resolved ? "Aucune question résolue." : "Aucune question en attente."}>
          {!resolved && "Les questions auxquelles l'assistant n'a pas su répondre apparaîtront ici."}
        </EmptyState>
      ) : (
        <ul className="space-y-3">
          {questions.map((q) => (
            <li key={q.id} className={`${cardClass} flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between`}>
              <div className="min-w-0">
                <p className="font-medium break-words text-gray-900">{q.text_fr}</p>
                <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-gray-600">
                  <Badge>Posée en {langLabel(q.lang)}</Badge>
                  <span>{formatDateTime(q.created_at)}</span>
                  {q.resolved && <Badge tone="green">Résolue</Badge>}
                </div>
              </div>
              {!q.resolved && (
                <div className="flex shrink-0 flex-wrap gap-2">
                  <Link
                    to={`/kb/new?${new URLSearchParams({ question: q.text_fr, unanswered: q.id }).toString()}`}
                    className={btnPrimary}
                  >
                    Créer une réponse
                  </Link>
                  <button type="button" onClick={() => handleResolve(q)} disabled={busyId === q.id} className={btnSecondary}>
                    {busyId === q.id ? "…" : "Marquer comme résolue"}
                  </button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
