import axios from "axios";
import { useEffect, useState, type FormEvent } from "react";
import { Link, useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { apiErrorMessage } from "../api/client";
import {
  archiveKbEntry,
  createKbEntry,
  deleteKbEntry,
  getKbEntry,
  resolveUnanswered,
  translateKbEntry,
  updateKbEntry,
  uploadKbAudio,
  validateKbEntry,
} from "../api/kb";
import { KB_TOPICS, type KbEntry, type KbTopic, type KbTranslationInput, type Lang } from "../api/types";
import {
  Alert,
  AudioPanel,
  Badge,
  Loading,
  MachineTranslatedBadge,
  PageHeader,
  StatusBadge,
  StringListEditor,
  ValidationInfo,
  LangTabs,
} from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { LANG_LABELS, LANGS, TOPIC_LABELS } from "../lib/labels";
import { buildKbPayload, isKbTranslationFilled, missingLangs, normalizeKbTranslations } from "../lib/mappers";
import { can } from "../lib/roles";
import { btnDanger, btnPrimary, btnSecondary, btnSuccess, cardClass, inputClass, labelClass } from "../lib/styles";

type FormTranslations = Record<Lang, KbTranslationInput>;

function emptyForm(): FormTranslations {
  return {
    fr: { question: "", variants: [], answer: "" },
    mos: { question: "", variants: [], answer: "" },
    dyu: { question: "", variants: [], answer: "" },
  };
}

function formFromEntry(entry: KbEntry): FormTranslations {
  const normalized = normalizeKbTranslations(entry.translations);
  const out = emptyForm();
  for (const lang of LANGS) {
    out[lang] = {
      question: normalized[lang].question,
      variants: [...normalized[lang].variants],
      answer: normalized[lang].answer,
    };
  }
  return out;
}

export default function KbEditorPage() {
  const { id } = useParams<{ id: string }>();
  const isNew = !id;
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { user } = useAuth();
  const canValidate = can(user?.role, "validate");

  const fromUnansweredId = searchParams.get("unanswered");
  const prefillQuestion = searchParams.get("question") ?? "";

  const [entry, setEntry] = useState<KbEntry | null>(null);
  const [isLoading, setIsLoading] = useState(!isNew);
  const [topic, setTopic] = useState<KbTopic>("autre");
  const [isDangerTopic, setIsDangerTopic] = useState(false);
  const [source, setSource] = useState("");
  const [translations, setTranslations] = useState<FormTranslations>(() => {
    const form = emptyForm();
    form.fr.question = prefillQuestion;
    return form;
  });
  const [activeLang, setActiveLang] = useState<Lang>("fr");
  const [dirty, setDirty] = useState(false);
  const [resolveAfterCreate, setResolveAfterCreate] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(
    () => (location.state as { notice?: string } | null)?.notice ?? null,
  );

  function applyEntry(next: KbEntry) {
    setEntry(next);
    setTopic(next.topic);
    setIsDangerTopic(next.is_danger_topic);
    setSource(next.source ?? "");
    setTranslations(formFromEntry(next));
    setDirty(false);
  }

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    getKbEntry(id)
      .then((loaded) => {
        if (!cancelled) applyEntry(loaded);
      })
      .catch((err) => {
        if (!cancelled) setError(apiErrorMessage(err));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [id]);

  function updateLang(lang: Lang, patch: Partial<KbTranslationInput>) {
    setTranslations((prev) => ({ ...prev, [lang]: { ...prev[lang], ...patch } }));
    setDirty(true);
  }

  async function run(label: string, action: () => Promise<void>) {
    setBusy(label);
    setError(null);
    setNotice(null);
    try {
      await action();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(null);
    }
  }

  async function handleSave(event: FormEvent) {
    event.preventDefault();
    const payload = buildKbPayload({ topic, is_danger_topic: isDangerTopic, source, translations });
    if (Object.keys(payload.translations).length === 0) {
      setError("Saisissez au moins la question et la réponse dans une langue (de préférence le français).");
      return;
    }
    if (
      entry?.status === "validated" &&
      !confirm(
        "Cette réponse est validée. L'enregistrer la renverra en brouillon : elle ne sera plus servie à l'application tant qu'elle n'aura pas été validée à nouveau. Continuer ?",
      )
    ) {
      return;
    }
    await run("save", async () => {
      if (entry) {
        applyEntry(await updateKbEntry(entry.id, payload));
        setNotice("Modifications enregistrées.");
      } else {
        const created = await createKbEntry(payload);
        let resolveNote = "";
        if (fromUnansweredId && resolveAfterCreate) {
          try {
            await resolveUnanswered(fromUnansweredId);
            resolveNote = " La question d'origine est marquée comme résolue.";
          } catch (err) {
            resolveNote = ` La question d'origine n'a pas pu être marquée comme résolue : ${apiErrorMessage(err)}`;
          }
        }
        const message = `Réponse créée en brouillon.${resolveNote}`;
        applyEntry(created);
        setNotice(message);
        navigate(`/kb/${created.id}`, { replace: true, state: { notice: message } });
      }
    });
  }

  async function handleValidate() {
    if (!entry) return;
    setBusy("validate");
    setError(null);
    setNotice(null);
    try {
      applyEntry(await validateKbEntry(entry.id));
      setNotice("Réponse validée : elle sera servie à l'application.");
    } catch (err) {
      if (axios.isAxiosError(err) && err.response?.status === 409) {
        const detail = (err.response.data as { detail?: unknown } | undefined)?.detail;
        setError(
          typeof detail === "string" && detail
            ? detail
            : "Validation refusée : la traduction française (question et réponse) est obligatoire.",
        );
      } else {
        setError(apiErrorMessage(err));
      }
    } finally {
      setBusy(null);
    }
  }

  async function handleArchive() {
    if (!entry) return;
    if (!confirm("Archiver cette réponse ? Elle ne sera plus servie à l'application.")) return;
    await run("archive", async () => {
      applyEntry(await archiveKbEntry(entry.id));
      setNotice("Réponse archivée.");
    });
  }

  async function handleTranslate() {
    if (!entry) return;
    await run("translate", async () => {
      applyEntry(await translateKbEntry(entry.id));
      setNotice("Traduction automatique terminée. Les textes produits doivent être relus par une personne qui parle la langue.");
    });
  }

  async function handleDelete() {
    if (!entry) return;
    if (!confirm("Supprimer définitivement cette réponse et ses enregistrements audio ?")) return;
    await run("delete", async () => {
      await deleteKbEntry(entry.id);
      navigate("/kb", { replace: true });
    });
  }

  if (isLoading) return <Loading />;
  if (!isNew && !entry) {
    return (
      <div className="space-y-4">
        <Alert>{error ?? "Réponse introuvable."}</Alert>
        <Link to="/kb" className={btnSecondary}>Retour à la liste</Link>
      </div>
    );
  }

  const current = translations[activeLang];
  const serverTranslation = entry?.translations[activeLang] ?? null;
  const missingOnServer = entry ? missingLangs(entry.translations) : [];
  const missingTarget = missingOnServer.filter((l) => l !== "fr");
  const frFilled = isKbTranslationFilled(translations.fr);
  const marks: Partial<Record<Lang, string>> = {};
  for (const lang of LANGS) {
    if (!isKbTranslationFilled(translations[lang])) marks[lang] = "à compléter";
    else if (entry?.translations[lang]?.machine_translated) marks[lang] = "auto";
  }
  const isBusy = busy !== null;

  return (
    <div className="space-y-6">
      <div>
        <Link to="/kb" className="text-sm font-medium text-brand-700 hover:underline">← Base de réponses</Link>
      </div>
      <PageHeader
        title={isNew ? "Nouvelle réponse" : "Modifier la réponse"}
        description={
          entry ? (
            <span className="inline-flex flex-wrap items-center gap-2">
              <StatusBadge status={entry.status} />
              {entry.is_danger_topic && <Badge tone="red">Sujet à risque</Badge>}
              <ValidationInfo validatedBy={entry.validated_by} validatedAt={entry.validated_at} />
            </span>
          ) : (
            "La réponse sera créée en brouillon, puis devra être validée par une sage-femme ou un médecin."
          )
        }
      />

      {entry?.status === "validated" && (
        <Alert kind="warning">
          <strong>Réponse validée et servie à l'application.</strong> Toute modification enregistrée la renverra en
          brouillon : elle cessera d'être servie jusqu'à une nouvelle validation.
        </Alert>
      )}
      {entry?.status === "archived" && (
        <Alert kind="info">Réponse archivée : elle n'est plus servie à l'application.</Alert>
      )}
      {isNew && fromUnansweredId && (
        <Alert kind="info">
          Créée à partir d'une question restée sans réponse. La question (traduite en français) est pré-remplie ;
          vérifiez-la et rédigez la réponse.
        </Alert>
      )}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}
      {notice && <Alert kind="success" onClose={() => setNotice(null)}>{notice}</Alert>}

      <form onSubmit={handleSave} className="space-y-6">
        <section className={`${cardClass} grid grid-cols-1 gap-4 md:grid-cols-2`} aria-label="Informations générales">
          <div>
            <label htmlFor="kb-topic" className={labelClass}>Thème</label>
            <select
              id="kb-topic"
              value={topic}
              onChange={(e) => {
                setTopic(e.target.value as KbTopic);
                setDirty(true);
              }}
              className={inputClass}
            >
              {KB_TOPICS.map((t) => (
                <option key={t} value={t}>{TOPIC_LABELS[t]}</option>
              ))}
            </select>
          </div>
          <div className="flex items-end">
            <label className="flex items-center gap-2 text-sm text-gray-800">
              <input
                type="checkbox"
                checked={isDangerTopic}
                onChange={(e) => {
                  setIsDangerTopic(e.target.checked);
                  setDirty(true);
                }}
                className="h-4 w-4 accent-brand-600"
              />
              Sujet à risque (oriente vers un centre de santé)
            </label>
          </div>
          <div className="md:col-span-2">
            <label htmlFor="kb-source" className={labelClass}>Source</label>
            <input
              id="kb-source"
              value={source}
              onChange={(e) => {
                setSource(e.target.value);
                setDirty(true);
              }}
              placeholder="Ex. : protocole national de santé de la reproduction, recommandation OMS…"
              className={inputClass}
            />
            <p className="mt-1 text-xs text-gray-500">Référence officielle sur laquelle s'appuie la réponse.</p>
          </div>
        </section>

        <section className={cardClass} aria-label="Contenu par langue">
          <LangTabs idPrefix="kb" value={activeLang} onChange={setActiveLang} marks={marks} />
          <div id="kb-panel" role="tabpanel" aria-labelledby={`kb-tab-${activeLang}`} className="mt-4 space-y-4">
            {serverTranslation?.machine_translated && (
              <div className="flex flex-wrap items-center gap-2">
                <MachineTranslatedBadge />
                <p className="text-xs text-gray-600">Modifier ce texte puis l'enregistrer le marque comme relu.</p>
              </div>
            )}
            {activeLang === "fr" && (
              <p className="text-xs text-gray-600">Le français est obligatoire pour valider la réponse.</p>
            )}
            <div>
              <label htmlFor="kb-question" className={labelClass}>Question ({LANG_LABELS[activeLang]})</label>
              <input
                id="kb-question"
                value={current.question}
                onChange={(e) => updateLang(activeLang, { question: e.target.value })}
                className={inputClass}
              />
            </div>
            <StringListEditor
              label="Autres formulations de la question"
              values={current.variants}
              onChange={(variants) => updateLang(activeLang, { variants })}
              addLabel="Ajouter une formulation"
              itemLabel={(i) => `Formulation ${i + 1} (${LANG_LABELS[activeLang]})`}
            />
            <div>
              <label htmlFor="kb-answer" className={labelClass}>Réponse ({LANG_LABELS[activeLang]})</label>
              <textarea
                id="kb-answer"
                rows={6}
                value={current.answer}
                onChange={(e) => updateLang(activeLang, { answer: e.target.value })}
                className={inputClass}
              />
            </div>
            <AudioPanel
              key={activeLang}
              lang={activeLang}
              audioUrl={serverTranslation?.audio_url ?? null}
              audioKind={serverTranslation?.audio_kind ?? null}
              disabledReason={!entry ? "Enregistrez d'abord la réponse pour pouvoir y joindre un audio." : undefined}
              onUpload={async (file) => {
                if (!entry) return;
                setError(null);
                setNotice(null);
                try {
                  const updated = await uploadKbAudio(entry.id, activeLang, file);
                  // On garde les textes en cours de saisie, seul l'audio change.
                  setEntry(updated);
                  setNotice(`Audio ${LANG_LABELS[activeLang]} enregistré.`);
                } catch (err) {
                  setError(apiErrorMessage(err));
                }
              }}
            />
          </div>
        </section>

        {isNew && fromUnansweredId && (
          <label className="flex items-center gap-2 text-sm text-gray-800">
            <input
              type="checkbox"
              checked={resolveAfterCreate}
              onChange={(e) => setResolveAfterCreate(e.target.checked)}
              className="h-4 w-4 accent-brand-600"
            />
            Marquer la question d'origine comme résolue après l'enregistrement
          </label>
        )}

        <div className="sticky bottom-0 z-10 -mx-4 flex flex-wrap gap-2 border-t border-gray-200 bg-white/95 px-4 py-3 sm:mx-0 sm:rounded-2xl sm:border sm:shadow-sm">
          <button type="submit" disabled={isBusy || (!dirty && !isNew)} className={btnPrimary}>
            {busy === "save" ? "Enregistrement…" : "Enregistrer"}
          </button>
          {entry && canValidate && entry.status !== "validated" && (
            <button
              type="button"
              onClick={handleValidate}
              disabled={isBusy || dirty}
              title={dirty ? "Enregistrez d'abord vos modifications" : !frFilled ? "Le français est obligatoire" : undefined}
              className={btnSuccess}
            >
              {busy === "validate" ? "Validation…" : "Valider"}
            </button>
          )}
          {entry && missingTarget.length > 0 && (
            <button
              type="button"
              onClick={handleTranslate}
              disabled={isBusy || dirty || !frFilled}
              title={dirty ? "Enregistrez d'abord vos modifications" : undefined}
              className={btnSecondary}
            >
              {busy === "translate" ? "Traduction…" : "Traduire automatiquement les langues manquantes"}
            </button>
          )}
          {entry && entry.status !== "archived" && (
            <button type="button" onClick={handleArchive} disabled={isBusy} className={btnSecondary}>
              Archiver
            </button>
          )}
          {entry && (
            <button type="button" onClick={handleDelete} disabled={isBusy} className={btnDanger}>
              Supprimer
            </button>
          )}
          {dirty && <p className="self-center text-xs text-amber-800">Modifications non enregistrées.</p>}
        </div>
      </form>
    </div>
  );
}
