import { apiClient } from "./client";
import type { PublicStats } from "./types";

/** `GET /public/stats?from=&to=` (sans authentification). Sans dates, le
 * backend applique sa période par défaut. */
export async function fetchPublicStats(period: { from?: string; to?: string } = {}): Promise<PublicStats> {
  const params: Record<string, string> = {};
  if (period.from) params.from = period.from;
  if (period.to) params.to = period.to;
  const response = await apiClient.get<PublicStats>("/public/stats", { params });
  return response.data;
}
