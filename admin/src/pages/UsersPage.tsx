import { useState, type FormEvent } from "react";
import { createUser, deleteUser, listUsers, resetUserPassword, updateUser } from "../api/admin";
import { apiErrorMessage } from "../api/client";
import { listDistricts } from "../api/districts";
import type { AdminUser, District, StaffRole, UpdateUserPayload } from "../api/types";
import { Alert, Badge, EmptyState, Loading, OneTimeSecret, PageHeader } from "../components/ui";
import { useAuth } from "../context/AuthContext";
import { formatDate } from "../lib/labels";
import { ROLE_LABELS } from "../lib/roles";
import { useAsync } from "../lib/useAsync";
import { btnDanger, btnPrimary, btnSecondary, cardClass, inputClass, labelClass } from "../lib/styles";

const STAFF_ROLES: StaffRole[] = ["agent", "validator", "admin"];

export default function UsersPage() {
  const { user: me } = useAuth();
  const [roleFilter, setRoleFilter] = useState<StaffRole | "">("");
  const { data, error: loadError, isLoading, mutate } = useAsync(() => listUsers(roleFilter), roleFilter);
  const users: AdminUser[] = data ?? [];
  // La liste des districts n'est qu'une aide à la saisie : son échec ne bloque pas la page.
  const districts: District[] = useAsync(listDistricts, "districts").data ?? [];
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [secret, setSecret] = useState<{ title: string; value: string } | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [newUser, setNewUser] = useState({ email: "", full_name: "", role: "agent" as StaffRole, district_id: "" });

  const districtName = (id: string | null) => districts.find((d) => d.id === id)?.name ?? null;

  async function handleCreate(event: FormEvent) {
    event.preventDefault();
    setBusyId("create");
    setError(null);
    setNotice(null);
    try {
      const result = await createUser({
        email: newUser.email.trim(),
        full_name: newUser.full_name.trim(),
        role: newUser.role,
        district_id: newUser.district_id || null,
      });
      if (!roleFilter || roleFilter === result.user.role) mutate((prev) => [result.user, ...(prev ?? [])]);
      setSecret({ title: `Compte créé pour ${result.user.email ?? newUser.email}`, value: result.temporary_password });
      setNewUser({ email: "", full_name: "", role: "agent", district_id: "" });
      setShowCreate(false);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusyId(null);
    }
  }

  async function patch(target: AdminUser, payload: UpdateUserPayload, confirmMessage?: string) {
    if (confirmMessage && !confirm(confirmMessage)) return;
    setBusyId(target.id);
    setError(null);
    setNotice(null);
    try {
      const updated = await updateUser(target.id, payload);
      mutate((prev) => (prev ?? []).map((u) => (u.id === updated.id ? { ...u, ...updated } : u)));
      setNotice(`Compte ${updated.email ?? ""} mis à jour.`);
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusyId(null);
    }
  }

  async function handleReset(target: AdminUser) {
    if (!confirm(`Réinitialiser le mot de passe de ${target.email} ? L'ancien mot de passe ne fonctionnera plus.`)) return;
    setBusyId(target.id);
    setError(null);
    setNotice(null);
    try {
      const password = await resetUserPassword(target.id);
      setSecret({ title: `Nouveau mot de passe temporaire pour ${target.email}`, value: password });
      window.scrollTo({ top: 0, behavior: "smooth" });
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusyId(null);
    }
  }

  async function handleDelete(target: AdminUser) {
    const extra = target.role === "agent" ? " Ses bénéficiaires et visites enregistrés seront également supprimés." : "";
    if (!confirm(`Supprimer définitivement le compte ${target.email} ?${extra}`)) return;
    setBusyId(target.id);
    setError(null);
    setNotice(null);
    try {
      await deleteUser(target.id);
      mutate((prev) => (prev ?? []).filter((u) => u.id !== target.id));
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Utilisateurs"
        description="Comptes du personnel : agents de santé communautaires, validateurs (sages-femmes, médecins) et administrateurs. Les comptes des utilisatrices sont anonymes et ne sont jamais listés."
        actions={
          <button type="button" onClick={() => setShowCreate((v) => !v)} className={btnPrimary} aria-expanded={showCreate}>
            {showCreate ? "Fermer" : "Nouveau compte"}
          </button>
        }
      />

      {secret && <OneTimeSecret title={secret.title} secret={secret.value} onDismiss={() => setSecret(null)} />}
      {loadError && <Alert>{loadError}</Alert>}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}
      {notice && <Alert kind="success" onClose={() => setNotice(null)}>{notice}</Alert>}

      {showCreate && (
        <form onSubmit={handleCreate} className={`${cardClass} grid grid-cols-1 gap-4 md:grid-cols-2`} aria-label="Création de compte">
          <div>
            <label htmlFor="u-email" className={labelClass}>Adresse e-mail</label>
            <input
              id="u-email"
              type="email"
              required
              value={newUser.email}
              onChange={(e) => setNewUser((u) => ({ ...u, email: e.target.value }))}
              className={inputClass}
            />
          </div>
          <div>
            <label htmlFor="u-name" className={labelClass}>Nom complet</label>
            <input
              id="u-name"
              required
              value={newUser.full_name}
              onChange={(e) => setNewUser((u) => ({ ...u, full_name: e.target.value }))}
              className={inputClass}
            />
          </div>
          <div>
            <label htmlFor="u-role" className={labelClass}>Rôle</label>
            <select
              id="u-role"
              value={newUser.role}
              onChange={(e) => setNewUser((u) => ({ ...u, role: e.target.value as StaffRole }))}
              className={inputClass}
            >
              {STAFF_ROLES.map((r) => (
                <option key={r} value={r}>{ROLE_LABELS[r]}</option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="u-district" className={labelClass}>District</label>
            <select
              id="u-district"
              value={newUser.district_id}
              onChange={(e) => setNewUser((u) => ({ ...u, district_id: e.target.value }))}
              className={inputClass}
            >
              <option value="">Aucun</option>
              {districts.map((d) => (
                <option key={d.id} value={d.id}>{d.name} ({d.region})</option>
              ))}
            </select>
            {districts.length === 0 && (
              <p className="mt-1 text-xs text-gray-500">Aucun district enregistré (page Districts).</p>
            )}
          </div>
          <div className="md:col-span-2">
            <p className="mb-3 text-xs text-gray-600">
              Un mot de passe temporaire sera généré et affiché une seule fois après la création.
            </p>
            <button type="submit" disabled={busyId === "create"} className={btnPrimary}>
              {busyId === "create" ? "Création…" : "Créer le compte"}
            </button>
          </div>
        </form>
      )}

      <div className="max-w-xs">
        <label htmlFor="u-filter" className={labelClass}>Filtrer par rôle</label>
        <select id="u-filter" value={roleFilter} onChange={(e) => setRoleFilter(e.target.value as StaffRole | "")} className={inputClass}>
          <option value="">Tous les rôles</option>
          {STAFF_ROLES.map((r) => (
            <option key={r} value={r}>{ROLE_LABELS[r]}</option>
          ))}
        </select>
      </div>

      {isLoading ? (
        <Loading />
      ) : users.length === 0 && !loadError ? (
        <EmptyState title={roleFilter ? "Aucun compte avec ce rôle." : "Aucun compte du personnel."} />
      ) : (
        <ul className="space-y-3">
          {users.map((u) => {
            const isSelf = u.id === me?.id;
            const isBusy = busyId === u.id;
            const active = u.active !== false;
            return (
              <li key={u.id} className={`${cardClass} space-y-3`}>
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-semibold break-all text-gray-900">{u.email ?? "—"}</p>
                  {u.full_name && <span className="text-sm text-gray-600">{u.full_name}</span>}
                  {!active && <Badge tone="gray">Désactivé</Badge>}
                  {isSelf && <Badge tone="brand">Votre compte</Badge>}
                </div>
                <p className="text-xs text-gray-500">
                  Créé le {formatDate(u.created_at)}
                  {u.district_id && ` · District : ${districtName(u.district_id) ?? "inconnu"}`}
                </p>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-[12rem_16rem_1fr]">
                  <div>
                    <label htmlFor={`role-${u.id}`} className="text-xs font-medium text-gray-600">Rôle</label>
                    <select
                      id={`role-${u.id}`}
                      value={u.role}
                      disabled={isSelf || isBusy}
                      onChange={(e) => {
                        const role = e.target.value as StaffRole;
                        patch(
                          u,
                          { role },
                          role === "admin"
                            ? `Donner les droits administrateur à ${u.email} ? Cette personne pourra gérer tous les comptes et contenus.`
                            : `Changer le rôle de ${u.email} en « ${ROLE_LABELS[role]} » ?`,
                        );
                      }}
                      className={inputClass}
                    >
                      {STAFF_ROLES.map((r) => (
                        <option key={r} value={r}>{ROLE_LABELS[r]}</option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label htmlFor={`district-${u.id}`} className="text-xs font-medium text-gray-600">District</label>
                    <select
                      id={`district-${u.id}`}
                      value={u.district_id ?? ""}
                      disabled={isBusy}
                      onChange={(e) => patch(u, { district_id: e.target.value || null })}
                      className={inputClass}
                    >
                      <option value="">Aucun</option>
                      {u.district_id && !districts.some((d) => d.id === u.district_id) && (
                        <option value={u.district_id}>District actuel (inconnu)</option>
                      )}
                      {districts.map((d) => (
                        <option key={d.id} value={d.id}>{d.name}</option>
                      ))}
                    </select>
                  </div>
                  <div className="flex flex-wrap items-end gap-2">
                    {!isSelf && (
                      <button
                        type="button"
                        disabled={isBusy}
                        onClick={() =>
                          patch(
                            u,
                            { active: !active },
                            active ? `Désactiver le compte ${u.email} ? Il ne pourra plus se connecter.` : undefined,
                          )
                        }
                        className={btnSecondary}
                      >
                        {active ? "Désactiver" : "Réactiver"}
                      </button>
                    )}
                    <button type="button" disabled={isBusy} onClick={() => handleReset(u)} className={btnSecondary}>
                      Réinitialiser le mot de passe
                    </button>
                    {!isSelf && (
                      <button type="button" disabled={isBusy} onClick={() => handleDelete(u)} className={btnDanger}>
                        Supprimer
                      </button>
                    )}
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
