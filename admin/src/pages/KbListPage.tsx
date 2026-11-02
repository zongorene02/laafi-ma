import { useState, type FormEvent } from "react";
import { Link } from "react-router-dom";
import { listKbEntries, type KbFilters } from "../api/kb";
import { KB_TOPICS, type ContentStatus, type KbEntry, type KbTopic } from "../api/types";
import { Alert, Badge, EmptyState, Loading, PageHeader, StatusBadge } from "../components/ui";
import { CONTENT_STATUSES, formatDate, LANGS, STATUS_LABELS, TOPIC_LABELS } from "../lib/labels";
import { missingLangs } from "../lib/mappers";
import { useAsync } from "../lib/useAsync";
import { btnPrimary, btnSecondary, inputClass, labelClass } from "../lib/styles";


export default function KbListPage() {
  const [status, setStatus] = useState<ContentStatus | "">("");
  const [topic, setTopic] = useState<KbTopic | "">("");
  const [search, setSearch] = useState("");
  const [applied, setApplied] = useState<KbFilters>({});
  const { data, error, isLoading } = useAsync(() => listKbEntries(applied), JSON.stringify(applied));
  const entries: KbEntry[] = data ?? [];

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setApplied({ status, topic, q: search });
  }

  function reset() {
    setStatus("");
    setTopic("");
    setSearch("");
    setApplied({});
  }

  const filtered = Boolean(applied.status || applied.topic || applied.q?.trim());

  return (
    <div className="space-y-6">
      <PageHeader
        title="Base de réponses"
        description="Questions-réponses de santé servies par l'assistant vocal. Seules les réponses validées par une sage-femme ou un médecin sont envoyées à l'application."
        actions={
          <Link to="/kb/new" className={btnPrimary}>
            Nouvelle réponse
          </Link>
        }
      />

      <form onSubmit={handleSubmit} className="grid grid-cols-1 gap-3 rounded-2xl bg-white p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <label htmlFor="kb-status" className={labelClass}>Statut</label>
          <select id="kb-status" value={status} onChange={(e) => setStatus(e.target.value as ContentStatus | "")} className={inputClass}>
            <option value="">Tous</option>
            {CONTENT_STATUSES.map((s) => (
              <option key={s} value={s}>{STATUS_LABELS[s]}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="kb-topic" className={labelClass}>Thème</label>
          <select id="kb-topic" value={topic} onChange={(e) => setTopic(e.target.value as KbTopic | "")} className={inputClass}>
            <option value="">Tous</option>
            {KB_TOPICS.map((t) => (
              <option key={t} value={t}>{TOPIC_LABELS[t]}</option>
            ))}
          </select>
        </div>
        <div>
          <label htmlFor="kb-search" className={labelClass}>Recherche</label>
          <input id="kb-search" type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Mot de la question ou de la réponse" className={inputClass} />
        </div>
        <div className="flex items-end gap-2">
          <button type="submit" className={btnPrimary}>Filtrer</button>
          <button type="button" onClick={reset} className={btnSecondary}>Réinitialiser</button>
        </div>
      </form>

      {error && <Alert>{error}</Alert>}

      {isLoading ? (
        <Loading />
      ) : entries.length === 0 && !error ? (
        filtered ? (
          <EmptyState title="Aucune réponse ne correspond à ces filtres." />
        ) : (
          <EmptyState title="La base de réponses est vide.">
            Créez une première réponse à partir d'une source reconnue (protocole national, OMS…), puis faites-la valider.
          </EmptyState>
        )
      ) : (
        <ul className="space-y-3">
          {entries.map((entry) => {
            const fr = entry.translations.fr;
            const missing = missingLangs(entry.translations);
            const machine = LANGS.filter((l) => entry.translations[l]?.machine_translated);
            return (
              <li key={entry.id}>
                <Link
                  to={`/kb/${entry.id}`}
                  className="block rounded-2xl bg-white p-4 shadow-sm transition hover:shadow-md focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:outline-none"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <StatusBadge status={entry.status} />
                    <Badge>{TOPIC_LABELS[entry.topic] ?? entry.topic}</Badge>
                    {entry.is_danger_topic && <Badge tone="red">Sujet à risque</Badge>}
                    {machine.length > 0 && (
                      <Badge tone="violet">Trad. automatique : {machine.join(", ")}</Badge>
                    )}
                    {missing.length > 0 && <Badge tone="amber">Manque : {missing.join(", ")}</Badge>}
                  </div>
                  <p className="mt-2 font-medium text-gray-900">
                    {fr?.question || <span className="text-gray-500 italic">Pas encore de question en français</span>}
                  </p>
                  {fr?.answer && <p className="mt-1 line-clamp-2 text-sm text-gray-600">{fr.answer}</p>}
                  <p className="mt-2 text-xs text-gray-500">Modifié le {formatDate(entry.updated_at)}</p>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
