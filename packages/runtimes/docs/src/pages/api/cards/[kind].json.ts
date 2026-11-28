// Hover-card shards, one JSON file per kind (/api/cards/structure.json, ...), loaded on first hover.

import type { APIRoute, GetStaticPaths } from "astro";

import { buildCards } from "../../../lib/api/indexes.ts";
import { loadCatalog } from "../../../lib/api/load.ts";

const shards = buildCards(loadCatalog());

export const getStaticPaths = (() => [...shards.keys()].map((kind) => ({ params: { kind } }))) satisfies GetStaticPaths;

export const GET: APIRoute = ({ params }) => {
  const kind = params["kind"];
  const shard = [...shards.entries()].find(([key]) => key === kind)?.[1];
  if (shard === undefined) {
    return new Response("Not found", { status: 404 });
  }
  return new Response(JSON.stringify(shard), { headers: { "Content-Type": "application/json" } });
};
