
const API_BASE = import.meta.env.VITE_PUBLIC_API_URL;
const AGENT_API_BASE = import.meta.env.VITE_PUBLIC_AGENT_API_URL;

export async function apiGet<T>(url: string): Promise<T> {
  const res = await fetch(`${API_BASE}${url}`, { cache: "no-store" });
  if (!res.ok) throw new Error("Failed to fetch");
  return res.json();
}

export async function apiPost<T>(url: string, body: any): Promise<T> {
  console.log("apiPost", JSON.stringify(body));
  const res = await fetch(`${API_BASE}${url}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error("Failed to post");
  return res.json();
}

export async function agentApiPost<T>(body: any): Promise<T> {
  console.log("agentApiPost", JSON.stringify(body));
  const res = await fetch(`${AGENT_API_BASE}/query`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error("Failed to post to agent API");
  return res.json();
}

export async function apiPut<T>(url: string, body: any): Promise<T> {
  const res = await fetch(`${API_BASE}${url}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error("Failed to update");
  return res.json();
}

export async function apiDelete<T>(url: string): Promise<T> {
  const res = await fetch(`${API_BASE}${url}`, { method: "DELETE" });
  if (!res.ok) throw new Error("Failed to delete");
  return res.json();
}
