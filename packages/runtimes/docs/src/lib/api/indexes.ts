// The two static JSON indexes the browser loads lazily: the symbol search list and the hover-card shards.
// Both are emitted at build time by endpoints under src/pages/api/.

import type { CardKind, Catalog } from "./catalog.ts";
import type { CoverageGroup } from "./coverage.ts";
import { lookupCoverage } from "./coverage.ts";
import type { Member } from "./model.ts";
import { apiPaths } from "./paths.ts";
import { isUntypedFunction } from "./type-expr.ts";

/** Search kinds, kept short because the index ships to the browser. */
export type SearchKind =
  | "namespace"
  | "function"
  | "value"
  | "widget"
  | "method"
  | "event"
  | "enum"
  | "structure"
  | "alias";

/** `[name, kind, path, untyped]`; untyped is 1 for APIs declared as `(...unknown) -> ...unknown`. */
export type SearchEntry = readonly [string, SearchKind, string, 0 | 1];

function untyped(type: string): 0 | 1 {
  return isUntypedFunction(type) ? 1 : 0;
}

export function buildSearchIndex(catalog: Catalog): SearchEntry[] {
  const { parsed } = catalog;
  const entries: SearchEntry[] = [];
  for (const ns of parsed.namespaces) {
    entries.push([ns.name, "namespace", apiPaths.namespace(ns.name), 0]);
    for (const member of ns.members) {
      entries.push([
        `${ns.name}.${member.name}`,
        "function",
        `${apiPaths.namespace(ns.name)}#${member.name}`,
        untyped(member.type),
      ]);
    }
  }
  for (const fn of parsed.functions) {
    entries.push([fn.name, "function", apiPaths.global(fn.name), untyped(fn.type)]);
  }
  for (const value of parsed.values) {
    entries.push([value.name, "value", apiPaths.global(value.name), 0]);
  }
  for (const widget of parsed.widgets) {
    entries.push([widget.name, "widget", apiPaths.widget(widget.name), 0]);
    for (const method of widget.methods) {
      entries.push([`${widget.name}:${method.name}`, "method", `${apiPaths.widget(widget.name)}#${method.name}`, 0]);
    }
  }
  for (const event of parsed.events) {
    entries.push([event.name, "event", apiPaths.event(event.name), 0]);
  }
  for (const apiEnum of parsed.enums) {
    entries.push([`Enum.${apiEnum.name}`, "enum", apiPaths.enumPage(apiEnum.name), 0]);
  }
  for (const structure of parsed.structures) {
    entries.push([structure.name, "structure", apiPaths.structure(structure.name), 0]);
  }
  for (const alias of parsed.aliases) {
    entries.push([alias.name, "alias", apiPaths.alias(alias.name), 0]);
  }
  return entries;
}

/** One hover card: a title, a plain-text Luau snippet, the page, and the coverage status when known. */
export interface Card {
  readonly title: string;
  readonly kind: string;
  readonly snippet: string;
  readonly path: string;
  readonly status: string | undefined;
  readonly source: string | undefined;
}

const MAX_LINES = 12;

function membersSnippet(members: readonly Member[], indent = "  "): string[] {
  const lines = members.slice(0, MAX_LINES).map((member) => `${indent}${member.name}: ${member.type},`);
  if (members.length > MAX_LINES) {
    lines.push(`${indent}-- ...${members.length - MAX_LINES} more`);
  }
  return lines;
}

function truncate(text: string, max = 600): string {
  return text.length > max ? `${text.slice(0, max)} ...` : text;
}

function withCoverage(
  catalog: Catalog,
  group: CoverageGroup,
  key: string,
  card: Omit<Card, "status" | "source">,
): Card {
  const coverage = lookupCoverage(catalog.coverage, group, key);
  return { ...card, status: coverage?.status, source: coverage?.source };
}

export function buildCards(catalog: Catalog): Map<CardKind, Record<string, Card>> {
  const shards = new Map<CardKind, Record<string, Card>>();
  const put = (kind: CardKind, name: string, card: Card): void => {
    const shard = shards.get(kind) ?? {};
    shard[name] = card;
    shards.set(kind, shard);
  };
  for (const structure of catalog.parsed.structures) {
    const head = structure.bases.length > 0 ? `${structure.bases.join(" & ")} & {` : "{";
    const snippet = [`type ${structure.name} = ${head}`, ...membersSnippet(structure.fields), "}"].join("\n");
    put(
      "structure",
      structure.name,
      withCoverage(catalog, "structures", structure.name, {
        title: structure.name,
        kind: structure.name.endsWith("Mixin") ? "Mixin" : "Structure",
        snippet,
        path: apiPaths.structure(structure.name),
      }),
    );
  }
  for (const widget of catalog.parsed.widgets) {
    const chain = catalog.widgetChain(widget.name).map((link) => link.name);
    const inherited = catalog
      .widgetChain(widget.name)
      .slice(1)
      .reduce((total, link) => total + link.methods.length, 0);
    const snippet = [
      `declare extern type ${widget.name}${widget.parent === undefined ? "" : ` extends ${widget.parent}`}`,
      `-- ${chain.join(" < ")}`,
      `-- ${widget.methods.length} methods, ${inherited} inherited${widget.scripts.length > 0 ? `, ${widget.scripts.length} script handlers` : ""}`,
      ...(widget.creatable ? [`-- CreateFrame("${widget.name}") returns ${widget.name}`] : []),
    ].join("\n");
    put(
      "widget",
      widget.name,
      withCoverage(catalog, "widgets", widget.name, {
        title: widget.name,
        kind: widget.section === "widget" ? "Widget" : "Script object",
        snippet,
        path: apiPaths.widget(widget.name),
      }),
    );
  }
  for (const alias of catalog.parsed.aliases) {
    put("alias", alias.name, {
      title: alias.name,
      kind: "Type alias",
      snippet: truncate(`type ${alias.name} = ${alias.type}`),
      path: apiPaths.alias(alias.name),
      status: undefined,
      source: undefined,
    });
  }
  for (const apiEnum of catalog.parsed.enums) {
    const values = apiEnum.values.slice(0, MAX_LINES).map((value) => `  ${value},`);
    const more = apiEnum.values.length > MAX_LINES ? [`  -- ...${apiEnum.values.length - MAX_LINES} more`] : [];
    put(
      "enum",
      apiEnum.name,
      withCoverage(catalog, "enums", `Enum.${apiEnum.name}`, {
        title: `Enum.${apiEnum.name}`,
        kind: "Enum",
        snippet: [`Enum.${apiEnum.name} = {`, ...values, ...more, "}"].join("\n"),
        path: apiPaths.enumPage(apiEnum.name),
      }),
    );
  }
  for (const event of catalog.parsed.events) {
    put(
      "event",
      event.name,
      withCoverage(catalog, "events", event.name, {
        title: event.name,
        kind: "Event",
        snippet: truncate(`EventHandler<"${event.name}">\n  = ${event.payload}`),
        path: apiPaths.event(event.name),
      }),
    );
  }
  for (const ns of catalog.parsed.namespaces) {
    put("namespace", ns.name, {
      title: ns.name,
      kind: "Namespace",
      snippet: [`declare ${ns.name}: {`, ...membersSnippet(ns.members), "}"].join("\n"),
      path: apiPaths.namespace(ns.name),
      status: undefined,
      source: undefined,
    });
  }
  for (const fn of catalog.parsed.functions) {
    put(
      "global",
      fn.name,
      withCoverage(catalog, "functions", fn.name, {
        title: fn.name,
        kind: "Function",
        snippet: truncate(`${fn.name}: ${fn.type}`),
        path: apiPaths.global(fn.name),
      }),
    );
  }
  return shards;
}
