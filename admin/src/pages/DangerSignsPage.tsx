import { useRef, useState, type FormEvent } from "react";
import { apiErrorMessage } from "../api/client";
import { createDangerSign, deleteDangerSign, listDangerSigns, updateDangerSign, validateDangerSign } from "../api/kb";
import {
  DANGER_AGENT_QUESTION_MAX_CHARS,
  DANGER_AGENT_QUESTIONS_MAX,
  DANGER_REFER_WHEN_MAX_CHARS,
  type ContentStatus,
  type DangerSign,
  type Lang,
} from "../api/types";
import { Alert, Badge, ChipsInput, EmptyState, LangTabs, Loading, PageHeader, StatusBadge, ValidationInfo } from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { CONTENT_STATUSES, editSendsToDraft, LANG_LABELS, LANGS, STATUS_LABELS } from "../lib/labels";
import {
  buildDangerSignPayload,
  dangerSignProblems,
  normalizeDangerTranslations,
  splitAgentQuestions,
  type DangerSignTranslationForm,
} from "../lib/mappers";
import { can } from "../lib/roles";
import { useAsync } from "../lib/useAsync";
import { btnDanger, btnPrimary, btnSecondary, btnSuccess, cardClass, inputClass, labelClass } from "../lib/styles";

interface DangerForm {
  translations: Record<Lang, DangerSignTranslationForm>;
  keywords_fr: string[];
  source: string;
}

function emptyForm(): DangerForm {
  return { translations: normalizeDangerTranslations(null), keywords_fr: [], source: "" };
}

export default function DangerSignsPage() {
  const { user } = useAuth();
  const canValidate = can(user?.role, "validate");
  const { data, error: loadError, isLoading, mutate } = useAsync(listDangerSigns, "danger-signs");
  const signs: DangerSign[] = data ?? [];
  const [status, setStatus] = useState<ContentStatus | "">("");
  const shownSigns = status ? signs.filter((s) => s.status === status) : signs;
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<DangerSign | "new" | null>(null);
  const [form, setForm] = useState<DangerForm>(emptyForm);
  const [activeLang, setActiveLang] = useState<Lang>("fr");
  const [busy, setBusy] = useState<string | null>(null);
  const formRef = useRef<HTMLFormElement>(null);

  function openEditor(sign: DangerSign | "new") {
    setEditing(sign);
    setActiveLang("fr");
    setError(null);
    setNotice(null);
    setForm(
      sign === "new"
        ? emptyForm()
        : {
            translations: normalizeDangerTranslations(sign.translations),
            keywords_fr: [...(sign.keywords_fr ?? [])],
            source: sign.source ?? "",
          },
    );
    requestAnimationFrame(() => formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
  }

  function replaceSign(updated: DangerSign) {
    mutate((prev) => {
      const list = prev ?? [];
      return list.some((s) => s.id === updated.id) ? list.map((s) => (s.id === updated.id ? updated : s)) : [updated, ...list];
    });
  }

  async function run(key: string, action: () => Promise<void>) {
    setBusy(key);
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
    const payload = buildDangerSignPayload(form);
    if (!payload.translations.fr) {
      setError("Le libellé et le conseil en français sont obligatoires.");
      setActiveLang("fr");
      return;
    }
    if (payload.keywords_fr.length === 0) {
      setError("Ajoutez au moins un mot-clé français : c'est lui qui déclenche la détection du signe de danger.");
      return;
    }
    const problems = dangerSignProblems(form.translations);
    if (problems.length > 0) {
      setError(`Fiche d'aide à la décision : ${problems.join(" ")}`);
      return;
    }
    if (
      editing !== "new" &&
      editSendsToDraft(editing?.status) &&
      !confirm(
        `Ce signe de danger est ${editing?.status === "sourced" ? "sourcé, non relu" : "validé"}. L'enregistrer le renverra en brouillon : il ne sera plus détecté par l'application tant qu'il n'aura pas été revalidé. Continuer ?`,
      )
    ) {
      return;
    }
    await run("save", async () => {
      const saved = editing === "new" || !editing ? await createDangerSign(payload) : await updateDangerSign(editing.id, payload);
      replaceSign(saved);
      setEditing(null);
      setNotice(editing === "new" ? "Signe de danger créé en brouillon." : "Signe de danger enregistré.");
    });
  }

  async function handleValidate(sign: DangerSign) {
    await run(`validate-${sign.id}`, async () => {
      replaceSign(await validateDangerSign(sign.id));
      setNotice("Signe de danger validé : il sera détecté par l'application.");
    });
  }

  async function handleDelete(sign: DangerSign) {
    const label = sign.translations.fr?.label || "ce signe de danger";
    if (!confirm(`Supprimer définitivement « ${label} » ?`)) return;
    await run(`delete-${sign.id}`, async () => {
      await deleteDangerSign(sign.id);
      mutate((prev) => (prev ?? []).filter((s) => s.id !== sign.id));
      if (editing !== "new" && editing?.id === sign.id) setEditing(null);
    });
  }

  const current = form.translations[activeLang];
  const currentQuestions = splitAgentQuestions(current.agent_questions);

  function setCurrent(patch: Partial<DangerSignTranslationForm>) {
    setForm((f) => ({ ...f, translations: { ...f.translations, [activeLang]: { ...f.translations[activeLang], ...patch } } }));
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Signes de danger"
        description="Signes qui doivent pousser à consulter immédiatement. Ils sont détectés à partir des mots-clés français dans les questions posées, même hors connexion, une fois validés."
        actions={
          <button type="button" onClick={() => openEditor("new")} className={btnPrimary}>
            Nouveau signe de danger
          </button>
        }
      />

      <div className="max-w-xs">
        <label htmlFor="ds-status" className={labelClass}>Statut</label>
        <select id="ds-status" value={status} onChange={(e) => setStatus(e.target.value as ContentStatus | "")} className={inputClass}>
          <option value="">Tous les statuts</option>
          {CONTENT_STATUSES.map((s) => (
            <option key={s} value={s}>{STATUS_LABELS[s]}</option>
          ))}
        </select>
      </div>

      {loadError && <Alert>{loadError}</Alert>}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}
      {notice && <Alert kind="success" onClose={() => setNotice(null)}>{notice}</Alert>}

      {editing && (
        <form ref={formRef} onSubmit={handleSave} className={`${cardClass} space-y-4`} aria-label="Éditeur de signe de danger">
          <h2 className="text-lg font-semibold text-gray-900">
            {editing === "new" ? "Nouveau signe de danger" : "Modifier le signe de danger"}
          </h2>
          {editing !== "new" && editSendsToDraft(editing.status) && (
            <Alert kind="warning">
              Ce signe est {editing.status === "sourced" ? "sourcé, non relu par une sage-femme" : "validé"}. Toute
              modification enregistrée le renverra en brouillon jusqu'à une nouvelle validation.
            </Alert>
          )}
          <LangTabs
            idPrefix="ds"
            value={activeLang}
            onChange={setActiveLang}
            marks={Object.fromEntries(
              LANGS.filter((l) => !form.translations[l].label.trim()).map((l) => [l, "à compléter"]),
            )}
          />
          <div id="ds-panel" role="tabpanel" aria-labelledby={`ds-tab-${activeLang}`} className="space-y-4">
            <div>
              <label htmlFor="ds-label" className={labelClass}>Libellé ({LANG_LABELS[activeLang]})</label>
              <input
                id="ds-label"
                value={current.label}
                onChange={(e) =>
                  setForm((f) => ({ ...f, translations: { ...f.translations, [activeLang]: { ...current, label: e.target.value } } }))
                }
                placeholder={activeLang === "fr" ? "Ex. : Saignement pendant la grossesse" : undefined}
                className={inputClass}
              />
            </div>
            <div>
              <label htmlFor="ds-advice" className={labelClass}>Conseil à donner ({LANG_LABELS[activeLang]})</label>
              <textarea
                id="ds-advice"
                rows={3}
                value={current.advice}
                onChange={(e) =>
                  setForm((f) => ({ ...f, translations: { ...f.translations, [activeLang]: { ...current, advice: e.target.value } } }))
                }
                className={inputClass}
              />
            </div>
            <fieldset className="space-y-4 rounded-xl border border-gray-200 bg-gray-50 p-4">
              <legend className="px-1 text-sm font-semibold text-gray-900">
                Fiche d'aide à la décision (agents) — {LANG_LABELS[activeLang]}
              </legend>
              <p className="text-xs text-gray-600">
                Affichée aux agents de santé quand ce signe est repéré. Si une langue est vide, l'application affiche la
                version française. Comme les autres champs, toute modification renvoie un signe validé en brouillon.
              </p>
              <div>
                <label htmlFor="ds-questions" className={labelClass}>Questions à poser ({LANG_LABELS[activeLang]})</label>
                <textarea
                  id="ds-questions"
                  rows={4}
                  value={current.agent_questions}
                  onChange={(e) => setCurrent({ agent_questions: e.target.value })}
                  aria-describedby="ds-questions-help"
                  placeholder={activeLang === "fr" ? "Depuis quand ?\nCombien de linges par jour ?" : undefined}
                  className={inputClass}
                />
                <p
                  id="ds-questions-help"
                  className={`mt-1 text-xs ${
                    currentQuestions.length > DANGER_AGENT_QUESTIONS_MAX ||
                    currentQuestions.some((q) => q.length > DANGER_AGENT_QUESTION_MAX_CHARS)
                      ? "font-medium text-red-700"
                      : "text-gray-500"
                  }`}
                >
                  Une question par ligne — {currentQuestions.length}/{DANGER_AGENT_QUESTIONS_MAX} questions,{" "}
                  {DANGER_AGENT_QUESTION_MAX_CHARS} caractères maximum chacune.
                </p>
              </div>
              <div>
                <label htmlFor="ds-refer" className={labelClass}>Quand orienter vers le centre de santé ({LANG_LABELS[activeLang]})</label>
                <textarea
                  id="ds-refer"
                  rows={3}
                  maxLength={DANGER_REFER_WHEN_MAX_CHARS}
                  value={current.refer_when}
                  onChange={(e) => setCurrent({ refer_when: e.target.value })}
                  aria-describedby="ds-refer-help"
                  className={inputClass}
                />
                <p id="ds-refer-help" className="mt-1 text-xs text-gray-500">
                  {current.refer_when.length}/{DANGER_REFER_WHEN_MAX_CHARS} caractères.
                </p>
              </div>
            </fieldset>
          </div>
          <ChipsInput
            label="Mots-clés de détection (français)"
            values={form.keywords_fr}
            onChange={(keywords_fr) => setForm((f) => ({ ...f, keywords_fr }))}
            placeholder="Tapez un mot puis Entrée"
            help="La détection s'applique à la question traduite en français. Ajoutez les formes courantes (ex. « saigne », « saignement », « sang »)."
          />
          <div>
            <label htmlFor="ds-source" className={labelClass}>Source</label>
            <input
              id="ds-source"
              value={form.source}
              onChange={(e) => setForm((f) => ({ ...f, source: e.target.value }))}
              placeholder="Protocole national, OMS…"
              className={inputClass}
            />
          </div>
          <div className="flex flex-wrap gap-2">
            <button type="submit" disabled={busy !== null} className={btnPrimary}>
              {busy === "save" ? "Enregistrement…" : "Enregistrer"}
            </button>
            <button type="button" onClick={() => setEditing(null)} className={btnSecondary}>
              Annuler
            </button>
          </div>
        </form>
      )}

      {isLoading ? (
        <Loading />
      ) : shownSigns.length === 0 && !loadError ? (
        <EmptyState title={status ? "Aucun signe de danger avec ce statut." : "Aucun signe de danger saisi."}>
          Ajoutez les signes de danger à partir d'une source médicale reconnue, puis faites-les valider.
        </EmptyState>
      ) : (
        <ul className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {shownSigns.map((sign) => {
            const fr = sign.translations.fr;
            const missing = LANGS.filter((l) => !sign.translations[l]?.label);
            return (
              <li key={sign.id} className={`${cardClass} flex flex-col gap-2`}>
                <div className="flex flex-wrap items-center gap-2">
                  <StatusBadge status={sign.status} />
                  {missing.length > 0 && <Badge tone="amber">Manque : {missing.join(", ")}</Badge>}
                </div>
                <p className="font-semibold text-gray-900">{fr?.label || <span className="italic text-gray-500">Sans libellé français</span>}</p>
                {fr?.advice && <p className="text-sm text-gray-700">{fr.advice}</p>}
                {sign.keywords_fr?.length > 0 && (
                  <p className="text-xs text-gray-600">
                    <span className="font-medium">Mots-clés :</span> {sign.keywords_fr.join(", ")}
                  </p>
                )}
                <p className="text-xs text-gray-600">
                  <span className="font-medium">Fiche agents :</span>{" "}
                  {(fr?.agent_questions?.length ?? 0) > 0 || fr?.refer_when
                    ? `${fr?.agent_questions?.length ?? 0} question(s) à poser${fr?.refer_when ? ", critère d'orientation renseigné" : ", critère d'orientation à compléter"}`
                    : "à compléter"}
                </p>
                {sign.source && <p className="text-xs text-gray-500">Source : {sign.source}</p>}
                <ValidationInfo validatedBy={sign.validated_by} validatedAt={sign.validated_at} />
                <div className="mt-auto flex flex-wrap gap-2 pt-2">
                  <button type="button" onClick={() => openEditor(sign)} className={btnSecondary}>
                    Modifier
                  </button>
                  {canValidate && sign.status !== "validated" && (
                    <button type="button" onClick={() => handleValidate(sign)} disabled={busy !== null} className={btnSuccess}>
                      Valider
                    </button>
                  )}
                  <button type="button" onClick={() => handleDelete(sign)} disabled={busy !== null} className={btnDanger}>
                    Supprimer
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
