// The definitions file, copied into the site so the in-browser checker can load it (same origin, no server).

import type { APIRoute } from "astro";

import { readDefinitionsSource } from "../../lib/api/load.ts";

export const GET: APIRoute = () =>
  new Response(readDefinitionsSource(), { headers: { "Content-Type": "text/plain; charset=utf-8" } });
