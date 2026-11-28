// Fetches and validates the static JSON indexes (search list and hover-card shards) once per page.

import type { SearchEntry, SearchKind } from "../../lib/api/indexes.ts";
import { withBase } from "../../lib/site.ts";

const KINDS: ReadonlySet<string> = new Set<SearchKind>([
  "namespace",
  "function",
  "value",
  "widget",
  "method",
  "event",
  "enum",
  "structure",
  "alias",
]);

function isKind(value: unknown): value is SearchKind {
  return typeof value === "string" && KINDS.has(value);
}

function toEntry(value: unknown): SearchEntry | undefined {
  if (!Array.isArray(value) || value.length !== 4) {
    return undefined;
  }
  const entry: readonly unknown[] = value;
  const [name, kind, path, untyped] = entry;
  if (typeof name !== "string" || !isKind(kind) || typeof path !== "string" || (untyped !== 0 && untyped !== 1)) {
    return undefined;
  }
  return [name, kind, path, untyped];
}

let searchIndex: Promise<SearchEntry[]> | undefined;

export function loadSearchIndex(): Promise<SearchEntry[]> {
  searchIndex ??= fetch(withBase("/api/search.json"))
    .then(async (response) => {
      if (!response.ok) {
        throw new Error(`search index: HTTP ${response.status}`);
      }
      const json: unknown = await response.json();
      if (!Array.isArray(json)) {
        throw new Error("search index: expected an array");
      }
      return json.map(toEntry).filter((entry): entry is SearchEntry => entry !== undefined);
    })
    .catch((error: unknown) => {
      searchIndex = undefined;
      throw error instanceof Error ? error : new Error(String(error));
    });
  return searchIndex;
}

export interface CardData {
  readonly title: string;
  readonly kind: string;
  readonly snippet: string;
  readonly path: string;
  readonly status: string | undefined;
  readonly source: string | undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function toCard(value: unknown): CardData | undefined {
  if (!isRecord(value)) {
    return undefined;
  }
  const { title, kind, snippet, path } = value;
  if (
    typeof title !== "string" ||
    typeof kind !== "string" ||
    typeof snippet !== "string" ||
    typeof path !== "string"
  ) {
    return undefined;
  }
  return {
    title,
    kind,
    snippet,
    path,
    status: optionalString(value["status"]),
    source: optionalString(value["source"]),
  };
}

const shards = new Map<string, Promise<ReadonlyMap<string, CardData>>>();

/** Loads the card for a `kind:name` symbol id, or undefined when there is none. */
export async function loadCard(symbol: string): Promise<CardData | undefined> {
  const colon = symbol.indexOf(":");
  const kind = symbol.slice(0, colon);
  const name = symbol.slice(colon + 1);
  if (colon < 1 || !/^[a-z]+$/.test(kind)) {
    return undefined;
  }
  let shard = shards.get(kind);
  if (shard === undefined) {
    shard = fetch(withBase(`/api/cards/${kind}.json`)).then(async (response) => {
      if (!response.ok) {
        return new Map<string, CardData>();
      }
      const json: unknown = await response.json();
      const cards = new Map<string, CardData>();
      if (isRecord(json)) {
        for (const [key, value] of Object.entries(json)) {
          const card = toCard(value);
          if (card !== undefined) {
            cards.set(key, card);
          }
        }
      }
      return cards;
    });
    shards.set(kind, shard);
  }
  return (await shard).get(name);
}
