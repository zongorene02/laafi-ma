import { useRef, useState, type FormEvent } from "react";
import { apiErrorMessage } from "../api/client";
import { createHelpService, deleteHelpService, listHelpServices, updateHelpService, verifyHelpService } from "../api/help";
import { HELP_CATEGORIES, type HelpCategory, type HelpService, type HelpServicePayload, type Lang } from "../api/types";
import { Alert, Badge, EmptyState, Loading, PageHeader } from "../components/ui";
import { formatDate, HELP_CATEGORY_LABELS, LANG_LABELS, LANGS } from "../lib/labels";
import { useAsync } from "../lib/useAsync";
import { btnDanger, btnPrimary, btnSecondary, btnSuccess, cardClass, inputClass, labelClass } from "../lib/styles";

interface ServiceForm {
  name: string;
  category: HelpCategory;
  phone: string;
  city: string;
  region: string;
  address: string;
  hours: string;
  free_call: boolean;
  languages: Lang[];
  source_url: string;
  active: boolean;
}

function emptyForm(): ServiceForm {
  return {
    name: "",
    category: "hotline",
    phone: "",
    city: "",
    region: "",
    address: "",
    hours: "",
    free_call: false,
    languages: ["fr"],
    source_url: "",
    active: true,
  };
}

function formFrom(service: HelpService): ServiceForm {
  return {
    name: service.name,
    category: service.category,
    phone: service.phone,
    city: service.city ?? "",
    region: service.region ?? "",
    address: service.address ?? "",
    hours: service.hours ?? "",
    free_call: service.free_call,
    languages: [...(service.languages ?? [])],
    source_url: service.source_url ?? "",
    active: service.active,
  };
}

function toPayload(form: ServiceForm): HelpServicePayload {
  const orNull = (value: string) => value.trim() || null;
  return {
    name: form.name.trim(),
    category: form.category,
    phone: form.phone.trim(),
    city: orNull(form.city),
    region: orNull(form.region),
    address: orNull(form.address),
    hours: orNull(form.hours),
    free_call: form.free_call,
    languages: LANGS.filter((l) => form.languages.includes(l)),
    source_url: orNull(form.source_url),
    active: form.active,
  };
}

export default function HelpServicesPage() {
  const { data, error: loadError, isLoading, mutate } = useAsync(listHelpServices, "help-services");
  const services: HelpService[] = data ?? [];
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<HelpService | "new" | null>(null);
  const [form, setForm] = useState<ServiceForm>(emptyForm);
  const [busy, setBusy] = useState<string | null>(null);
  const formRef = useRef<HTMLFormElement>(null);

  function openEditor(target: HelpService | "new") {
    setEditing(target);
    setForm(target === "new" ? emptyForm() : formFrom(target));
    setError(null);
    setNotice(null);
    requestAnimationFrame(() => formRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }));
  }

  function replace(updated: HelpService) {
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
    const payload = toPayload(form);
    if (!payload.name || !payload.phone) {
      setError("Le nom et le numéro de téléphone sont obligatoires.");
      return;
    }
    await run("save", async () => {
      const saved = editing === "new" || !editing ? await createHelpService(payload) : await updateHelpService(editing.id, payload);
      replace(saved);
      setEditing(null);
      setNotice(
        saved.verified_at
          ? "Service enregistré."
          : "Service enregistré. Il reste « non confirmé » tant que le numéro n'a pas été vérifié.",
      );
    });
  }

  async function handleVerify(service: HelpService) {
    if (!confirm(`Confirmez-vous avoir vérifié aujourd'hui le numéro ${service.phone} de « ${service.name} » (appel ou source officielle à jour) ?`)) {
      return;
    }
    await run(`verify-${service.id}`, async () => {
      replace(await verifyHelpService(service.id));
      setNotice("Service marqué comme vérifié aujourd'hui.");
    });
  }

  async function handleDelete(service: HelpService) {
    if (!confirm(`Supprimer définitivement « ${service.name} » de l'annuaire ?`)) return;
    await run(`delete-${service.id}`, async () => {
      await deleteHelpService(service.id);
      mutate((prev) => (prev ?? []).filter((s) => s.id !== service.id));
      if (editing !== "new" && editing?.id === service.id) setEditing(null);
    });
  }

  function field(key: keyof ServiceForm, label: string, opts: { type?: string; placeholder?: string; required?: boolean } = {}) {
    const id = `hs-${key}`;
    return (
      <div>
        <label htmlFor={id} className={labelClass}>
          {label}
          {opts.required && <span className="text-red-700"> *</span>}
        </label>
        <input
          id={id}
          type={opts.type ?? "text"}
          required={opts.required}
          placeholder={opts.placeholder}
          value={form[key] as string}
          onChange={(e) => setForm((f) => ({ ...f, [key]: e.target.value }))}
          className={inputClass}
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Annuaire d'aide"
        description="Numéros et services d'aide (VBG, santé, police…) affichés dans l'application. Chaque numéro doit provenir d'une source officielle et être vérifié avant d'être présenté comme confirmé."
        actions={
          <button type="button" onClick={() => openEditor("new")} className={btnPrimary}>
            Nouveau service
          </button>
        }
      />

      {loadError && <Alert>{loadError}</Alert>}
      {error && <Alert onClose={() => setError(null)}>{error}</Alert>}
      {notice && <Alert kind="success" onClose={() => setNotice(null)}>{notice}</Alert>}

      {editing && (
        <form ref={formRef} onSubmit={handleSave} className={`${cardClass} space-y-4`} aria-label="Éditeur de service d'aide">
          <h2 className="text-lg font-semibold text-gray-900">{editing === "new" ? "Nouveau service" : `Modifier « ${editing.name} »`}</h2>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            {field("name", "Nom", { required: true })}
            <div>
              <label htmlFor="hs-category" className={labelClass}>Catégorie</label>
              <select
                id="hs-category"
                value={form.category}
                onChange={(e) => setForm((f) => ({ ...f, category: e.target.value as HelpCategory }))}
                className={inputClass}
              >
                {HELP_CATEGORIES.map((c) => (
                  <option key={c} value={c}>{HELP_CATEGORY_LABELS[c]}</option>
                ))}
              </select>
            </div>
            {field("phone", "Téléphone", { type: "tel", required: true })}
            {field("hours", "Horaires", { placeholder: "Ex. : 24 h/24, 7 j/7" })}
            {field("city", "Ville")}
            {field("region", "Région")}
            <div className="md:col-span-2">{field("address", "Adresse")}</div>
            <div className="md:col-span-2">{field("source_url", "Source (lien officiel)", { type: "url", placeholder: "https://…" })}</div>
          </div>
          <fieldset>
            <legend className={labelClass}>Langues parlées</legend>
            <div className="mt-1 flex flex-wrap gap-4">
              {LANGS.map((lang) => (
                <label key={lang} className="flex items-center gap-2 text-sm text-gray-800">
                  <input
                    type="checkbox"
                    checked={form.languages.includes(lang)}
                    onChange={(e) =>
                      setForm((f) => ({
                        ...f,
                        languages: e.target.checked ? [...f.languages, lang] : f.languages.filter((l) => l !== lang),
                      }))
                    }
                    className="h-4 w-4 accent-brand-600"
                  />
                  {LANG_LABELS[lang]}
                </label>
              ))}
            </div>
          </fieldset>
          <div className="flex flex-wrap gap-6">
            <label className="flex items-center gap-2 text-sm text-gray-800">
              <input
                type="checkbox"
                checked={form.free_call}
                onChange={(e) => setForm((f) => ({ ...f, free_call: e.target.checked }))}
                className="h-4 w-4 accent-brand-600"
              />
              Appel gratuit
            </label>
            <label className="flex items-center gap-2 text-sm text-gray-800">
              <input
                type="checkbox"
                checked={form.active}
                onChange={(e) => setForm((f) => ({ ...f, active: e.target.checked }))}
                className="h-4 w-4 accent-brand-600"
              />
              Actif (affiché dans l'application)
            </label>
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
      ) : services.length === 0 && !loadError ? (
        <EmptyState title="L'annuaire est vide.">
          Ajoutez les services d'aide à partir de sources officielles (ministère, ONG, forces de sécurité), avec le lien
          de la source, puis vérifiez chaque numéro.
        </EmptyState>
      ) : (
        <ul className="grid grid-cols-1 gap-3 lg:grid-cols-2">
          {services.map((service) => (
            <li key={service.id} className={`${cardClass} flex flex-col gap-2`}>
              <div className="flex flex-wrap items-center gap-2">
                <Badge>{HELP_CATEGORY_LABELS[service.category] ?? service.category}</Badge>
                {service.verified_at ? (
                  <Badge tone="green">Vérifié le {formatDate(service.verified_at)}</Badge>
                ) : (
                  <Badge tone="amber" title="Numéro pas encore vérifié : l'application l'affiche comme non confirmé">
                    Non confirmé
                  </Badge>
                )}
                {service.free_call && <Badge tone="blue">Appel gratuit</Badge>}
                {!service.active && <Badge tone="gray">Inactif</Badge>}
              </div>
              <p className="font-semibold text-gray-900">{service.name}</p>
              <p className="text-lg font-semibold text-gray-900 tabular-nums">
                <a href={`tel:${service.phone.replace(/\s+/g, "")}`} className="hover:underline">{service.phone}</a>
              </p>
              <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-0.5 text-sm text-gray-700">
                {(service.city || service.region) && (
                  <>
                    <dt className="text-gray-500">Lieu</dt>
                    <dd>{[service.city, service.region].filter(Boolean).join(", ")}</dd>
                  </>
                )}
                {service.address && (
                  <>
                    <dt className="text-gray-500">Adresse</dt>
                    <dd>{service.address}</dd>
                  </>
                )}
                {service.hours && (
                  <>
                    <dt className="text-gray-500">Horaires</dt>
                    <dd>{service.hours}</dd>
                  </>
                )}
                {service.languages?.length > 0 && (
                  <>
                    <dt className="text-gray-500">Langues</dt>
                    <dd>{service.languages.map((l) => LANG_LABELS[l] ?? l).join(", ")}</dd>
                  </>
                )}
                <dt className="text-gray-500">Source</dt>
                <dd className="min-w-0 break-all">
                  {service.source_url ? (
                    <a href={service.source_url} target="_blank" rel="noreferrer" className="text-brand-700 hover:underline">
                      {service.source_url}
                    </a>
                  ) : (
                    <span className="text-amber-800">Aucune source renseignée</span>
                  )}
                </dd>
              </dl>
              <div className="mt-auto flex flex-wrap gap-2 pt-2">
                <button type="button" onClick={() => openEditor(service)} className={btnSecondary}>
                  Modifier
                </button>
                <button type="button" onClick={() => handleVerify(service)} disabled={busy !== null} className={btnSuccess}>
                  Marquer comme vérifié
                </button>
                <button type="button" onClick={() => handleDelete(service)} disabled={busy !== null} className={btnDanger}>
                  Supprimer
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
