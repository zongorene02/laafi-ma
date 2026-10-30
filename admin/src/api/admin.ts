import { apiClient } from "./client";
import type {
  AdminStats,
  AdminUser,
  CreateUserPayload,
  CreateUserResponse,
  ServicesHealth,
  StaffRole,
  UpdateUserPayload,
} from "./types";

/** `GET /admin/users?role=` — personnel uniquement (jamais les comptes `woman`). */
export async function listUsers(role?: StaffRole | ""): Promise<AdminUser[]> {
  const response = await apiClient.get<AdminUser[]>("/admin/users", { params: role ? { role } : {} });
  return response.data;
}

/** `POST /admin/users` → utilisateur + mot de passe temporaire (affiché une fois). */
export async function createUser(payload: CreateUserPayload): Promise<CreateUserResponse> {
  const response = await apiClient.post<CreateUserResponse>("/admin/users", payload);
  return response.data;
}

/** `PATCH /admin/users/{id}` */
export async function updateUser(userId: string, payload: UpdateUserPayload): Promise<AdminUser> {
  const response = await apiClient.patch<AdminUser>(`/admin/users/${userId}`, payload);
  return response.data;
}

/** `POST /admin/users/{id}/reset-password` → mot de passe temporaire. */
export async function resetUserPassword(userId: string): Promise<string> {
  const response = await apiClient.post<{ temporary_password: string }>(`/admin/users/${userId}/reset-password`);
  return response.data.temporary_password;
}

/** `DELETE /admin/users/{id}` */
export async function deleteUser(userId: string): Promise<void> {
  await apiClient.delete(`/admin/users/${userId}`);
}

/** `GET /admin/stats` */
export async function fetchAdminStats(): Promise<AdminStats> {
  const response = await apiClient.get<AdminStats>("/admin/stats");
  return response.data;
}

/** `GET /admin/health` */
export async function fetchServicesHealth(): Promise<ServicesHealth> {
  const response = await apiClient.get<ServicesHealth>("/admin/health");
  return response.data;
}
