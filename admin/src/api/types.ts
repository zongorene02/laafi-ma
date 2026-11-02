// Types alignés sur docs/API.md (contrat v1). Toute divergence avec le
// contrat doit être corrigée ici, pas contournée dans les pages.

export type Role = "woman" | "agent" | "validator" | "admin";
export type StaffRole = "agent" | "validator" | "admin";
export type Lang = "fr" | "mos" | "dyu";
export type ContentStatus = "draft" | "sourced" | "validated" | "archived";
export type AudioKind = "human" | "synthetic";

export interface CurrentUser {
  id: string;
  role: Role;
  email: string | null;
  full_name: string | null;
  district_id: string | null;
  created_at: string;
}

export interface AdminUser {
  id: string;
  role: StaffRole;
  email: string | null;
  full_name: string | null;
  district_id: string | null;
  created_at: string;
  /** Absent si le backend ne le renvoie pas : traité comme actif. */
  active?: boolean;
}

export interface CreateUserPayload {
  email: string;
  full_name: string;
  role: StaffRole;
  district_id: string | null;
}

export interface UpdateUserPayload {
  role?: StaffRole;
  full_name?: string;
  district_id?: string | null;
  active?: boolean;
}

export interface CreateUserResponse {
  user: AdminUser;
  temporary_password: string;
}

export interface AdminStats {
  women_accounts: number;
  agents: number;
  validators: number;
  kb: { draft: number; sourced: number; validated: number };
  capsules: { draft: number; sourced: number; validated: number };
  unanswered_open: number;
  events_last_30_days: number;
}

/** `GET /admin/health` : champs de `/health` + vérifications DB/disque dont
 * la forme exacte n'est pas fixée par le contrat (affichées génériquement). */
export interface ServicesHealth {
  status?: string;
  translation_model_loaded?: boolean;
  speech_model_loaded?: boolean;
  fast_mode_available?: boolean;
  database?: string;
  [key: string]: unknown;
}

export interface ValidatedBy {
  id: string;
  full_name: string | null;
}

// ---- Base de réponses -------------------------------------------------------

export const KB_TOPICS = [
  "grossesse",
  "post_partum",
  "contraception",
  "menstruation",
  "nutrition",
  "maladies",
  "sante_mentale",
  "violences",
  "enfant",
  "hygiene",
  "autre",
] as const;
export type KbTopic = (typeof KB_TOPICS)[number];

export interface KbTranslation {
  question: string;
  variants: string[];
  answer: string;
  audio_url: string | null;
  audio_kind: AudioKind | null;
  machine_translated: boolean;
}

export interface KbEntry {
  id: string;
  topic: KbTopic;
  status: ContentStatus;
  is_danger_topic: boolean;
  translations: Partial<Record<Lang, KbTranslation | null>>;
  source: string | null;
  validated_by: ValidatedBy | null;
  validated_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface KbTranslationInput {
  question: string;
  variants: string[];
  answer: string;
}

export interface KbEntryPayload {
  topic: KbTopic;
  is_danger_topic: boolean;
  source: string | null;
  translations: Partial<Record<Lang, KbTranslationInput>>;
}

// ---- Signes de danger -------------------------------------------------------

export interface DangerSignTranslation {
  label: string;
  advice: string;
  /** Fiche d'aide à la décision (agents) : questions à poser, ≤ 10 × 300 car. */
  agent_questions: string[];
  /** Quand orienter vers le centre de santé, ≤ 1000 car. */
  refer_when: string | null;
}

export const DANGER_AGENT_QUESTIONS_MAX = 10;
export const DANGER_AGENT_QUESTION_MAX_CHARS = 300;
export const DANGER_REFER_WHEN_MAX_CHARS = 1000;

export interface DangerSign {
  id: string;
  status: ContentStatus;
  translations: Partial<Record<Lang, DangerSignTranslation | null>>;
  keywords_fr: string[];
  source: string | null;
  validated_by: ValidatedBy | null;
  validated_at: string | null;
}

export interface DangerSignPayload {
  translations: Partial<Record<Lang, DangerSignTranslation>>;
  keywords_fr: string[];
  source: string | null;
}

export interface UnansweredQuestion {
  id: string;
  text_fr: string;
  lang: Lang;
  created_at: string;
  resolved: boolean;
}

// ---- Capsules ---------------------------------------------------------------

export const CAPSULE_TRACKS = [
  "adolescente",
  "future_mere",
  "jeune_mere",
  "hommes_familles",
  "droits",
  "bien_etre",
  "general",
] as const;
export type CapsuleTrack = (typeof CAPSULE_TRACKS)[number];

export interface CapsuleTranslation {
  title: string;
  text: string;
  audio_url: string | null;
  audio_kind: AudioKind | null;
}

export type LocalizedText = Partial<Record<Lang, string>>;

export interface QuizQuestion {
  question: LocalizedText;
  choices: LocalizedText[];
  correct_index: number;
}

export interface Capsule {
  id: string;
  track: CapsuleTrack;
  status: ContentStatus;
  order: number;
  translations: Partial<Record<Lang, CapsuleTranslation | null>>;
  quiz: QuizQuestion[];
  license: string;
  /** Vrai seulement pour `sourced` : contenu relu par aucune sage-femme. */
  provisional?: boolean;
  validated_by: ValidatedBy | null;
  validated_at: string | null;
}

export interface CapsulePayload {
  track: CapsuleTrack;
  order: number;
  translations: Partial<Record<Lang, { title: string; text: string }>>;
  quiz: QuizQuestion[];
}

// ---- Annuaire d'aide --------------------------------------------------------

export const HELP_CATEGORIES = [
  "hotline",
  "vbg_center",
  "police",
  "gendarmerie",
  "emergency",
  "health",
  "social",
  "legal",
  "psychosocial",
] as const;
export type HelpCategory = (typeof HELP_CATEGORIES)[number];

export interface HelpService {
  id: string;
  name: string;
  category: HelpCategory;
  phone: string;
  city: string | null;
  region: string | null;
  address: string | null;
  hours: string | null;
  free_call: boolean;
  languages: Lang[];
  source_url: string | null;
  verified_at: string | null;
  active: boolean;
}

export type HelpServicePayload = Omit<HelpService, "id" | "verified_at">;

// ---- Districts --------------------------------------------------------------

export interface District {
  id: string;
  name: string;
  region: string;
}

export type DistrictPayload = Omit<District, "id">;

// ---- Statistiques publiques -------------------------------------------------

export const EVENT_TYPES = [
  "app_opened",
  "question_asked",
  "question_unanswered",
  "danger_flagged",
  "help_opened",
  "help_call",
  "help_alert_sent",
  "directory_viewed",
  "capsule_played",
  "reminder_done",
  "record_backup",
  "monthly_active",
  "question_voice",
  "answer_understood",
  "answer_not_understood",
  "anc_visit_recorded",
  "vaccine_recorded",
] as const;
export type EventType = (typeof EVENT_TYPES)[number];

export interface PublicStats {
  generated_at: string;
  min_count: number;
  period: { from: string; to: string };
  totals: { type: string; count: number }[];
  by_week: { week: string; type: string; count: number }[];
  by_lang: { lang: string; type: string; count: number }[];
  by_district: { district: string; type: string; count: number }[];
  by_month: { month: string; type: string; count: number }[];
  by_region: { region: string; type: string; count: number }[];
  agent_activity: AgentActivityRow[];
  suppressed_cells: number;
}

/** Activité des agents (dossiers agents, aucun événement des femmes),
 * par mois et région du district de l'agent. */
export const AGENT_ACTIVITY_TYPES = ["agents_active", "agent_visits", "danger_referrals", "gbv_referrals"] as const;
export type AgentActivityType = (typeof AGENT_ACTIVITY_TYPES)[number];

export interface AgentActivityRow {
  month: string;
  region: string;
  type: AgentActivityType;
  count: number;
}
