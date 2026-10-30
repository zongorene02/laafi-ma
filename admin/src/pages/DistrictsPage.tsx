import { useState, type FormEvent } from "react";
import { apiErrorMessage } from "../api/client";
import { createDistrict, deleteDistrict, listDistricts, updateDistrict } from "../api/districts";
import type { District } from "../api/types";
import { Alert, EmptyState, Loading, PageHeader } from "../components/ui";
import { useAsync } from "../lib/useAsync";
import { btnDanger, btnPrimary, btnSecondary, cardClass, inputClass, labelClass } from "../lib/styles";

export default function DistrictsPage() {
  const { data, error: loadError, isLoading, mutate } = useAsync(listDistricts, "districts");
  const districts: District[] = data ?? [];
  const [error, setError] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [region, setRegion] = useState("");
  const [busy, setBusy] = useState(false);

  function resetForm() {
    setEditingId(null);
    setName("");
    setRegion("");
  }

  function startEdit(district: District) {
    setEditingId(district.id);
    setName(district.name);
    setRegion(district.region);
    setError(null);
  }

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    const payload = { name: name.trim(), region: region.trim() };
    if (!payload.name || !payload.region) {
      setError("Le nom du district et sa région sont obligatoires.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      if (editingId) {
        const updated = await updateDistrict(editingId, payload);
        mutate((prev) => (prev ?? []).map((d) => (d.id === updated.id ? updated : d)));
      } else {
        const created = await createDistrict(payload);
        mutate((prev) => [...(prev ?? []), created]);
      }
      resetForm();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  async function handleDelete(district: District) {
    if (!confirm(`Supprimer le district « ${district.name} » ? Les comptes rattachés n'auront plus de district.`)) return;
    setBusy(true);
    setError(null);
    try {
      await deleteDistrict(district.id);
      mutate((prev) => (prev ?? []).filter((d) => d.id !== district.id));
      if (editingId === district.id) resetForm();
    } catch (err) {
      setError(apiErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }

  const sorted = [...districts].sort((a, b) => a.region.localeCompare(b.region, "fr") || a.name.localeCompare(b.name, "fr"));

  return (
    <div className="space-y-6">
      <PageHeader
        title="Districts sanitaires"
        description="Utilisés pour rattacher les agents et ventiler les statistiques publiques. Aucun district n'est pré-rempli."
      />

      <form onSubmit={handleSubmit} className={`${cardClass} grid grid-cols-1 gap-4 sm:grid-cols-[1fr_1fr_auto]`} aria-label="Ajout ou modification de district">
        <div>
          <label htmlFor="d-name" className={labelClass}>Nom du district</label>
          <input id="d-name" value={name} onChange={(e) => setName(e.target.value)} required className={inputClass} />
        </div>
        <div>
          <label htmlFor="d-region" className={labelClass}>Région</label>
          <input id="d-region" value={region} onChange={(e) => setRegion(e.target.value)} required className={inputClass} />
        </div>
        <div className="flex items-end gap-2">
          <button type="submit" disabled={busy} className={btnPrimary}>
            {editingId ? "Enregistrer" : "Ajouter"}
          </button>
          {editingId && (
            <button type="button" onClick={resetForm} className={btnSecondary}>
              Annuler
            </button>
          )}
        </div>
      </form>

      {loadError && <Alert>{loadError}</Alert>}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}

      {isLoading ? (
        <Loading />
      ) : sorted.length === 0 && !loadError ? (
        <EmptyState title="Aucun district enregistré.">
          La liste officielle des districts sanitaires doit être saisie à partir de la source du ministère de la Santé
          (découpage sanitaire en vigueur). N'ajoutez aucun district qui ne figure pas dans cette source.
        </EmptyState>
      ) : (
        <div className="overflow-x-auto rounded-2xl bg-white shadow-sm">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">Liste des districts</caption>
            <thead className="border-b border-gray-100 text-gray-600">
              <tr>
                <th scope="col" className="px-4 py-3 font-medium">District</th>
                <th scope="col" className="px-4 py-3 font-medium">Région</th>
                <th scope="col" className="px-4 py-3 font-medium"><span className="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              {sorted.map((d) => (
                <tr key={d.id} className="border-b border-gray-50 last:border-0">
                  <td className="px-4 py-3 font-medium text-gray-900">{d.name}</td>
                  <td className="px-4 py-3 text-gray-700">{d.region}</td>
                  <td className="px-4 py-3">
                    <div className="flex justify-end gap-2">
                      <button type="button" onClick={() => startEdit(d)} className={btnSecondary}>Modifier</button>
                      <button type="button" onClick={() => handleDelete(d)} disabled={busy} className={btnDanger}>Supprimer</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
