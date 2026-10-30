import { apiClient } from "./client";
import type { Capsule, CapsulePayload, CapsuleTrack, Lang } from "./types";

/** `GET /learn/capsules?track=` avec le jeton du personnel.
 *
 * Écart au contrat : la route publique ne renvoie que les capsules validées
 * et il n'existe pas de liste réservée au personnel. On envoie
 * `include_drafts=true` (ignoré par FastAPI s'il n'est pas géré) en
 * supposant que le backend renvoie alors tous les statuts à un
 * validateur/admin authentifié. */
export async function listCapsules(track?: CapsuleTrack | ""): Promise<Capsule[]> {
  const params: Record<string, string> = { include_drafts: "true" };
  if (track) params.track = track;
  const response = await apiClient.get<Capsule[]>("/learn/capsules", { params });
  return response.data;
}

export async function createCapsule(payload: CapsulePayload): Promise<Capsule> {
  const response = await apiClient.post<Capsule>("/learn/capsules", payload);
  return response.data;
}

export async function updateCapsule(id: string, payload: CapsulePayload): Promise<Capsule> {
  const response = await apiClient.put<Capsule>(`/learn/capsules/${id}`, payload);
  return response.data;
}

export async function deleteCapsule(id: string): Promise<void> {
  await apiClient.delete(`/learn/capsules/${id}`);
}

export async function validateCapsule(id: string): Promise<Capsule> {
  const response = await apiClient.post<Capsule>(`/learn/capsules/${id}/validate`);
  return response.data;
}

/** `POST /learn/capsules/{id}/audio/{lang}` multipart `audio`. */
export async function uploadCapsuleAudio(id: string, lang: Lang, file: File): Promise<Capsule> {
  const form = new FormData();
  form.append("audio", file);
  const response = await apiClient.post<Capsule>(`/learn/capsules/${id}/audio/${lang}`, form);
  return response.data;
}
