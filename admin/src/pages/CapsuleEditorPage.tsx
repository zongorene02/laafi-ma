import { useEffect, useState, type FormEvent } from "react";
import { Link, useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { apiErrorMessage } from "../api/client";
import { createCapsule, deleteCapsule, listCapsules, updateCapsule, uploadCapsuleAudio, validateCapsule } from "../api/learn";
import { CAPSULE_TRACKS, type Capsule, type CapsuleTrack, type Lang, type QuizQuestion } from "../api/types";
import { Alert, AudioPanel, Badge, LangTabs, Loading, PageHeader, StatusBadge, ValidationInfo } from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { LANG_LABELS, LANGS, TRACK_LABELS } from "../lib/labels";
import { buildCapsulePayload, normalizeCapsuleTranslations, quizProblems, removeChoice } from "../lib/mappers";
import { can } from "../lib/roles";
import { btnDanger, btnPrimary, btnSecondary, btnSuccess, cardClass, inputClass, labelClass } from "../lib/styles";

type TextForm = Record<Lang, { title: string; text: string }>;

function textsFrom(capsule: Capsule | null): TextForm {
  const normalized = normalizeCapsuleTranslations(capsule?.translations);
  return {
    fr: { title: normalized.fr.title, text: normalized.fr.text },
    mos: { title: normalized.mos.title, text: normalized.mos.text },
    dyu: { title: normalized.dyu.title, text: normalized.dyu.text },
  };
}

function newQuestion(): QuizQuestion {
  return { question: { fr: "" }, choices: [{ fr: "" }, { fr: "" }], correct_index: 0 };
}

function isTrack(value: string | null): value is CapsuleTrack {
  return !!value && (CAPSULE_TRACKS as readonly string[]).includes(value);
}

export default function CapsuleEditorPage() {
  const { id } = useParams<{ id: string }>();
  const isNew = !id;
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const location = useLocation();
  const { user } = useAuth();
  const canValidate = can(user?.role, "validate");
  const initialTrack = searchParams.get("track");

  const [capsule, setCapsule] = useState<Capsule | null>(null);
  const [isLoading, setIsLoading] = useState(!isNew);
  const [track, setTrack] = useState<CapsuleTrack>(isTrack(initialTrack) ? initialTrack : "general");
  const [order, setOrder] = useState(0);
  const [texts, setTexts] = useState<TextForm>(() => textsFrom(null));
  const [quiz, setQuiz] = useState<QuizQuestion[]>([]);
  const [activeLang, setActiveLang] = useState<Lang>("fr");
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(
    () => (location.state as { notice?: string } | null)?.notice ?? null,
  );

  function apply(next: Capsule) {
    setCapsule(next);
    setTrack(next.track);
    setOrder(next.order ?? 0);
    setTexts(textsFrom(next));
    setQuiz(
      (next.quiz ?? []).map((q) => ({
        question: { ...q.question },
        choices: q.choices.map((c) => ({ ...c })),
        correct_index: q.correct_index,
      })),
    );
    setDirty(false);
  }

  useEffect(() => {
    if (!id) return;
    let cancelled = false;
    // Pas de GET /learn/capsules/{id} dans le contrat : on relit la liste.
    listCapsules()
      .then((all) => {
        if (cancelled) return;
        const found = all.find((c) => c.id === id);
        if (found) apply(found);
        else setError("Capsule introuvable.");
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

  function touch() {
    setDirty(true);
  }

  function updateQuestion(index: number, next: QuizQuestion) {
    setQuiz((prev) => prev.map((q, i) => (i === index ? next : q)));
    touch();
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
    const payload = buildCapsulePayload({ track, order, translations: texts, quiz });
    if (!payload.translations.fr?.title || !payload.translations.fr?.text) {
      setActiveLang("fr");
      setError("Le titre et le texte en français sont obligatoires.");
      return;
    }
    const problems = quizProblems(payload.quiz);
    if (problems.length > 0) {
      setError(`Quiz incomplet : ${problems.join(" ")}`);
      return;
    }
    if (
      capsule?.status === "validated" &&
      !confirm("Cette capsule est validée. L'enregistrer la renverra en brouillon jusqu'à une nouvelle validation. Continuer ?")
    ) {
      return;
    }
    await run("save", async () => {
      if (capsule) {
        apply(await updateCapsule(capsule.id, payload));
        setNotice("Capsule enregistrée.");
      } else {
        const created = await createCapsule(payload);
        apply(created);
        setNotice("Capsule créée en brouillon.");
        navigate(`/capsules/${created.id}`, { replace: true, state: { notice: "Capsule créée en brouillon." } });
      }
    });
  }

  async function handleValidate() {
    if (!capsule) return;
    await run("validate", async () => {
      apply(await validateCapsule(capsule.id));
      setNotice("Capsule validée : elle sera proposée dans l'application.");
    });
  }

  async function handleDelete() {
    if (!capsule) return;
    if (!confirm("Supprimer définitivement cette capsule et ses audios ?")) return;
    await run("delete", async () => {
      await deleteCapsule(capsule.id);
      navigate("/capsules", { replace: true });
    });
  }

  if (isLoading) return <Loading />;
  if (!isNew && !capsule) {
    return (
      <div className="space-y-4">
        <Alert>{error ?? "Capsule introuvable."}</Alert>
        <Link to="/capsules" className={btnSecondary}>Retour aux capsules</Link>
      </div>
    );
  }

  const current = texts[activeLang];
  const serverTranslation = capsule?.translations[activeLang] ?? null;
  const isBusy = busy !== null;
  const marks: Partial<Record<Lang, string>> = {};
  for (const lang of LANGS) if (!texts[lang].title.trim() || !texts[lang].text.trim()) marks[lang] = "à compléter";

  return (
    <div className="space-y-6">
      <Link to="/capsules" className="text-sm font-medium text-brand-700 hover:underline">← Capsules</Link>
      <PageHeader
        title={isNew ? "Nouvelle capsule" : "Modifier la capsule"}
        description={
          <span className="inline-flex flex-wrap items-center gap-2">
            {capsule && <StatusBadge status={capsule.status} />}
            <Badge tone="blue">Licence {capsule?.license || "CC-BY-4.0"}</Badge>
            {capsule && <ValidationInfo validatedBy={capsule.validated_by} validatedAt={capsule.validated_at} />}
          </span>
        }
      />

      {capsule?.status === "validated" && (
        <Alert kind="warning">
          <strong>Capsule validée et publiée.</strong> Toute modification enregistrée la renverra en brouillon jusqu'à
          une nouvelle validation.
        </Alert>
      )}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}
      {notice && <Alert kind="success" onClose={() => setNotice(null)}>{notice}</Alert>}

      <form onSubmit={handleSave} className="space-y-6">
        <section className={`${cardClass} grid grid-cols-1 gap-4 sm:grid-cols-2`} aria-label="Parcours et ordre">
          <div>
            <label htmlFor="cap-track" className={labelClass}>Parcours</label>
            <select
              id="cap-track"
              value={track}
              onChange={(e) => {
                setTrack(e.target.value as CapsuleTrack);
                touch();
              }}
              className={inputClass}
            >
              {CAPSULE_TRACKS.map((t) => (
                <option key={t} value={t}>{TRACK_LABELS[t]}</option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="cap-order" className={labelClass}>Ordre dans le parcours</label>
            <input
              id="cap-order"
              type="number"
              min={0}
              step={1}
              value={order}
              onChange={(e) => {
                setOrder(Number(e.target.value));
                touch();
              }}
              className={inputClass}
            />
          </div>
        </section>

        <section className={`${cardClass} space-y-4`} aria-label="Contenu par langue">
          <LangTabs idPrefix="cap" value={activeLang} onChange={setActiveLang} marks={marks} />
          <div id="cap-panel" role="tabpanel" aria-labelledby={`cap-tab-${activeLang}`} className="space-y-4">
            <div>
              <label htmlFor="cap-title" className={labelClass}>Titre ({LANG_LABELS[activeLang]})</label>
              <input
                id="cap-title"
                value={current.title}
                onChange={(e) => {
                  setTexts((t) => ({ ...t, [activeLang]: { ...t[activeLang], title: e.target.value } }));
                  touch();
                }}
                className={inputClass}
              />
            </div>
            <div>
              <label htmlFor="cap-text" className={labelClass}>Texte ({LANG_LABELS[activeLang]})</label>
              <textarea
                id="cap-text"
                rows={8}
                value={current.text}
                onChange={(e) => {
                  setTexts((t) => ({ ...t, [activeLang]: { ...t[activeLang], text: e.target.value } }));
                  touch();
                }}
                className={inputClass}
              />
            </div>
            <AudioPanel
              key={activeLang}
              lang={activeLang}
              audioUrl={serverTranslation?.audio_url ?? null}
              audioKind={serverTranslation?.audio_kind ?? null}
              disabledReason={!capsule ? "Enregistrez d'abord la capsule pour pouvoir y joindre un audio." : undefined}
              onUpload={async (file) => {
                if (!capsule) return;
                setError(null);
                setNotice(null);
                try {
                  setCapsule(await uploadCapsuleAudio(capsule.id, activeLang, file));
                  setNotice(`Audio ${LANG_LABELS[activeLang]} enregistré.`);
                } catch (err) {
                  setError(apiErrorMessage(err));
                }
              }}
            />
          </div>
        </section>

        <section className={`${cardClass} space-y-4`} aria-labelledby="quiz-title">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 id="quiz-title" className="text-lg font-semibold text-gray-900">Quiz</h2>
              <p className="text-xs text-gray-600">
                Textes affichés dans la langue de l'onglet sélectionné ({LANG_LABELS[activeLang]}). Le français est
                obligatoire.
              </p>
            </div>
            <button
              type="button"
              onClick={() => {
                setQuiz((q) => [...q, newQuestion()]);
                touch();
              }}
              className={btnSecondary}
            >
              + Ajouter une question
            </button>
          </div>
          {quiz.length === 0 && <p className="text-sm text-gray-600">Aucune question. Le quiz est facultatif.</p>}
          {quiz.map((question, qi) => (
            <fieldset key={qi} className="rounded-xl border border-gray-200 p-4">
              <legend className="px-1 text-sm font-semibold text-gray-800">Question {qi + 1}</legend>
              <label htmlFor={`q-${qi}`} className="sr-only">
                Texte de la question {qi + 1} ({LANG_LABELS[activeLang]})
              </label>
              <input
                id={`q-${qi}`}
                value={question.question[activeLang] ?? ""}
                placeholder={`Question (${LANG_LABELS[activeLang]})`}
                onChange={(e) => updateQuestion(qi, { ...question, question: { ...question.question, [activeLang]: e.target.value } })}
                className={inputClass}
              />
              <div className="mt-3 space-y-2" role="radiogroup" aria-label={`Bonne réponse à la question ${qi + 1}`}>
                {question.choices.map((choice, ci) => (
                  <div key={ci} className="flex items-center gap-2">
                    <input
                      type="radio"
                      name={`correct-${qi}`}
                      checked={question.correct_index === ci}
                      onChange={() => updateQuestion(qi, { ...question, correct_index: ci })}
                      aria-label={`Choix ${ci + 1} est la bonne réponse`}
                      className="h-4 w-4 shrink-0 accent-green-700"
                    />
                    <input
                      aria-label={`Choix ${ci + 1} de la question ${qi + 1} (${LANG_LABELS[activeLang]})`}
                      value={choice[activeLang] ?? ""}
                      placeholder={`Choix ${ci + 1}`}
                      onChange={(e) =>
                        updateQuestion(qi, {
                          ...question,
                          choices: question.choices.map((c, j) => (j === ci ? { ...c, [activeLang]: e.target.value } : c)),
                        })
                      }
                      className={`${inputClass} mt-0`}
                    />
                    <button
                      type="button"
                      disabled={question.choices.length <= 2}
                      onClick={() => updateQuestion(qi, removeChoice(question, ci))}
                      className="shrink-0 rounded-lg border border-gray-300 px-2.5 py-2 text-xs text-gray-700 hover:bg-gray-50 disabled:opacity-40"
                      aria-label={`Retirer le choix ${ci + 1}`}
                    >
                      Retirer
                    </button>
                  </div>
                ))}
              </div>
              <p className="mt-2 text-xs text-gray-600">Cochez la bonne réponse (choix {question.correct_index + 1} actuellement).</p>
              <div className="mt-2 flex flex-wrap gap-3">
                <button
                  type="button"
                  onClick={() => updateQuestion(qi, { ...question, choices: [...question.choices, { fr: "" }] })}
                  className="text-sm font-medium text-brand-700 hover:underline"
                >
                  + Ajouter un choix
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setQuiz((q) => q.filter((_, i) => i !== qi));
                    touch();
                  }}
                  className="text-sm font-medium text-red-700 hover:underline"
                >
                  Supprimer la question
                </button>
              </div>
            </fieldset>
          ))}
        </section>

        <div className="sticky bottom-0 z-10 -mx-4 flex flex-wrap gap-2 border-t border-gray-200 bg-white/95 px-4 py-3 sm:mx-0 sm:rounded-2xl sm:border sm:shadow-sm">
          <button type="submit" disabled={isBusy || (!dirty && !isNew)} className={btnPrimary}>
            {busy === "save" ? "Enregistrement…" : "Enregistrer"}
          </button>
          {capsule && canValidate && capsule.status !== "validated" && (
            <button
              type="button"
              onClick={handleValidate}
              disabled={isBusy || dirty}
              title={dirty ? "Enregistrez d'abord vos modifications" : undefined}
              className={btnSuccess}
            >
              {busy === "validate" ? "Validation…" : "Valider"}
            </button>
          )}
          {capsule && (
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
