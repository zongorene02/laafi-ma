import { useState } from "react";
import { Link } from "react-router-dom";
import { listCapsules } from "../api/learn";
import { CAPSULE_TRACKS, type Capsule, type CapsuleTrack, type ContentStatus } from "../api/types";
import { Alert, Badge, EmptyState, Loading, PageHeader, StatusBadge } from "../components/ui";
import { CONTENT_STATUSES, LANGS, STATUS_LABELS, TRACK_LABELS } from "../lib/labels";
import { useAsync } from "../lib/useAsync";
import { btnPrimary, inputClass, labelClass } from "../lib/styles";

export default function CapsulesPage() {
  const [track, setTrack] = useState<CapsuleTrack | "">("");
  const { data, error, isLoading } = useAsync(() => listCapsules(track), track);
  const [status, setStatus] = useState<ContentStatus | "">("");
  const capsules: Capsule[] = (data ?? []).filter((c) => !status || c.status === status);

  // Groupées par parcours, triées par ordre d'affichage.
  const groups = CAPSULE_TRACKS.map((t) => ({
    track: t,
    items: capsules.filter((c) => c.track === t).sort((a, b) => a.order - b.order),
  })).filter((g) => g.items.length > 0);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Capsules « Apprendre »"
        description="Courtes leçons audio par parcours, avec quiz. Publiées sous licence CC-BY-4.0 une fois validées."
        actions={
          <Link to={`/capsules/new${track ? `?track=${track}` : ""}`} className={btnPrimary}>
            Nouvelle capsule
          </Link>
        }
      />

      <div className="flex max-w-xl flex-wrap gap-4">
        <div className="min-w-48 flex-1">
        <label htmlFor="cap-track" className={labelClass}>Parcours</label>
        <select id="cap-track" value={track} onChange={(e) => setTrack(e.target.value as CapsuleTrack | "")} className={inputClass}>
          <option value="">Tous les parcours</option>
          {CAPSULE_TRACKS.map((t) => (
            <option key={t} value={t}>{TRACK_LABELS[t]}</option>
          ))}
        </select>
        </div>
        <div className="min-w-48 flex-1">
          <label htmlFor="cap-status" className={labelClass}>Statut</label>
          <select id="cap-status" value={status} onChange={(e) => setStatus(e.target.value as ContentStatus | "")} className={inputClass}>
            <option value="">Tous les statuts</option>
            {CONTENT_STATUSES.map((s) => (
              <option key={s} value={s}>{STATUS_LABELS[s]}</option>
            ))}
          </select>
        </div>
      </div>

      {error && <Alert>{error}</Alert>}

      {isLoading ? (
        <Loading />
      ) : groups.length === 0 && !error ? (
        <EmptyState title={track || status ? "Aucune capsule pour ce choix." : "Aucune capsule pour le moment."}>
          Rédigez une capsule à partir d'un contenu sourcé, puis faites-la valider.
        </EmptyState>
      ) : (
        groups.map((group) => (
          <section key={group.track} aria-labelledby={`track-${group.track}`} className="space-y-3">
            <h2 id={`track-${group.track}`} className="text-lg font-semibold text-gray-900">
              {TRACK_LABELS[group.track]}
            </h2>
            <ul className="space-y-2">
              {group.items.map((capsule) => {
                const missing = LANGS.filter((l) => !capsule.translations[l]?.title);
                return (
                  <li key={capsule.id}>
                    <Link
                      to={`/capsules/${capsule.id}`}
                      className="flex flex-col gap-2 rounded-2xl bg-white p-4 shadow-sm transition hover:shadow-md focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:outline-none sm:flex-row sm:items-center sm:justify-between"
                    >
                      <div className="min-w-0">
                        <p className="font-medium text-gray-900">
                          <span className="mr-2 text-gray-500 tabular-nums">#{capsule.order}</span>
                          {capsule.translations.fr?.title || <span className="italic text-gray-500">Sans titre français</span>}
                        </p>
                        <p className="mt-1 text-xs text-gray-600">
                          {capsule.quiz?.length ?? 0} question(s) de quiz · Licence {capsule.license || "CC-BY-4.0"}
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <StatusBadge status={capsule.status} />
                        {missing.length > 0 && <Badge tone="amber">Manque : {missing.join(", ")}</Badge>}
                      </div>
                    </Link>
                  </li>
                );
              })}
            </ul>
          </section>
        ))
      )}
    </div>
  );
}
