import {
  AGENT_ACTIVITY_TYPES,
  DANGER_AGENT_QUESTION_MAX_CHARS,
  DANGER_AGENT_QUESTIONS_MAX,
  DANGER_REFER_WHEN_MAX_CHARS,
  type AgentActivityType,
} from "../api/types.ts";
import type {
  Capsule,
  CapsulePayload,
  CapsuleTranslation,
  DangerSign,
  DangerSignPayload,
  KbEntry,
  KbEntryPayload,
  KbTranslation,
  KbTranslationInput,
  Lang,
  LocalizedText,
  PublicStats,
  QuizQuestion,
} from "../api/types.ts";

// Conversions entre les objets du contrat (où une langue peut manquer) et les
// formulaires (où chaque langue a toujours des champs, éventuellement vides).

const LANG_ORDER: readonly Lang[] = ["fr", "mos", "dyu"];
const LANG_NAMES: Record<Lang, string> = { fr: "Français", mos: "Mooré", dyu: "Dioula" };

export function emptyKbTranslation(): KbTranslation {
  return { question: "", variants: [], answer: "", audio_url: null, audio_kind: null, machine_translated: false };
}

/** Chaque langue présente, champs manquants remplacés par des valeurs vides. */
export function normalizeKbTranslations(
  translations: KbEntry["translations"] | null | undefined,
): Record<Lang, KbTranslation> {
  const out = {} as Record<Lang, KbTranslation>;
  for (const lang of LANG_ORDER) {
    const t = translations?.[lang];
    out[lang] = {
      ...emptyKbTranslation(),
      ...(t ?? {}),
      variants: Array.isArray(t?.variants) ? t.variants : [],
      question: t?.question ?? "",
      answer: t?.answer ?? "",
    };
  }
  return out;
}

export function isKbTranslationFilled(t: Pick<KbTranslationInput, "question" | "answer"> | null | undefined): boolean {
  return !!t && t.question.trim() !== "" && t.answer.trim() !== "";
}

/** Corps de POST/PUT `/kb/entries` : seules les langues réellement saisies
 * sont envoyées (une langue vide = « manquante » pour le backend, ce qui
 * permet la traduction automatique et le refus 409 si le fr manque). */
export function buildKbPayload(form: {
  topic: KbEntryPayload["topic"];
  is_danger_topic: boolean;
  source: string;
  translations: Record<Lang, KbTranslationInput>;
}): KbEntryPayload {
  const translations: KbEntryPayload["translations"] = {};
  for (const lang of LANG_ORDER) {
    const t = form.translations[lang];
    const question = t.question.trim();
    const answer = t.answer.trim();
    const variants = t.variants.map((v) => v.trim()).filter((v) => v !== "");
    if (question === "" && answer === "" && variants.length === 0) continue;
    translations[lang] = { question, variants: dedupe(variants), answer };
  }
  return {
    topic: form.topic,
    is_danger_topic: form.is_danger_topic,
    source: form.source.trim() || null,
    translations,
  };
}

/** Langues absentes ou incomplètes d'une entrée. */
export function missingLangs(translations: Partial<Record<Lang, { question?: string; answer?: string } | null>>): Lang[] {
  return LANG_ORDER.filter((lang) => {
    const t = translations[lang];
    return !t || !(t.question ?? "").trim() || !(t.answer ?? "").trim();
  });
}

/** Champs du formulaire d'un signe de danger pour une langue. Les questions
 * de la fiche agents sont saisies une par ligne. */
export interface DangerSignTranslationForm {
  label: string;
  advice: string;
  agent_questions: string;
  refer_when: string;
}

export function normalizeDangerTranslations(
  translations: DangerSign["translations"] | null | undefined,
): Record<Lang, DangerSignTranslationForm> {
  const out = {} as Record<Lang, DangerSignTranslationForm>;
  for (const lang of LANG_ORDER) {
    const t = translations?.[lang];
    out[lang] = {
      label: t?.label ?? "",
      advice: t?.advice ?? "",
      agent_questions: Array.isArray(t?.agent_questions) ? t.agent_questions.join("\n") : "",
      refer_when: t?.refer_when ?? "",
    };
  }
  return out;
}

/** Une question par ligne, lignes vides ignorées. */
export function splitAgentQuestions(raw: string): string[] {
  return raw
    .split(/\r?\n/)
    .map((q) => q.trim())
    .filter((q) => q !== "");
}

/** Dépassements des limites du contrat pour la fiche agents (en français). */
export function dangerSignProblems(translations: Record<Lang, DangerSignTranslationForm>): string[] {
  const problems: string[] = [];
  for (const lang of LANG_ORDER) {
    const name = LANG_NAMES[lang];
    const questions = splitAgentQuestions(translations[lang].agent_questions);
    if (questions.length > DANGER_AGENT_QUESTIONS_MAX) {
      problems.push(`${name} : ${DANGER_AGENT_QUESTIONS_MAX} questions au maximum (${questions.length} saisies).`);
    }
    questions.forEach((q, i) => {
      if (q.length > DANGER_AGENT_QUESTION_MAX_CHARS) {
        problems.push(`${name}, question ${i + 1} : ${DANGER_AGENT_QUESTION_MAX_CHARS} caractères au maximum.`);
      }
    });
    if (translations[lang].refer_when.trim().length > DANGER_REFER_WHEN_MAX_CHARS) {
      problems.push(`${name} : « Quand orienter » dépasse ${DANGER_REFER_WHEN_MAX_CHARS} caractères.`);
    }
  }
  return problems;
}

/** Corps de POST/PUT `/kb/danger-signs`. Une langue entièrement vide n'est
 * pas envoyée ; sinon `agent_questions` / `refer_when` sont toujours
 * présents (`[]` / `null` pour effacer). */
export function buildDangerSignPayload(form: {
  translations: Record<Lang, DangerSignTranslationForm>;
  keywords_fr: string[];
  source: string;
}): DangerSignPayload {
  const translations: DangerSignPayload["translations"] = {};
  for (const lang of LANG_ORDER) {
    const t = form.translations[lang];
    const label = t.label.trim();
    const advice = t.advice.trim();
    const agent_questions = dedupe(splitAgentQuestions(t.agent_questions));
    const refer_when = t.refer_when.trim() || null;
    if (label === "" && advice === "" && agent_questions.length === 0 && refer_when === null) continue;
    translations[lang] = { label, advice, agent_questions, refer_when };
  }
  return {
    translations,
    keywords_fr: normalizeKeywords(form.keywords_fr),
    source: form.source.trim() || null,
  };
}

/** Mots-clés fr : minuscules, sans espaces superflus, sans doublons. */
export function normalizeKeywords(keywords: string[]): string[] {
  return dedupe(keywords.map((k) => k.trim().toLowerCase().replace(/\s+/g, " ")).filter((k) => k !== ""));
}

/** Découpe une saisie « saigne, sang; saignement » en mots-clés. */
export function splitKeywordInput(raw: string): string[] {
  return raw
    .split(/[,;\n]/)
    .map((k) => k.trim())
    .filter((k) => k !== "");
}

export function normalizeCapsuleTranslations(
  translations: Capsule["translations"] | null | undefined,
): Record<Lang, CapsuleTranslation> {
  const out = {} as Record<Lang, CapsuleTranslation>;
  for (const lang of LANG_ORDER) {
    const t = translations?.[lang];
    out[lang] = {
      title: t?.title ?? "",
      text: t?.text ?? "",
      audio_url: t?.audio_url ?? null,
      audio_kind: t?.audio_kind ?? null,
    };
  }
  return out;
}

function cleanLocalized(text: LocalizedText): LocalizedText {
  const out: LocalizedText = {};
  for (const lang of LANG_ORDER) {
    const value = text[lang]?.trim();
    if (value) out[lang] = value;
  }
  return out;
}

export function buildCapsulePayload(form: {
  track: CapsulePayload["track"];
  order: number;
  translations: Record<Lang, { title: string; text: string }>;
  quiz: QuizQuestion[];
}): CapsulePayload {
  const translations: CapsulePayload["translations"] = {};
  for (const lang of LANG_ORDER) {
    const title = form.translations[lang].title.trim();
    const text = form.translations[lang].text.trim();
    if (title === "" && text === "") continue;
    translations[lang] = { title, text };
  }
  const quiz = form.quiz.map((q) => ({
    question: cleanLocalized(q.question),
    choices: q.choices.map(cleanLocalized),
    correct_index: q.correct_index,
  }));
  return { track: form.track, order: Number.isFinite(form.order) ? Math.trunc(form.order) : 0, translations, quiz };
}

/** Problèmes bloquants du quiz (en français), vide si tout va bien. */
export function quizProblems(quiz: QuizQuestion[]): string[] {
  const problems: string[] = [];
  quiz.forEach((q, i) => {
    const n = i + 1;
    if (!q.question.fr?.trim()) problems.push(`Question ${n} : le texte en français est obligatoire.`);
    if (q.choices.length < 2) problems.push(`Question ${n} : au moins deux choix sont nécessaires.`);
    q.choices.forEach((c, j) => {
      if (!c.fr?.trim()) problems.push(`Question ${n}, choix ${j + 1} : le texte en français est obligatoire.`);
    });
    if (q.correct_index < 0 || q.correct_index >= q.choices.length) {
      problems.push(`Question ${n} : indiquez la bonne réponse.`);
    }
  });
  return problems;
}

/** Supprime un choix en gardant `correct_index` cohérent. */
export function removeChoice(question: QuizQuestion, index: number): QuizQuestion {
  const choices = question.choices.filter((_, j) => j !== index);
  let correct = question.correct_index;
  if (index === correct) correct = 0;
  else if (index < correct) correct -= 1;
  return { ...question, choices, correct_index: Math.min(Math.max(correct, 0), Math.max(choices.length - 1, 0)) };
}

// ---- Statistiques publiques -------------------------------------------------

/** Lignes par semaine pour un type d'événement donné, triées. */
export function weeklySeries(stats: PublicStats, type: string): { week: string; count: number }[] {
  return stats.by_week
    .filter((row) => row.type === type)
    .map((row) => ({ week: row.week, count: row.count }))
    .sort((a, b) => a.week.localeCompare(b.week));
}

export function langSeries(stats: PublicStats, type: string): { lang: string; count: number }[] {
  const order = (lang: string) => {
    const i = LANG_ORDER.indexOf(lang as Lang);
    return i === -1 ? LANG_ORDER.length : i;
  };
  return stats.by_lang
    .filter((row) => row.type === type)
    .map((row) => ({ lang: row.lang, count: row.count }))
    .sort((a, b) => order(a.lang) - order(b.lang));
}

export function districtSeries(stats: PublicStats, type: string): { district: string; count: number }[] {
  return stats.by_district
    .filter((row) => row.type === type)
    .map((row) => ({ district: row.district, count: row.count }))
    .sort((a, b) => b.count - a.count || a.district.localeCompare(b.district));
}

/** Types présents dans au moins une ventilation, pour le sélecteur. */
export function availableTypes(stats: PublicStats): string[] {
  const seen = new Set<string>();
  for (const rows of [stats.totals, stats.by_week, stats.by_lang, stats.by_district]) {
    for (const row of rows) seen.add(row.type);
  }
  return [...seen];
}

/** Lignes par mois pour un type donné (`by_month`), triées. */
export function monthlySeries(stats: PublicStats, type: string): { month: string; count: number }[] {
  return (stats.by_month ?? [])
    .filter((row) => row.type === type)
    .map((row) => ({ month: row.month, count: row.count }))
    .sort((a, b) => a.month.localeCompare(b.month));
}

/** Lignes par région pour un type donné (`by_region`), plus grand d'abord. */
export function regionSeries(stats: PublicStats, type: string): { region: string; count: number }[] {
  return (stats.by_region ?? [])
    .filter((row) => row.type === type)
    .map((row) => ({ region: row.region, count: row.count }))
    .sort((a, b) => b.count - a.count || a.region.localeCompare(b.region));
}

/** Total publié d'un type, `null` si la cellule est masquée ou absente. */
export function totalOf(stats: PublicStats, type: string): number | null {
  return stats.totals.find((row) => row.type === type)?.count ?? null;
}

export type UnderstoodRate =
  | { kind: "rate"; rate: number; understood: number; notUnderstood: number }
  | { kind: "insufficient" };

/** Taux de réponses jugées comprises. Calculé seulement si les deux totaux
 * (`answer_understood` et `answer_not_understood`) sont publiés : si l'un est
 * masqué (sous `min_count`), le taux serait faux, donc on ne calcule rien. */
export function understoodRate(stats: PublicStats): UnderstoodRate {
  const understood = totalOf(stats, "answer_understood");
  const notUnderstood = totalOf(stats, "answer_not_understood");
  if (understood === null || notUnderstood === null || understood + notUnderstood <= 0) return { kind: "insufficient" };
  return { kind: "rate", rate: understood / (understood + notUnderstood), understood, notUnderstood };
}

export type AgentActivityTableRow = { month: string; region: string } & Record<AgentActivityType, number | null>;

/** `agent_activity` regroupé par (mois, région) : une colonne par type,
 * `null` quand la cellule est masquée. Tri par mois puis région. */
export function agentActivityTable(stats: PublicStats): AgentActivityTableRow[] {
  const rows = new Map<string, AgentActivityTableRow>();
  for (const cell of stats.agent_activity ?? []) {
    if (!(AGENT_ACTIVITY_TYPES as readonly string[]).includes(cell.type)) continue;
    const key = `${cell.month}|${cell.region}`;
    let row = rows.get(key);
    if (!row) {
      row = { month: cell.month, region: cell.region, agents_active: null, agent_visits: null, danger_referrals: null, gbv_referrals: null };
      rows.set(key, row);
    }
    row[cell.type] = cell.count;
  }
  return [...rows.values()].sort((a, b) => a.month.localeCompare(b.month) || a.region.localeCompare(b.region));
}

export function formatPublicNote(stats: Pick<PublicStats, "min_count" | "suppressed_cells">): string {
  return `Chiffres agrégés et anonymes ; toute valeur inférieure à ${stats.min_count} est masquée (${stats.suppressed_cells} cellules masquées).`;
}

function dedupe(values: string[]): string[] {
  return [...new Set(values)];
}
