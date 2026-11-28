// The symbol search index, emitted at build time as /api/search.json and loaded lazily by the search dialog.

import type { APIRoute } from "astro";

import { buildSearchIndex } from "../../lib/api/indexes.ts";
import { loadCatalog } from "../../lib/api/load.ts";

export const GET: APIRoute = () =>
  new Response(JSON.stringify(buildSearchIndex(loadCatalog())), {
    headers: { "Content-Type": "application/json" },
  });
