import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { fetchAdminStats } from "../api/admin";
import { apiErrorMessage } from "../api/client";
import type { AdminStats } from "../api/types";
import StatCard from "../components/StatCard";
import { Alert, Loading, PageHeader } from "../components/ui";
import { cardClass } from "../lib/styles";

// Palette catégorielle validée (ordre fixe) : brouillon, sourcé, validé. Le
// tableau sous le graphique donne les valeurs (contraste de l'aqua < 3:1).
const SERIES_DRAFT = "#eb6834";
const SERIES_SOURCED = "#1baf7a";
const SERIES_VALIDATED = "#2a78d6";

export default function DashboardPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchAdminStats()
      .then(setStats)
      .catch((err) => setError(apiErrorMessage(err)));
  }, []);

  if (error) return <Alert>{error}</Alert>;
  if (!stats) return <Loading />;

  const contentData = [
    { name: "Base de réponses", ...stats.kb },
    { name: "Capsules", ...stats.capsules },
  ];
  const hasContent = contentData.some((d) => d.draft + d.sourced + d.validated > 0);

  return (
    <div className="space-y-6">
      <PageHeader title="Tableau de bord" description="Vue d'ensemble de Laafi Ma. Aucune donnée personnelle n'est affichée ici." />

      <section aria-labelledby="dash-accounts" className="space-y-3">
        <h2 id="dash-accounts" className="text-sm font-semibold tracking-wide text-gray-600 uppercase">
          Comptes et activité
        </h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
          <StatCard label="Comptes utilisatrices" value={stats.women_accounts} hint="Comptes anonymes (sauvegarde)" />
          <StatCard label="Agents de santé" value={stats.agents} />
          <StatCard label="Validateurs" value={stats.validators} />
          <StatCard label="Événements (30 jours)" value={stats.events_last_30_days} hint="Statistiques anonymes" />
          <Link
            to="/unanswered"
            className="rounded-2xl focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:outline-none"
          >
            <StatCard label="Questions sans réponse" value={stats.unanswered_open} hint="À traiter →" />
          </Link>
        </div>
      </section>

      <section aria-labelledby="dash-content" className={cardClass}>
        <h2 id="dash-content" className="text-sm font-semibold text-gray-800">
          Contenus de santé par statut
        </h2>
        <p className="mt-1 text-xs text-gray-500">Seuls les contenus validés sont servis à l'application.</p>
        {!hasContent ? (
          <p className="mt-4 text-sm text-gray-600">
            Aucun contenu saisi pour le moment. Commencez par la{" "}
            <Link to="/kb" className="font-medium text-brand-700 hover:underline">
              base de réponses
            </Link>
            .
          </p>
        ) : (
          <>
            <div className="mt-4 h-64">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={contentData} barGap={2}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#eceae6" vertical={false} />
                  <XAxis dataKey="name" stroke="#6b7280" fontSize={12} tickLine={false} />
                  <YAxis allowDecimals={false} stroke="#6b7280" fontSize={12} tickLine={false} axisLine={false} />
                  <Tooltip cursor={{ fill: "rgba(0,0,0,0.04)" }} />
                  <Legend wrapperStyle={{ fontSize: 12 }} />
                  <Bar dataKey="draft" name="Brouillons" fill={SERIES_DRAFT} radius={[4, 4, 0, 0]} maxBarSize={48} />
                  <Bar dataKey="sourced" name="Sourcés, non relus" fill={SERIES_SOURCED} radius={[4, 4, 0, 0]} maxBarSize={48} />
                  <Bar dataKey="validated" name="Validés" fill={SERIES_VALIDATED} radius={[4, 4, 0, 0]} maxBarSize={48} />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <table className="mt-4 w-full text-left text-sm">
              <caption className="sr-only">Contenus par statut</caption>
              <thead className="text-gray-600">
                <tr>
                  <th scope="col" className="py-1 font-medium">Contenu</th>
                  <th scope="col" className="py-1 text-right font-medium">Brouillons</th>
                  <th scope="col" className="py-1 text-right font-medium">Sourcés, non relus</th>
                  <th scope="col" className="py-1 text-right font-medium">Validés</th>
                </tr>
              </thead>
              <tbody className="tabular-nums">
                {contentData.map((row) => (
                  <tr key={row.name} className="border-t border-gray-100">
                    <th scope="row" className="py-1.5 font-normal text-gray-800">{row.name}</th>
                    <td className="py-1.5 text-right">{row.draft}</td>
                    <td className="py-1.5 text-right">{row.sourced}</td>
                    <td className="py-1.5 text-right">{row.validated}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        )}
      </section>
    </div>
  );
}
