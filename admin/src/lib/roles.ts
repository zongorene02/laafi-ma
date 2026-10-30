import type { Role } from "../api/types.ts";

// Règles d'accès de la console. Le backend reste l'autorité (403) ; ce module
// évite seulement d'afficher des actions vouées à l'échec.

export type Permission =
  | "dashboard" // GET /admin/stats
  | "content" // base de réponses, signes de danger, questions, capsules
  | "validate" // POST .../validate
  | "help_services" // annuaire d'aide (admin)
  | "districts" // districts (admin)
  | "users" // comptes du personnel (admin)
  | "health"; // GET /admin/health

const PERMISSIONS: Record<Role, readonly Permission[]> = {
  admin: ["dashboard", "content", "validate", "help_services", "districts", "users", "health"],
  validator: ["content", "validate"],
  agent: [],
  woman: [],
};

/** Rôles autorisés à se connecter à la console. */
export const CONSOLE_ROLES: readonly Role[] = ["admin", "validator"];

export function canAccessConsole(role: Role | null | undefined): boolean {
  return !!role && CONSOLE_ROLES.includes(role);
}

export function can(role: Role | null | undefined, permission: Permission): boolean {
  if (!role) return false;
  return PERMISSIONS[role]?.includes(permission) ?? false;
}

export function consoleAccessDeniedMessage(role: Role): string {
  if (role === "agent") {
    return "Accès réservé aux validateurs et administrateurs. Les agents de santé communautaires utilisent l'application mobile Laafi Ma.";
  }
  return "Accès réservé aux validateurs et administrateurs de Laafi Ma.";
}

export interface NavItem {
  to: string;
  label: string;
  permission: Permission;
  end?: boolean;
}

export const NAV_ITEMS: readonly NavItem[] = [
  { to: "/", label: "Tableau de bord", permission: "dashboard", end: true },
  { to: "/kb", label: "Base de réponses", permission: "content" },
  { to: "/danger-signs", label: "Signes de danger", permission: "content" },
  { to: "/unanswered", label: "Questions sans réponse", permission: "content" },
  { to: "/capsules", label: "Capsules", permission: "content" },
  { to: "/help-services", label: "Annuaire d'aide", permission: "help_services" },
  { to: "/districts", label: "Districts", permission: "districts" },
  { to: "/users", label: "Utilisateurs", permission: "users" },
  { to: "/services", label: "État des services", permission: "health" },
];

export function navItemsFor(role: Role | null | undefined): NavItem[] {
  return NAV_ITEMS.filter((item) => can(role, item.permission));
}

/** Page d'accueil après connexion : le tableau de bord pour un admin, la base
 * de réponses pour un validateur. */
export function homePathFor(role: Role | null | undefined): string {
  if (can(role, "dashboard")) return "/";
  if (can(role, "content")) return "/kb";
  return "/login";
}

export const ROLE_LABELS: Record<Role, string> = {
  woman: "Utilisatrice",
  agent: "Agent de santé",
  validator: "Validateur·rice",
  admin: "Administrateur·rice",
};
