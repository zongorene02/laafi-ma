// Périodes de la page publique. Dates locales au format YYYY-MM-DD.

export type PeriodPreset = "default" | "30d" | "90d" | "12m" | "custom";

export function toIsoDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/** Bornes d'une période prédéfinie ; `{}` = période par défaut du backend. */
export function presetRange(preset: PeriodPreset, today: Date = new Date()): { from?: string; to?: string } {
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const start = new Date(end);
  switch (preset) {
    case "30d":
      start.setDate(start.getDate() - 29);
      break;
    case "90d":
      start.setDate(start.getDate() - 89);
      break;
    case "12m":
      start.setFullYear(start.getFullYear() - 1);
      start.setDate(start.getDate() + 1);
      break;
    default:
      return {};
  }
  return { from: toIsoDate(start), to: toIsoDate(end) };
}

export function isValidRange(from: string, to: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(from) && /^\d{4}-\d{2}-\d{2}$/.test(to) && from <= to;
}

/** « 2026-W44 » → « sem. 44 (2026) » */
export function formatIsoWeek(week: string): string {
  const match = /^(\d{4})-W(\d{1,2})$/.exec(week);
  if (!match) return week;
  return `sem. ${Number(match[2])} (${match[1]})`;
}

const MONTHS_FR = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];

/** « 2026-11 » → « nov. 2026 » */
export function formatMonth(month: string): string {
  const match = /^(\d{4})-(\d{2})$/.exec(month);
  const index = match ? Number(match[2]) - 1 : -1;
  if (!match || index < 0 || index > 11) return month;
  return `${MONTHS_FR[index]} ${match[1]}`;
}
