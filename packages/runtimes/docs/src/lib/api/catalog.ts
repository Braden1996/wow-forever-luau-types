// Cross-references the parsed definitions: resolves type names to pages, walks inheritance, and records which
// APIs use each type ("used by").

import type { CoverageIndex } from "./coverage.ts";
import type {
  Alias,
  ApiEnum,
  ApiEvent,
  GlobalDeclaration,
  Namespace,
  ParsedDefinitions,
  Structure,
  WidgetType,
} from "./model.ts";
import { apiPaths, globalLetter } from "./paths.ts";
import { referencedTypes } from "./type-expr.ts";

export type CardKind = "structure" | "widget" | "alias" | "enum" | "event" | "namespace" | "global";

/** Where a type name in an expression links to, and which hover card describes it. */
export interface TypeTarget {
  readonly path: string;
  readonly card: CardKind;
  readonly name: string;
}

export interface Referrer {
  readonly label: string;
  readonly path: string;
}

export interface GlobalsPage {
  readonly letter: string;
  readonly functions: readonly GlobalDeclaration[];
  readonly values: readonly GlobalDeclaration[];
}

export interface Catalog {
  readonly parsed: ParsedDefinitions;
  readonly coverage: CoverageIndex;
  readonly structures: ReadonlyMap<string, Structure>;
  readonly widgets: ReadonlyMap<string, WidgetType>;
  readonly aliases: ReadonlyMap<string, Alias>;
  readonly enums: ReadonlyMap<string, ApiEnum>;
  readonly events: ReadonlyMap<string, ApiEvent>;
  readonly namespaces: ReadonlyMap<string, Namespace>;
  readonly globals: readonly GlobalsPage[];
  resolve(typeName: string): TypeTarget | undefined;
  usedBy(target: TypeTarget): readonly Referrer[];
  /** The widget and its ancestors, nearest first. */
  widgetChain(name: string): WidgetType[];
  /** Direct subtypes of a widget. */
  widgetChildren(name: string): WidgetType[];
  /** The structure's bases, transitively, nearest first. */
  structureChain(name: string): Structure[];
  /** Structures that extend this one directly. */
  structureChildren(name: string): Structure[];
}

function byName<T extends { readonly name: string }>(items: readonly T[]): Map<string, T> {
  return new Map(items.map((item) => [item.name, item]));
}

function buildResolver(
  parsed: ParsedDefinitions,
  structures: ReadonlyMap<string, Structure>,
  widgets: ReadonlyMap<string, WidgetType>,
  aliases: ReadonlyMap<string, Alias>,
  enums: ReadonlyMap<string, ApiEnum>,
): (typeName: string) => TypeTarget | undefined {
  const special = new Map<string, TypeTarget>([
    ["FrameEvent", { path: apiPaths.events, card: "alias", name: "FrameEvent" }],
    ["EventPayloads", { path: apiPaths.events, card: "alias", name: "EventHandler" }],
    ["FrameTypeMap", { path: apiPaths.widgets, card: "global", name: "CreateFrame" }],
  ]);
  const enumTypes = new Set(parsed.enumValueTypes);
  return (typeName) => {
    const fixed = special.get(typeName);
    if (fixed !== undefined) {
      return fixed;
    }
    if (structures.has(typeName)) {
      return { path: apiPaths.structure(typeName), card: "structure", name: typeName };
    }
    if (widgets.has(typeName)) {
      return { path: apiPaths.widget(typeName), card: "widget", name: typeName };
    }
    if (enumTypes.has(typeName)) {
      const enumName = typeName.slice("Enum_".length);
      return enums.has(enumName) ? { path: apiPaths.enumPage(enumName), card: "enum", name: enumName } : undefined;
    }
    if (typeName.endsWith("ScriptType")) {
      const widget = typeName.slice(0, -"ScriptType".length);
      if (widgets.has(widget)) {
        return { path: `${apiPaths.widget(widget)}#scripts`, card: "widget", name: widget };
      }
    }
    if (aliases.has(typeName)) {
      return { path: apiPaths.alias(typeName), card: "alias", name: typeName };
    }
    return undefined;
  };
}

function targetKey(target: TypeTarget): string {
  return `${target.card}:${target.name}`;
}

function collectUsage(
  parsed: ParsedDefinitions,
  resolve: (typeName: string) => TypeTarget | undefined,
): Map<string, Referrer[]> {
  const usage = new Map<string, Referrer[]>();
  const record = (expr: string, referrer: Referrer): void => {
    for (const typeName of referencedTypes(expr)) {
      const target = resolve(typeName);
      if (target === undefined) {
        continue;
      }
      const key = targetKey(target);
      const list = usage.get(key) ?? [];
      if (list.at(-1)?.path !== referrer.path) {
        list.push(referrer);
      }
      usage.set(key, list);
    }
  };
  for (const ns of parsed.namespaces) {
    for (const member of ns.members) {
      record(member.type, {
        label: `${ns.name}.${member.name}`,
        path: `${apiPaths.namespace(ns.name)}#${member.name}`,
      });
    }
  }
  for (const decl of [...parsed.functions, ...parsed.values]) {
    record(decl.type, { label: decl.name, path: apiPaths.global(decl.name) });
  }
  for (const widget of parsed.widgets) {
    for (const method of widget.methods) {
      record(method.type, {
        label: `${widget.name}:${method.name}`,
        path: `${apiPaths.widget(widget.name)}#${method.name}`,
      });
    }
  }
  for (const event of parsed.events) {
    record(event.payload, { label: event.name, path: apiPaths.event(event.name) });
  }
  for (const structure of parsed.structures) {
    for (const base of structure.bases) {
      record(base, { label: structure.name, path: apiPaths.structure(structure.name) });
    }
    for (const field of structure.fields) {
      record(field.type, { label: `${structure.name}.${field.name}`, path: apiPaths.structure(structure.name) });
    }
  }
  for (const alias of parsed.aliases) {
    record(alias.type, { label: alias.name, path: apiPaths.alias(alias.name) });
  }
  return usage;
}

function compareByName(a: GlobalDeclaration, b: GlobalDeclaration): number {
  return a.name.localeCompare(b.name, "en");
}

function groupGlobals(parsed: ParsedDefinitions): GlobalsPage[] {
  const pages = new Map<string, { functions: GlobalDeclaration[]; values: GlobalDeclaration[] }>();
  const page = (name: string): { functions: GlobalDeclaration[]; values: GlobalDeclaration[] } => {
    const letter = globalLetter(name);
    const existing = pages.get(letter);
    if (existing !== undefined) {
      return existing;
    }
    const created = { functions: [], values: [] };
    pages.set(letter, created);
    return created;
  };
  for (const fn of parsed.functions) {
    page(fn.name).functions.push(fn);
  }
  for (const value of parsed.values) {
    page(value.name).values.push(value);
  }
  return [...pages.entries()]
    .map(([letter, entries]) => ({
      letter,
      functions: entries.functions.toSorted(compareByName),
      values: entries.values.toSorted(compareByName),
    }))
    .toSorted((a, b) => a.letter.localeCompare(b.letter, "en"));
}

export function buildCatalog(parsed: ParsedDefinitions, coverage: CoverageIndex): Catalog {
  const structures = byName(parsed.structures);
  const widgets = byName(parsed.widgets);
  const aliases = byName(parsed.aliases);
  const enums = byName(parsed.enums);
  const events = byName(parsed.events);
  const namespaces = byName(parsed.namespaces);
  const resolve = buildResolver(parsed, structures, widgets, aliases, enums);
  const usage = collectUsage(parsed, resolve);

  const widgetChain = (name: string): WidgetType[] => {
    const chain: WidgetType[] = [];
    let current = widgets.get(name);
    while (current !== undefined && chain.length < 32) {
      chain.push(current);
      current = current.parent === undefined ? undefined : widgets.get(current.parent);
    }
    return chain;
  };

  const structureChain = (name: string): Structure[] => {
    const chain: Structure[] = [];
    const visit = (structureName: string): void => {
      const structure = structures.get(structureName);
      if (structure === undefined || chain.includes(structure) || chain.length > 32) {
        return;
      }
      chain.push(structure);
      for (const base of structure.bases) {
        visit(base);
      }
    };
    for (const base of structures.get(name)?.bases ?? []) {
      visit(base);
    }
    return chain;
  };

  return {
    parsed,
    coverage,
    structures,
    widgets,
    aliases,
    enums,
    events,
    namespaces,
    globals: groupGlobals(parsed),
    resolve,
    usedBy: (target) => usage.get(targetKey(target)) ?? [],
    widgetChain,
    widgetChildren: (name) => parsed.widgets.filter((widget) => widget.parent === name),
    structureChain,
    structureChildren: (name) => parsed.structures.filter((structure) => structure.bases.includes(name)),
  };
}
