import { apiClient } from "./client";
import type { District, DistrictPayload } from "./types";

/** `GET /districts` (sans authentification). */
export async function listDistricts(): Promise<District[]> {
  const response = await apiClient.get<District[]>("/districts");
  return response.data;
}

export async function createDistrict(payload: DistrictPayload): Promise<District> {
  const response = await apiClient.post<District>("/districts", payload);
  return response.data;
}

export async function updateDistrict(id: string, payload: DistrictPayload): Promise<District> {
  const response = await apiClient.put<District>(`/districts/${id}`, payload);
  return response.data;
}

export async function deleteDistrict(id: string): Promise<void> {
  await apiClient.delete(`/districts/${id}`);
}
