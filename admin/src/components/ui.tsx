import { useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { mediaUrl } from "../api/client";
import type { AudioKind, ContentStatus, Lang } from "../api/types";
import { LANG_LABELS, LANGS, STATUS_LABELS } from "../lib/labels";
import { splitKeywordInput } from "../lib/mappers";
import { btnSecondary, inputClass } from "../lib/styles";

export function Alert({
  kind = "error",
  children,
  onClose,
}: {
  kind?: "error" | "success" | "warning" | "info";
  children: ReactNode;
  onClose?: () => void;
}) {
  const styles = {
    error: "border-red-200 bg-red-50 text-red-800",
    success: "border-green-200 bg-green-50 text-green-800",
    warning: "border-amber-300 bg-amber-50 text-amber-900",
    info: "border-sky-200 bg-sky-50 text-sky-900",
  }[kind];
  return (
    <div
      role={kind === "error" ? "alert" : "status"}
      className={`flex items-start justify-between gap-3 rounded-lg border px-4 py-3 text-sm ${styles}`}
    >
      <div className="min-w-0">{children}</div>
      {onClose && (
        <button type="button" onClick={onClose} className="shrink-0 font-semibold opacity-70 hover:opacity-100">
          <span aria-hidden="true">×</span>
          <span className="sr-only">Fermer le message</span>
        </button>
      )}
    </div>
  );
}

export function Badge({ tone = "gray", children, title }: { tone?: BadgeTone; children: ReactNode; title?: string }) {
  const styles: Record<BadgeTone, string> = {
    gray: "bg-gray-100 text-gray-700",
    green: "bg-green-100 text-green-800",
    amber: "bg-amber-100 text-amber-900",
    red: "bg-red-100 text-red-800",
    blue: "bg-sky-100 text-sky-900",
    brand: "bg-brand-100 text-brand-700",
    violet: "bg-violet-100 text-violet-800",
  };
  return (
    <span
      title={title}
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap ${styles[tone]}`}
    >
      {children}
    </span>
  );
}

type BadgeTone = "gray" | "green" | "amber" | "red" | "blue" | "brand" | "violet";

export function StatusBadge({ status }: { status: ContentStatus }) {
  const tones: Record<ContentStatus, BadgeTone> = { draft: "amber", sourced: "violet", validated: "green", archived: "gray" };
  const tone = tones[status] ?? "gray";
  return <Badge tone={tone}>{STATUS_LABELS[status] ?? status}</Badge>;
}

export function MachineTranslatedBadge() {
  return (
    <Badge tone="violet" title="Texte produit par traduction automatique : à relire par une personne qui parle la langue">
      Traduction automatique — à relire
    </Badge>
  );
}

export function AudioKindBadge({ kind }: { kind: AudioKind | null }) {
  if (kind === "human") return <Badge tone="green">Voix humaine</Badge>;
  if (kind === "synthetic") return <Badge tone="blue">Voix de synthèse</Badge>;
  return null;
}

export function PageHeader({ title, description, actions }: { title: string; description?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
        {description && <p className="mt-1 max-w-3xl text-sm text-gray-600">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="rounded-2xl border border-dashed border-gray-300 bg-white px-6 py-10 text-center">
      <p className="font-semibold text-gray-800">{title}</p>
      {children && <div className="mx-auto mt-2 max-w-xl text-sm text-gray-600">{children}</div>}
    </div>
  );
}

export function Loading({ label = "Chargement…" }: { label?: string }) {
  return (
    <p role="status" className="py-6 text-center text-sm text-gray-500">
      {label}
    </p>
  );
}

/** Onglets de langue fr / mos / dyu (motif ARIA tabs). */
export function LangTabs({
  value,
  onChange,
  marks,
  idPrefix,
}: {
  value: Lang;
  onChange: (lang: Lang) => void;
  /** Indication à droite du nom de la langue (ex. « vide »). */
  marks?: Partial<Record<Lang, string>>;
  idPrefix: string;
}) {
  function handleKey(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    const next = (index + (event.key === "ArrowRight" ? 1 : LANGS.length - 1)) % LANGS.length;
    onChange(LANGS[next]);
    document.getElementById(`${idPrefix}-tab-${LANGS[next]}`)?.focus();
  }
  return (
    <div role="tablist" aria-label="Langue" className="flex flex-wrap gap-1 border-b border-gray-200">
      {LANGS.map((lang, index) => {
        const selected = lang === value;
        return (
          <button
            key={lang}
            id={`${idPrefix}-tab-${lang}`}
            type="button"
            role="tab"
            aria-selected={selected}
            aria-controls={`${idPrefix}-panel`}
            tabIndex={selected ? 0 : -1}
            onClick={() => onChange(lang)}
            onKeyDown={(e) => handleKey(e, index)}
            className={`-mb-px rounded-t-lg border-b-2 px-4 py-2 text-sm font-medium ${
              selected ? "border-brand-600 text-brand-700" : "border-transparent text-gray-600 hover:text-gray-900"
            }`}
          >
            {LANG_LABELS[lang]}
            {marks?.[lang] && <span className="ml-1.5 text-xs font-normal text-gray-500">({marks[lang]})</span>}
          </button>
        );
      })}
    </div>
  );
}

/** Saisie de mots-clés sous forme de pastilles (Entrée ou virgule pour ajouter). */
export function ChipsInput({
  label,
  values,
  onChange,
  placeholder,
  help,
}: {
  label: string;
  values: string[];
  onChange: (values: string[]) => void;
  placeholder?: string;
  help?: string;
}) {
  const [draft, setDraft] = useState("");
  const inputId = useId();
  const helpId = useId();

  function commit(raw: string) {
    const parts = splitKeywordInput(raw).map((p) => p.toLowerCase());
    if (parts.length === 0) return;
    const next = [...values];
    for (const part of parts) if (!next.includes(part)) next.push(part);
    onChange(next);
    setDraft("");
  }

  return (
    <div>
      <label htmlFor={inputId} className="block text-sm font-medium text-gray-700">
        {label}
      </label>
      <div className="mt-1 flex flex-wrap items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-2 py-1.5 focus-within:border-brand-500">
        {values.map((value) => (
          <span key={value} className="inline-flex items-center gap-1 rounded-full bg-brand-50 px-2.5 py-0.5 text-sm text-brand-700">
            {value}
            <button
              type="button"
              onClick={() => onChange(values.filter((v) => v !== value))}
              className="font-bold text-brand-700/70 hover:text-brand-700"
              aria-label={`Retirer le mot-clé ${value}`}
            >
              ×
            </button>
          </span>
        ))}
        <input
          id={inputId}
          value={draft}
          aria-describedby={help ? helpId : undefined}
          onChange={(e) => {
            const value = e.target.value;
            if (/[,;]/.test(value)) commit(value);
            else setDraft(value);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              e.preventDefault();
              commit(draft);
            } else if (e.key === "Backspace" && draft === "" && values.length > 0) {
              onChange(values.slice(0, -1));
            }
          }}
          onBlur={() => commit(draft)}
          placeholder={placeholder}
          className="min-w-[8rem] flex-1 border-0 bg-transparent px-1 py-1 text-sm focus:outline-none"
        />
      </div>
      {help && (
        <p id={helpId} className="mt-1 text-xs text-gray-500">
          {help}
        </p>
      )}
    </div>
  );
}

/** Liste de champs texte (ex. variantes de formulation d'une question). */
export function StringListEditor({
  label,
  values,
  onChange,
  addLabel,
  itemLabel,
}: {
  label: string;
  values: string[];
  onChange: (values: string[]) => void;
  addLabel: string;
  itemLabel: (index: number) => string;
}) {
  return (
    <fieldset>
      <legend className="text-sm font-medium text-gray-700">{label}</legend>
      <div className="mt-1 space-y-2">
        {values.length === 0 && <p className="text-xs text-gray-500">Aucune variante pour le moment.</p>}
        {values.map((value, index) => (
          <div key={index} className="flex gap-2">
            <input
              aria-label={itemLabel(index)}
              value={value}
              onChange={(e) => onChange(values.map((v, i) => (i === index ? e.target.value : v)))}
              className={`${inputClass} mt-0`}
            />
            <button
              type="button"
              onClick={() => onChange(values.filter((_, i) => i !== index))}
              className="shrink-0 rounded-lg border border-gray-300 px-3 text-sm text-gray-600 hover:bg-gray-50"
              aria-label={`Supprimer : ${itemLabel(index)}`}
            >
              Retirer
            </button>
          </div>
        ))}
      </div>
      <button type="button" onClick={() => onChange([...values, ""])} className="mt-2 text-sm font-medium text-brand-700 hover:underline">
        + {addLabel}
      </button>
    </fieldset>
  );
}

/** Lecteur + envoi d'un enregistrement audio pour une langue. */
export function AudioPanel({
  lang,
  audioUrl,
  audioKind,
  disabledReason,
  onUpload,
}: {
  lang: Lang;
  audioUrl: string | null;
  audioKind: AudioKind | null;
  /** Si renseigné, l'envoi est impossible (ex. contenu pas encore enregistré). */
  disabledReason?: string;
  onUpload: (file: File) => Promise<void>;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const inputId = useId();
  const src = mediaUrl(audioUrl);

  async function handleFile(file: File | undefined) {
    if (!file) return;
    setUploading(true);
    try {
      await onUpload(file);
    } finally {
      setUploading(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  return (
    <div className="rounded-xl border border-gray-200 bg-gray-50 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <p className="text-sm font-semibold text-gray-800">Audio — {LANG_LABELS[lang]}</p>
        <AudioKindBadge kind={audioKind} />
      </div>
      {src ? (
        <audio controls preload="none" src={src} className="mt-3 w-full">
          Votre navigateur ne peut pas lire cet audio.
        </audio>
      ) : (
        <p className="mt-2 text-sm text-gray-600">Aucun audio pour cette langue.</p>
      )}
      <div className="mt-3">
        <label htmlFor={inputId} className="text-sm font-medium text-gray-700">
          Envoyer un enregistrement humain (wav, webm, ogg, m4a, mp3 — 10 Mo max.)
        </label>
        <input
          ref={inputRef}
          id={inputId}
          type="file"
          accept="audio/*,.wav,.webm,.ogg,.m4a,.mp3"
          disabled={!!disabledReason || uploading}
          onChange={(e) => handleFile(e.target.files?.[0])}
          className="mt-1 block w-full text-sm text-gray-700 file:mr-3 file:rounded-lg file:border-0 file:bg-white file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-gray-800 file:shadow-sm"
        />
        {uploading && (
          <p role="status" className="mt-1 text-xs text-gray-600">
            Envoi en cours…
          </p>
        )}
        {disabledReason && <p className="mt-1 text-xs text-gray-600">{disabledReason}</p>}
      </div>
    </div>
  );
}

/** Secret affiché une seule fois (mot de passe temporaire), avec copie. */
export function OneTimeSecret({ title, secret, onDismiss }: { title: string; secret: string; onDismiss: () => void }) {
  const [copied, setCopied] = useState<"idle" | "ok" | "fail">("idle");

  async function copy() {
    try {
      await navigator.clipboard.writeText(secret);
      setCopied("ok");
    } catch {
      setCopied("fail");
    }
  }

  return (
    <div role="alert" className="rounded-xl border-2 border-amber-400 bg-amber-50 p-4 sm:p-5">
      <p className="font-semibold text-amber-950">{title}</p>
      <p className="mt-1 text-sm text-amber-900">
        Ce mot de passe temporaire ne sera <strong>plus jamais affiché</strong>. Copiez-le maintenant et transmettez-le à
        la personne par un canal sûr ; elle devra le changer à sa première connexion.
      </p>
      <div className="mt-3 flex flex-col gap-2 sm:flex-row sm:items-center">
        <code className="rounded-lg border border-amber-300 bg-white px-3 py-2 font-mono text-base break-all text-gray-900 select-all">
          {secret}
        </code>
        <button type="button" onClick={copy} className={btnSecondary}>
          Copier
        </button>
      </div>
      <p className="mt-2 text-sm text-amber-900" aria-live="polite">
        {copied === "ok" && "Copié dans le presse-papiers."}
        {copied === "fail" && "Copie impossible : sélectionnez le texte et copiez-le manuellement."}
      </p>
      <button type="button" onClick={onDismiss} className="mt-2 text-sm font-semibold text-amber-950 underline">
        J'ai noté le mot de passe, masquer
      </button>
    </div>
  );
}

export function ValidationInfo({
  validatedBy,
  validatedAt,
}: {
  validatedBy: { full_name: string | null } | null;
  validatedAt: string | null;
}) {
  if (!validatedAt) return null;
  return (
    <span className="text-xs text-gray-600">
      Validé le {new Date(validatedAt).toLocaleDateString("fr-FR")}
      {validatedBy?.full_name ? ` par ${validatedBy.full_name}` : ""}
    </span>
  );
}
