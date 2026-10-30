import { apiClient } from "./client";
import type { HelpService, HelpServicePayload } from "./types";

/** `GET /help/services`.
 *
 * Écart au contrat : la route ne renvoie que les services actifs. On envoie
 * `include_inactive=true` (ignoré s'il n'est pas géré) pour qu'un admin
 * puisse retrouver et réactiver un service désactivé. */
export async function listHelpServices(): Promise<HelpService[]> {
  const response = await apiClient.get<HelpService[]>("/help/services", {
    params: { include_inactive: "true" },
  });
  return response.data;
}

export async function createHelpService(payload: HelpServicePayload): Promise<HelpService> {
  const response = await apiClient.post<HelpService>("/help/services", payload);
  return response.data;
}

export async function updateHelpService(id: string, payload: HelpServicePayload): Promise<HelpService> {
  const response = await apiClient.put<HelpService>(`/help/services/${id}`, payload);
  return response.data;
}

export async function deleteHelpService(id: string): Promise<void> {
  await apiClient.delete(`/help/services/${id}`);
}

/** `POST /help/services/{id}/verify` — fixe `verified_at` à aujourd'hui. */
export async function verifyHelpService(id: string): Promise<HelpService> {
  const response = await apiClient.post<HelpService>(`/help/services/${id}/verify`);
  return response.data;
}
