import type {
  AgentActivityType,
  CapsuleTrack,
  ContentStatus,
  EventType,
  HelpCategory,
  KbTopic,
  Lang,
} from "../api/types.ts";

export const LANGS: readonly Lang[] = ["fr", "mos", "dyu"];

export const LANG_LABELS: Record<Lang, string> = {
  fr: "Français",
  mos: "Mooré",
  dyu: "Dioula",
};

export const STATUS_LABELS: Record<ContentStatus, string> = {
  draft: "Brouillon",
  sourced: "Sourcé, non relu",
  validated: "Validé",
  archived: "Archivé",
};

/** Ordre du circuit de validation, pour les filtres par statut. */
export const CONTENT_STATUSES: readonly ContentStatus[] = ["draft", "sourced", "validated", "archived"];

/** Une modification renvoie ce contenu en brouillon : à confirmer d'abord. */
export function editSendsToDraft(status: ContentStatus | undefined): boolean {
  return status === "sourced" || status === "validated";
}

export const TOPIC_LABELS: Record<KbTopic, string> = {
  grossesse: "Grossesse",
  post_partum: "Post-partum",
  contraception: "Contraception",
  menstruation: "Menstruation",
  nutrition: "Nutrition",
  maladies: "Maladies",
  sante_mentale: "Santé mentale",
  violences: "Violences",
  enfant: "Enfant",
  hygiene: "Hygiène",
  autre: "Autre",
};

export const TRACK_LABELS: Record<CapsuleTrack, string> = {
  adolescente: "Adolescente",
  future_mere: "Future mère",
  jeune_mere: "Jeune mère",
  hommes_familles: "Hommes et familles",
  droits: "Droits",
  bien_etre: "Bien-être",
  general: "Général",
};

export const HELP_CATEGORY_LABELS: Record<HelpCategory, string> = {
  hotline: "Numéro vert / ligne d'écoute",
  vbg_center: "Centre de prise en charge VBG",
  police: "Police",
  gendarmerie: "Gendarmerie",
  emergency: "Urgences (pompiers, SAMU)",
  health: "Santé",
  social: "Action sociale",
  legal: "Aide juridique",
  psychosocial: "Soutien psychosocial",
};

export const EVENT_LABELS: Record<EventType, string> = {
  app_opened: "Ouvertures de l'application",
  question_asked: "Questions posées",
  question_unanswered: "Questions sans réponse",
  danger_flagged: "Signes de danger détectés",
  help_opened: "Ouvertures de l'aide",
  help_call: "Appels vers un service d'aide",
  help_alert_sent: "Alertes envoyées",
  directory_viewed: "Consultations de l'annuaire",
  capsule_played: "Capsules écoutées",
  reminder_done: "Rappels effectués",
  record_backup: "Sauvegardes du carnet",
  monthly_active: "Utilisatrices actives (par mois)",
  question_voice: "Questions vocales",
  answer_understood: "Réponses jugées comprises",
  answer_not_understood: "Réponses jugées non comprises",
  anc_visit_recorded: "Consultations prénatales enregistrées",
  vaccine_recorded: "Vaccins enregistrés",
};

export const AGENT_ACTIVITY_LABELS: Record<AgentActivityType, string> = {
  agents_active: "Agents actifs",
  agent_visits: "Visites des agents",
  danger_referrals: "Orientations pour signe de danger",
  gbv_referrals: "Orientations VBG par les agents",
};

export function eventLabel(type: string): string {
  return (EVENT_LABELS as Record<string, string>)[type] ?? type;
}

export function langLabel(code: string): string {
  return (LANG_LABELS as Record<string, string>)[code] ?? code;
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleDateString("fr-FR");
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" });
}
