import "server-only";

import { redirect } from "next/navigation";

import { merchantApi } from "@/lib/server/session-api";

export type MerchantTenant = {
  id: string;
  name: string;
  slug: string;
  status: string;
  membership: { role: string; status: string };
  stores_count: number;
  accessible: boolean;
};

export type MerchantStore = { id: string; name: string; slug: string; status: string };

type TenantDirectory = { tenants: MerchantTenant[] };
type StoreDirectory = { tenant_id: string; role: string; stores: MerchantStore[] };

export type MerchantQuery = { tenant?: string; store?: string };

export async function loadMerchantContext(query: MerchantQuery) {
  const tenantResult = await merchantApi<TenantDirectory>("/v1/tenants");
  if (!tenantResult || tenantResult.status === 401) redirect("/merchant/login");

  const tenants = tenantResult.data?.tenants.filter((tenant) => tenant.accessible) ?? [];
  const selectedTenant = tenants.find((tenant) => tenant.id === query.tenant) ?? tenants[0] ?? null;

  if (!selectedTenant) {
    return { tenants, selectedTenant: null, stores: [], selectedStore: null, role: null };
  }

  const storesResult = await merchantApi<StoreDirectory>("/v1/stores", selectedTenant.id);
  if (!storesResult || storesResult.status === 401) redirect("/merchant/login");

  const stores = storesResult.data?.stores ?? [];
  const selectedStore = stores.find((store) => store.id === query.store) ?? stores[0] ?? null;

  return {
    tenants,
    selectedTenant,
    stores,
    selectedStore,
    role: storesResult.data?.role ?? selectedTenant.membership.role,
  };
}
