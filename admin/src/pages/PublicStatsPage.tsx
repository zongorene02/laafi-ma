import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { fetchPublicStats } from "../api/publicStats";
import { AGENT_ACTIVITY_TYPES, EVENT_TYPES, type PublicStats } from "../api/types";
import StatCard from "../components/StatCard";
import { Alert, EmptyState, Loading } from "../components/ui";
import { AGENT_ACTIVITY_LABELS, eventLabel, formatDate, formatDateTime, langLabel } from "../lib/labels";
import {
  agentActivityTable,
  availableTypes,
  districtSeries,
  formatPublicNote,
  langSeries,
  monthlySeries,
  regionSeries,
  totalOf,
  understoodRate,
  weeklySeries,
} from "../lib/mappers";
import { formatIsoWeek, formatMonth, isValidRange, presetRange, type PeriodPreset } from "../lib/period";
import { btnPrimary, cardClass, inputClass, labelClass } from "../lib/styles";
import { useAsync } from "../lib/useAsync";

const REFRESH_MS = 60_000;
// Une seule série par graphique : couleur unique (slot 1 de la palette validée).
const SERIES_COLOR = "#2a78d6";
const GRID = "#eceae6";
const AXIS = "#6b7280";

const PRESETS: { value: PeriodPreset; label: string }[] = [
  { value: "default", label: "Période par défaut" },
  { value: "30d", label: "30 derniers jours" },
  { value: "90d", label: "90 derniers jours" },
  { value: "12m", label: "12 derniers mois" },
  { value: "custom", label: "Personnalisée" },
];

function typeOrder(type: string): number {
  const i = (EVENT_TYPES as readonly string[]).indexOf(type);
  return i === -1 ? EVENT_TYPES.length : i;
}

export default function PublicStatsPage() {
  const [preset, setPreset] = useState<PeriodPreset>("default");
  const [customFrom, setCustomFrom] = useState("");
  const [customTo, setCustomTo] = useState("");
  const [appliedRange, setAppliedRange] = useState<{ from?: string; to?: string }>({});
  const [selectedType, setSelectedType] = useState<string>("question_asked");
  const { data: stats, error, isLoading, reload } = useAsync(
    () => fetchPublicStats(appliedRange),
    JSON.stringify(appliedRange),
  );

  // Actualisation automatique toutes les 60 s avec la période appliquée.
  useEffect(() => {
    const interval = setInterval(reload, REFRESH_MS);
    return () => clearInterval(interval);
  }, [reload, appliedRange]);

  function handlePresetChange(value: PeriodPreset) {
    setPreset(value);
    if (value === "custom") {
      // Pré-remplit avec la période affichée ; appliquée via le bouton.
      if (stats) {
        setCustomFrom(stats.period.from);
        setCustomTo(stats.period.to);
      }
    } else {
      setAppliedRange(presetRange(value));
    }
  }

  const customValid = isValidRange(customFrom, customTo);

  const types = useMemo(() => (stats ? availableTypes(stats).sort((a, b) => typeOrder(a) - typeOrder(b)) : []), [stats]);
  const activeType = types.includes(selectedType) ? selectedType : (types[0] ?? selectedType);
  // `monthly_active` additionné sur plusieurs mois compterait des « mois-utilisatrices » :
  // il n'est montré que par mois (indicateurs d'impact).
  const totals = stats
    ? stats.totals.filter((t) => t.type !== "monthly_active").sort((a, b) => typeOrder(a.type) - typeOrder(b.type))
    : [];
  const weekly = stats ? weeklySeries(stats, activeType).map((r) => ({ ...r, label: formatIsoWeek(r.week) })) : [];
  const byLang = stats ? langSeries(stats, activeType).map((r) => ({ ...r, label: langLabel(r.lang) })) : [];
  const byDistrict = stats ? districtSeries(stats, activeType) : [];
  const hasImpactData =
    !!stats && ((stats.by_month ?? []).length > 0 || (stats.by_region ?? []).length > 0 || (stats.agent_activity ?? []).length > 0);

  return (
    <div className="min-h-screen">
      <header className="border-b border-gray-200 bg-white">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-2 px-4 py-4">
          <div>
            <p className="text-lg font-bold text-gray-900">Laafi Ma</p>
            <p className="text-xs text-gray-600">Statistiques publiques d'utilisation</p>
          </div>
          <Link to="/login" className="text-sm font-medium text-brand-700 hover:underline">
            Espace personnel →
          </Link>
        </div>
      </header>

      <main className="mx-auto max-w-6xl space-y-6 px-4 py-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Laafi Ma en chiffres</h1>
          <p className="mt-1 max-w-3xl text-sm text-gray-700">
            Utilisation de l'application de santé et de protection des femmes au Burkina Faso, en français, mooré et
            dioula. Aucune donnée personnelle : seules les utilisatrices ayant accepté les statistiques anonymes sont
            comptées, par jour, sans identifiant.
          </p>
        </div>

        <section aria-label="Période" className={`${cardClass} flex flex-col gap-4 md:flex-row md:items-end`}>
          <div className="md:w-64">
            <label htmlFor="pub-preset" className={labelClass}>Période</label>
            <select id="pub-preset" value={preset} onChange={(e) => handlePresetChange(e.target.value as PeriodPreset)} className={inputClass}>
              {PRESETS.map((p) => (
                <option key={p.value} value={p.value}>{p.label}</option>
              ))}
            </select>
          </div>
          {preset === "custom" && (
            <>
              <div>
                <label htmlFor="pub-from" className={labelClass}>Du</label>
                <input id="pub-from" type="date" value={customFrom} max={customTo || undefined} onChange={(e) => setCustomFrom(e.target.value)} className={inputClass} />
              </div>
              <div>
                <label htmlFor="pub-to" className={labelClass}>Au</label>
                <input id="pub-to" type="date" value={customTo} min={customFrom || undefined} onChange={(e) => setCustomTo(e.target.value)} className={inputClass} />
              </div>
              <button
                type="button"
                disabled={!customValid}
                onClick={() => setAppliedRange({ from: customFrom, to: customTo })}
                className={btnPrimary}
              >
                Appliquer
              </button>
            </>
          )}
          <p className="text-xs text-gray-600 md:ml-auto md:text-right" aria-live="polite">
            {stats && (
              <>
                Du {formatDate(stats.period.from)} au {formatDate(stats.period.to)}
                <br />
                Mis à jour le {formatDateTime(stats.generated_at)} · actualisation automatique toutes les 60 s
              </>
            )}
          </p>
        </section>

        {preset === "custom" && !customValid && (
          <Alert kind="info">Choisissez une date de début et une date de fin (la fin doit suivre le début).</Alert>
        )}

        {stats && (
          <Alert kind="info">
            <strong>{formatPublicNote(stats)}</strong> Les indicateurs liés à l'aide (appels, alertes) et aux signes de
            danger ne sont jamais ventilés par semaine ni par district, pour protéger les personnes concernées.
          </Alert>
        )}

        {error && <Alert>{error}{stats ? " Les chiffres affichés sont ceux du dernier chargement réussi." : ""}</Alert>}

        {isLoading && !stats ? (
          <Loading />
        ) : stats && totals.length === 0 && types.length === 0 && !hasImpactData ? (
          <EmptyState title="Aucun chiffre publiable sur cette période.">
            Soit aucune activité n'a été enregistrée, soit toutes les valeurs sont inférieures au seuil de {stats.min_count} et
            ont été masquées.
          </EmptyState>
        ) : stats ? (
          <>
            <section aria-labelledby="pub-totals" className="space-y-3">
              <h2 id="pub-totals" className="text-lg font-semibold text-gray-900">Totaux sur la période</h2>
              {totals.length === 0 ? (
                <p className="text-sm text-gray-600">Tous les totaux sont sous le seuil de publication.</p>
              ) : (
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                  {totals.map((t) => (
                    <StatCard key={t.type} label={eventLabel(t.type)} value={t.count} />
                  ))}
                </div>
              )}
            </section>

            <ImpactIndicators stats={stats} />

            <section aria-labelledby="pub-breakdown" className="space-y-4">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                <h2 id="pub-breakdown" className="text-lg font-semibold text-gray-900">Détail par indicateur</h2>
                <div className="sm:w-80">
                  <label htmlFor="pub-type" className={labelClass}>Indicateur</label>
                  <select id="pub-type" value={activeType} onChange={(e) => setSelectedType(e.target.value)} className={inputClass}>
                    {types.map((t) => (
                      <option key={t} value={t}>{eventLabel(t)}</option>
                    ))}
                  </select>
                </div>
              </div>

              <div className={cardClass}>
                <h3 className="text-sm font-semibold text-gray-800">{eventLabel(activeType)} — par semaine</h3>
                {weekly.length === 0 ? (
                  <p className="mt-3 text-sm text-gray-600">Pas de ventilation hebdomadaire publiable pour cet indicateur.</p>
                ) : (
                  <ChartWithTable
                    caption={`${eventLabel(activeType)} par semaine`}
                    data={weekly}
                    headers={["Semaine", "Nombre"]}
                  />
                )}
              </div>

              <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                <div className={cardClass}>
                  <h3 className="text-sm font-semibold text-gray-800">Par langue</h3>
                  {byLang.length === 0 ? (
                    <p className="mt-3 text-sm text-gray-600">Pas de ventilation par langue publiable.</p>
                  ) : (
                    <ChartWithTable caption={`${eventLabel(activeType)} par langue`} data={byLang} headers={["Langue", "Nombre"]} />
                  )}
                </div>
                <div className={cardClass}>
                  <h3 className="text-sm font-semibold text-gray-800">Par district</h3>
                  {byDistrict.length === 0 ? (
                    <p className="mt-3 text-sm text-gray-600">Pas de ventilation par district publiable pour cet indicateur.</p>
                  ) : (
                    <RankedTable
                      caption={`${eventLabel(activeType)} par district`}
                      header="District"
                      rows={byDistrict.map((r) => ({ label: r.district, count: r.count }))}
                    />
                  )}
                </div>
              </div>
            </section>
          </>
        ) : null}
      </main>
    </div>
  );
}

/** Indicateurs du dossier, calculés uniquement à partir de `GET /public/stats`. */
function ImpactIndicators({ stats }: { stats: PublicStats }) {
  const min = stats.min_count;
  const insufficient = `données insuffisantes (moins de ${min})`;
  const rate = understoodRate(stats);
  const cards: { label: string; value: number | null; hint?: string }[] = [
    { label: eventLabel("question_asked"), value: totalOf(stats, "question_asked") },
    { label: eventLabel("question_voice"), value: totalOf(stats, "question_voice") },
    { label: eventLabel("danger_flagged"), value: totalOf(stats, "danger_flagged") },
    { label: eventLabel("anc_visit_recorded"), value: totalOf(stats, "anc_visit_recorded") },
    { label: eventLabel("vaccine_recorded"), value: totalOf(stats, "vaccine_recorded") },
  ];
  const activeByMonth = monthlySeries(stats, "monthly_active").map((r) => ({ ...r, label: formatMonth(r.month) }));
  const voiceByLang = langSeries(stats, "question_voice").map((r) => ({ ...r, label: langLabel(r.lang) }));
  const dangerByMonth = monthlySeries(stats, "danger_flagged").map((r) => ({ ...r, label: formatMonth(r.month) }));
  const dangerByRegion = regionSeries(stats, "danger_flagged").map((r) => ({ label: r.region, count: r.count }));
  const agentRows = agentActivityTable(stats);
  const noData = <p className="mt-3 text-sm text-gray-600">Aucun chiffre publiable : {insufficient} ou aucune activité.</p>;

  return (
    <section aria-labelledby="pub-impact" className="space-y-4">
      <div>
        <h2 id="pub-impact" className="text-lg font-semibold text-gray-900">Indicateurs d'impact</h2>
        <p className="mt-1 text-xs text-gray-600">
          Tout chiffre inférieur à {min} est masqué ; les chiffres VBG et signes de danger ne sont publiés que par mois et
          par région.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((c) => (
          <StatCard key={c.label} label={c.label} value={c.value ?? "—"} hint={c.value === null ? insufficient : undefined} />
        ))}
        <StatCard
          label="Taux de réponses jugées comprises"
          value={rate.kind === "rate" ? rate.rate.toLocaleString("fr-FR", { style: "percent", maximumFractionDigits: 0 }) : "—"}
          hint={
            rate.kind === "rate"
              ? `${rate.understood.toLocaleString("fr-FR")} sur ${(rate.understood + rate.notUnderstood).toLocaleString("fr-FR")} réponses évaluées`
              : insufficient
          }
        />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className={cardClass}>
          <h3 className="text-sm font-semibold text-gray-800">Utilisatrices actives par mois</h3>
          {activeByMonth.length === 0 ? noData : (
            <ChartWithTable caption="Utilisatrices actives par mois" data={activeByMonth} headers={["Mois", "Utilisatrices"]} />
          )}
        </div>
        <div className={cardClass}>
          <h3 className="text-sm font-semibold text-gray-800">Questions vocales par langue</h3>
          {voiceByLang.length === 0 ? noData : (
            <ChartWithTable caption="Questions vocales par langue" data={voiceByLang} headers={["Langue", "Questions"]} />
          )}
        </div>
        <div className={cardClass}>
          <h3 className="text-sm font-semibold text-gray-800">Signes de danger détectés par mois</h3>
          {dangerByMonth.length === 0 ? noData : (
            <ChartWithTable caption="Signes de danger détectés par mois" data={dangerByMonth} headers={["Mois", "Signes détectés"]} />
          )}
        </div>
        <div className={cardClass}>
          <h3 className="text-sm font-semibold text-gray-800">Signes de danger détectés par région</h3>
          {dangerByRegion.length === 0 ? noData : (
            <RankedTable caption="Signes de danger détectés par région" header="Région" rows={dangerByRegion} />
          )}
        </div>
      </div>

      <div className={cardClass}>
        <h3 className="text-sm font-semibold text-gray-800">Activité des agents de santé communautaires</h3>
        <p className="mt-1 text-xs text-gray-600">
          Issue des dossiers des agents (aucune donnée des utilisatrices), par mois et région du district de l'agent.
        </p>
        {agentRows.length === 0 ? noData : (
          <div className="mt-3 overflow-x-auto">
            <table className="w-full min-w-[36rem] text-left text-sm">
              <caption className="sr-only">Activité des agents par mois et par région</caption>
              <thead className="text-gray-600">
                <tr>
                  <th scope="col" className="py-1 pr-3 font-medium">Mois</th>
                  <th scope="col" className="py-1 pr-3 font-medium">Région</th>
                  {AGENT_ACTIVITY_TYPES.map((t) => (
                    <th key={t} scope="col" className="py-1 pl-3 text-right font-medium">{AGENT_ACTIVITY_LABELS[t]}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="tabular-nums">
                {agentRows.map((row) => (
                  <tr key={`${row.month}|${row.region}`} className="border-t border-gray-100">
                    <th scope="row" className="py-2 pr-3 font-normal whitespace-nowrap text-gray-800">{formatMonth(row.month)}</th>
                    <td className="py-2 pr-3 text-gray-800">{row.region}</td>
                    {AGENT_ACTIVITY_TYPES.map((t) => {
                      const value = row[t];
                      return (
                        <td key={t} className="py-2 pl-3 text-right text-gray-900">
                          {value === null ? (
                            <span title={`Masqué (moins de ${min})`}>
                              <span aria-hidden="true">—</span>
                              <span className="sr-only">masqué, moins de {min}</span>
                            </span>
                          ) : (
                            value.toLocaleString("fr-FR")
                          )}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </section>
  );
}

/** Tableau classé avec barre proportionnelle (districts, régions). */
function RankedTable({ caption, header, rows }: { caption: string; header: string; rows: { label: string; count: number }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.count));
  return (
    <table className="mt-3 w-full text-left text-sm">
      <caption className="sr-only">{caption}</caption>
      <thead className="text-gray-600">
        <tr>
          <th scope="col" className="py-1 font-medium">{header}</th>
          <th scope="col" className="py-1 text-right font-medium">Nombre</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.label} className="border-t border-gray-100">
            <th scope="row" className="py-2 pr-3 font-normal text-gray-800">
              {row.label}
              <span aria-hidden="true" className="mt-1 block h-1.5 rounded-full" style={{ width: `${Math.max(4, (row.count / max) * 100)}%`, background: SERIES_COLOR }} />
            </th>
            <td className="py-2 text-right align-top tabular-nums text-gray-900">{row.count.toLocaleString("fr-FR")}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function ChartWithTable({
  caption,
  data,
  headers,
}: {
  caption: string;
  data: { label: string; count: number }[];
  headers: [string, string];
}) {
  const [showTable, setShowTable] = useState(false);
  return (
    <div className="mt-3">
      <div className="h-60" role="img" aria-label={`${caption} : ${data.map((d) => `${d.label} ${d.count}`).join(", ")}`}>
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ left: -16, right: 8 }}>
            <CartesianGrid strokeDasharray="3 3" stroke={GRID} vertical={false} />
            <XAxis dataKey="label" stroke={AXIS} fontSize={11} tickLine={false} interval="preserveStartEnd" />
            <YAxis allowDecimals={false} stroke={AXIS} fontSize={11} tickLine={false} axisLine={false} />
            <Tooltip cursor={{ fill: "rgba(0,0,0,0.04)" }} formatter={(value) => [Number(value).toLocaleString("fr-FR"), "Nombre"]} />
            <Bar dataKey="count" fill={SERIES_COLOR} radius={[4, 4, 0, 0]} maxBarSize={40} />
          </BarChart>
        </ResponsiveContainer>
      </div>
      <button type="button" onClick={() => setShowTable((v) => !v)} aria-expanded={showTable} className="mt-2 text-xs font-medium text-brand-700 hover:underline">
        {showTable ? "Masquer le tableau" : "Afficher le tableau des valeurs"}
      </button>
      {showTable && (
        <table className="mt-2 w-full text-left text-sm">
          <caption className="sr-only">{caption}</caption>
          <thead className="text-gray-600">
            <tr>
              <th scope="col" className="py-1 font-medium">{headers[0]}</th>
              <th scope="col" className="py-1 text-right font-medium">{headers[1]}</th>
            </tr>
          </thead>
          <tbody className="tabular-nums">
            {data.map((row) => (
              <tr key={row.label} className="border-t border-gray-100">
                <th scope="row" className="py-1 font-normal text-gray-800">{row.label}</th>
                <td className="py-1 text-right">{row.count.toLocaleString("fr-FR")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
