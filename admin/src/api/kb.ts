import { apiClient } from "./client";
import type {
  ContentStatus,
  DangerSign,
  DangerSignPayload,
  KbEntry,
  KbEntryPayload,
  KbTopic,
  Lang,
  UnansweredQuestion,
} from "./types";

export interface KbFilters {
  status?: ContentStatus | "";
  topic?: KbTopic | "";
  q?: string;
}

/** `GET /kb/entries?status=&topic=&q=` — paramètres vides omis. */
export async function listKbEntries(filters: KbFilters = {}): Promise<KbEntry[]> {
  const params: Record<string, string> = {};
  if (filters.status) params.status = filters.status;
  if (filters.topic) params.topic = filters.topic;
  if (filters.q?.trim()) params.q = filters.q.trim();
  const response = await apiClient.get<KbEntry[]>("/kb/entries", { params });
  return response.data;
}

export async function getKbEntry(id: string): Promise<KbEntry> {
  const response = await apiClient.get<KbEntry>(`/kb/entries/${id}`);
  return response.data;
}

export async function createKbEntry(payload: KbEntryPayload): Promise<KbEntry> {
  const response = await apiClient.post<KbEntry>("/kb/entries", payload);
  return response.data;
}

export async function updateKbEntry(id: string, payload: KbEntryPayload): Promise<KbEntry> {
  const response = await apiClient.put<KbEntry>(`/kb/entries/${id}`, payload);
  return response.data;
}

export async function deleteKbEntry(id: string): Promise<void> {
  await apiClient.delete(`/kb/entries/${id}`);
}

/** `POST /kb/entries/{id}/validate` — 409 si la traduction fr manque. */
export async function validateKbEntry(id: string): Promise<KbEntry> {
  const response = await apiClient.post<KbEntry>(`/kb/entries/${id}/validate`);
  return response.data;
}

export async function archiveKbEntry(id: string): Promise<KbEntry> {
  const response = await apiClient.post<KbEntry>(`/kb/entries/${id}/archive`);
  return response.data;
}

/** `POST /kb/entries/{id}/audio/{lang}` multipart `audio` (enregistrement humain). */
export async function uploadKbAudio(id: string, lang: Lang, file: File): Promise<KbEntry> {
  const form = new FormData();
  form.append("audio", file);
  const response = await apiClient.post<KbEntry>(`/kb/entries/${id}/audio/${lang}`, form);
  return response.data;
}

/** `POST /kb/entries/{id}/translate` — remplit les mos/dyu manquants. */
export async function translateKbEntry(id: string): Promise<KbEntry> {
  const response = await apiClient.post<KbEntry>(`/kb/entries/${id}/translate`);
  return response.data;
}

// ---- Signes de danger -------------------------------------------------------

export async function listDangerSigns(): Promise<DangerSign[]> {
  const response = await apiClient.get<DangerSign[]>("/kb/danger-signs");
  return response.data;
}

export async function createDangerSign(payload: DangerSignPayload): Promise<DangerSign> {
  const response = await apiClient.post<DangerSign>("/kb/danger-signs", payload);
  return response.data;
}

export async function updateDangerSign(id: string, payload: DangerSignPayload): Promise<DangerSign> {
  const response = await apiClient.put<DangerSign>(`/kb/danger-signs/${id}`, payload);
  return response.data;
}

export async function deleteDangerSign(id: string): Promise<void> {
  await apiClient.delete(`/kb/danger-signs/${id}`);
}

export async function validateDangerSign(id: string): Promise<DangerSign> {
  const response = await apiClient.post<DangerSign>(`/kb/danger-signs/${id}/validate`);
  return response.data;
}

// ---- Questions sans réponse -------------------------------------------------

/** `GET /kb/unanswered?resolved=` */
export async function listUnanswered(resolved: boolean): Promise<UnansweredQuestion[]> {
  const response = await apiClient.get<UnansweredQuestion[]>("/kb/unanswered", { params: { resolved } });
  return response.data;
}

/** `POST /kb/unanswered/{id}/resolve` → 204 */
export async function resolveUnanswered(id: string): Promise<void> {
  await apiClient.post(`/kb/unanswered/${id}/resolve`);
}
