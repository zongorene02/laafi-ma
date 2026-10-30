import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { PublicStats, QuizQuestion } from "../src/api/types.ts";
import { describeHttpError } from "../src/lib/errors.ts";
import {
  buildCapsulePayload,
  buildDangerSignPayload,
  buildKbPayload,
  agentActivityTable,
  dangerSignProblems,
  districtSeries,
  formatPublicNote,
  langSeries,
  missingLangs,
  monthlySeries,
  normalizeDangerTranslations,
  normalizeKbTranslations,
  normalizeKeywords,
  quizProblems,
  regionSeries,
  removeChoice,
  splitKeywordInput,
  understoodRate,
  weeklySeries,
} from "../src/lib/mappers.ts";
import { formatIsoWeek, formatMonth, isValidRange, presetRange } from "../src/lib/period.ts";

const empty = { question: "", variants: [], answer: "" };

describe("base de réponses", () => {
  it("normalise les langues absentes", () => {
    const t = normalizeKbTranslations({ fr: { question: "Q", variants: ["v"], answer: "R", audio_url: null, audio_kind: null, machine_translated: false } });
    assert.equal(t.fr.question, "Q");
    assert.deepEqual(t.mos, { question: "", variants: [], answer: "", audio_url: null, audio_kind: null, machine_translated: false });
    assert.deepEqual(t.dyu.variants, []);
  });

  it("n'envoie que les langues saisies, variantes nettoyées", () => {
    const payload = buildKbPayload({
      topic: "grossesse",
      is_danger_topic: false,
      source: "  ",
      translations: {
        fr: { question: " Q ", variants: ["a", " ", "a", "b "], answer: "R" },
        mos: empty,
        dyu: { question: "", variants: [""], answer: "" },
      },
    });
    assert.deepEqual(payload, {
      topic: "grossesse",
      is_danger_topic: false,
      source: null,
      translations: { fr: { question: "Q", variants: ["a", "b"], answer: "R" } },
    });
  });

  it("détecte les langues manquantes", () => {
    assert.deepEqual(missingLangs({ fr: { question: "Q", answer: "R" }, mos: { question: "Q", answer: "" }, dyu: null }), ["mos", "dyu"]);
  });
});

describe("signes de danger", () => {
  it("mots-clés en minuscules sans doublons", () => {
    assert.deepEqual(normalizeKeywords([" Saigne", "saigne", "", "SANG  frais"]), ["saigne", "sang frais"]);
    assert.deepEqual(splitKeywordInput("saigne, sang;fièvre"), ["saigne", "sang", "fièvre"]);
  });

  const blank = { label: "", advice: "", agent_questions: "", refer_when: "" };

  it("payload sans langues vides, fiche agents toujours présente", () => {
    const payload = buildDangerSignPayload({
      translations: { fr: { ...blank, label: "L", advice: "A" }, mos: blank, dyu: blank },
      keywords_fr: ["Sang"],
      source: "OMS",
    });
    assert.deepEqual(payload, {
      translations: { fr: { label: "L", advice: "A", agent_questions: [], refer_when: null } },
      keywords_fr: ["sang"],
      source: "OMS",
    });
  });

  it("fiche agents : une question par ligne, critère nettoyé", () => {
    const payload = buildDangerSignPayload({
      translations: {
        fr: { label: "L", advice: "A", agent_questions: " Depuis quand ?\r\n\n Combien de linges ? \nDepuis quand ?", refer_when: "  Si plus de 2 linges.  " },
        mos: { ...blank, refer_when: "Mooré" },
        dyu: blank,
      },
      keywords_fr: ["sang"],
      source: "",
    });
    assert.deepEqual(payload.translations.fr, {
      label: "L",
      advice: "A",
      agent_questions: ["Depuis quand ?", "Combien de linges ?"],
      refer_when: "Si plus de 2 linges.",
    });
    assert.deepEqual(payload.translations.mos, { label: "", advice: "", agent_questions: [], refer_when: "Mooré" });
    assert.equal(payload.translations.dyu, undefined);
  });

  it("formulaire depuis le contrat (champs absents tolérés)", () => {
    const t = normalizeDangerTranslations({
      fr: { label: "L", advice: "A", agent_questions: ["Q1", "Q2"], refer_when: null },
    });
    assert.deepEqual(t.fr, { label: "L", advice: "A", agent_questions: "Q1\nQ2", refer_when: "" });
    assert.deepEqual(t.mos, blank);
  });

  it("limites du contrat de la fiche agents", () => {
    const ok = { fr: { ...blank, agent_questions: "a\nb" }, mos: blank, dyu: blank };
    assert.deepEqual(dangerSignProblems(ok), []);
    const tooMany = Array.from({ length: 11 }, (_, i) => `Q${i}`).join("\n");
    const problems = dangerSignProblems({
      fr: { ...blank, agent_questions: tooMany },
      mos: { ...blank, agent_questions: "x".repeat(301) },
      dyu: { ...blank, refer_when: "y".repeat(1001) },
    });
    assert.equal(problems.length, 3);
    assert.match(problems[0], /^Français : 10 questions au maximum/);
    assert.match(problems[1], /^Mooré, question 1/);
    assert.match(problems[2], /^Dioula/);
  });
});

describe("capsules", () => {
  const q: QuizQuestion = { question: { fr: "Q ?", mos: " " }, choices: [{ fr: "a" }, { fr: "b" }, { fr: "c" }], correct_index: 2 };

  it("payload : quiz nettoyé, ordre entier", () => {
    const payload = buildCapsulePayload({
      track: "general",
      order: 2.7,
      translations: { fr: { title: "T", text: "X" }, mos: { title: "", text: "" }, dyu: { title: "", text: "" } },
      quiz: [q],
    });
    assert.equal(payload.order, 2);
    assert.deepEqual(payload.quiz[0].question, { fr: "Q ?" });
    assert.deepEqual(Object.keys(payload.translations), ["fr"]);
  });

  it("retirer un choix garde la bonne réponse cohérente", () => {
    assert.equal(removeChoice(q, 0).correct_index, 1);
    assert.equal(removeChoice(q, 2).correct_index, 0);
    assert.equal(removeChoice(q, 1).choices.length, 2);
  });

  it("problèmes de quiz", () => {
    assert.deepEqual(quizProblems([q]), []);
    assert.equal(quizProblems([{ question: {}, choices: [{ fr: "a" }], correct_index: 3 }]).length, 3);
  });
});

describe("statistiques publiques", () => {
  const stats: PublicStats = {
    generated_at: "2026-10-29T10:00:00Z",
    min_count: 10,
    period: { from: "2026-10-01", to: "2026-10-29" },
    totals: [{ type: "question_asked", count: 120 }],
    by_week: [
      { week: "2026-W44", type: "question_asked", count: 40 },
      { week: "2026-W43", type: "question_asked", count: 30 },
      { week: "2026-W43", type: "app_opened", count: 99 },
    ],
    by_lang: [
      { lang: "dyu", type: "question_asked", count: 20 },
      { lang: "fr", type: "question_asked", count: 50 },
    ],
    by_district: [
      { district: "B", type: "question_asked", count: 12 },
      { district: "A", type: "question_asked", count: 30 },
    ],
    by_month: [
      { month: "2026-10", type: "monthly_active", count: 80 },
      { month: "2026-09", type: "monthly_active", count: 55 },
      { month: "2026-10", type: "danger_flagged", count: 12 },
    ],
    by_region: [
      { region: "Centre", type: "danger_flagged", count: 11 },
      { region: "Hauts-Bassins", type: "danger_flagged", count: 15 },
    ],
    agent_activity: [
      { month: "2026-10", region: "Hauts-Bassins", type: "agent_visits", count: 40 },
      { month: "2026-09", region: "Centre", type: "agents_active", count: 12 },
      { month: "2026-10", region: "Hauts-Bassins", type: "agents_active", count: 14 },
      { month: "2026-10", region: "Centre", type: "gbv_referrals", count: 10 },
    ],
    suppressed_cells: 4,
  };

  const withTotals = (totals: PublicStats["totals"]): PublicStats => ({ ...stats, totals });

  it("séries filtrées et triées", () => {
    assert.deepEqual(weeklySeries(stats, "question_asked").map((r) => r.week), ["2026-W43", "2026-W44"]);
    assert.deepEqual(langSeries(stats, "question_asked").map((r) => r.lang), ["fr", "dyu"]);
    assert.deepEqual(districtSeries(stats, "question_asked").map((r) => r.district), ["A", "B"]);
  });

  it("séries mensuelles et régionales", () => {
    assert.deepEqual(monthlySeries(stats, "monthly_active"), [
      { month: "2026-09", count: 55 },
      { month: "2026-10", count: 80 },
    ]);
    assert.deepEqual(regionSeries(stats, "danger_flagged").map((r) => r.region), ["Hauts-Bassins", "Centre"]);
    assert.deepEqual(monthlySeries({ ...stats, by_month: undefined as unknown as PublicStats["by_month"] }, "x"), []);
    assert.equal(formatMonth("2026-11"), "nov. 2026");
    assert.equal(formatMonth("2026-13"), "2026-13");
  });

  it("taux de réponses comprises : calculé si les deux cellules sont publiées", () => {
    const rate = understoodRate(
      withTotals([
        { type: "answer_understood", count: 30 },
        { type: "answer_not_understood", count: 10 },
      ]),
    );
    assert.deepEqual(rate, { kind: "rate", rate: 0.75, understood: 30, notUnderstood: 10 });
  });

  it("taux de réponses comprises : jamais calculé sur une cellule masquée", () => {
    // « non comprises » masquée (< min_count) : 100 % serait faux.
    assert.deepEqual(understoodRate(withTotals([{ type: "answer_understood", count: 30 }])), { kind: "insufficient" });
    assert.deepEqual(understoodRate(withTotals([{ type: "answer_not_understood", count: 12 }])), { kind: "insufficient" });
    assert.deepEqual(understoodRate(withTotals([])), { kind: "insufficient" });
  });

  it("activité des agents regroupée par mois et région, cellules masquées à null", () => {
    assert.deepEqual(agentActivityTable(stats), [
      { month: "2026-09", region: "Centre", agents_active: 12, agent_visits: null, danger_referrals: null, gbv_referrals: null },
      { month: "2026-10", region: "Centre", agents_active: null, agent_visits: null, danger_referrals: null, gbv_referrals: 10 },
      { month: "2026-10", region: "Hauts-Bassins", agents_active: 14, agent_visits: 40, danger_referrals: null, gbv_referrals: null },
    ]);
    const unknown = { ...stats, agent_activity: [{ month: "2026-10", region: "X", type: "autre", count: 50 }] } as unknown as PublicStats;
    assert.deepEqual(agentActivityTable(unknown), []);
  });

  it("note de confidentialité", () => {
    assert.equal(
      formatPublicNote(stats),
      "Chiffres agrégés et anonymes ; toute valeur inférieure à 10 est masquée (4 cellules masquées).",
    );
  });

  it("périodes", () => {
    assert.deepEqual(presetRange("30d", new Date(2026, 9, 29)), { from: "2026-09-30", to: "2026-10-29" });
    assert.deepEqual(presetRange("default"), {});
    assert.equal(isValidRange("2026-10-01", "2026-09-01"), false);
    assert.equal(formatIsoWeek("2026-W04"), "sem. 4 (2026)");
  });
});

describe("erreurs", () => {
  it("utilise detail en priorité, sinon un message par code", () => {
    assert.equal(describeHttpError(409, "Traduction fr manquante"), "Traduction fr manquante");
    assert.match(describeHttpError(403, undefined), /Accès refusé/);
    assert.match(describeHttpError(422, [{ loc: ["body", "email"], msg: "invalide" }]), /email : invalide/);
    assert.match(describeHttpError(502, null), /502/);
  });
});
