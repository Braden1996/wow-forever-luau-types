// Parses the generated definitions file into a ParsedDefinitions. The file's layout is fixed by the generator
// (generator/build.luau): named sections, one declaration or field per line, blocks closed at column 0.

import type {
  Alias,
  ApiEnum,
  ApiEvent,
  GlobalDeclaration,
  Member,
  Namespace,
  ParsedDefinitions,
  Structure,
  WidgetType,
} from "./model.ts";
import { functionOverloads, splitTopLevel } from "./type-expr.ts";

type Section =
  | "header"
  | "events"
  | "aliases"
  | "enumValueTypes"
  | "structures"
  | "widgets"
  | "scriptObjects"
  | "globals";

const SECTION_TITLES: ReadonlyArray<readonly [string, Section]> = [
  ["Events", "events"],
  ["Aliases", "aliases"],
  ["Enum value types", "enumValueTypes"],
  ["Structures and mixins", "structures"],
  ["Widgets (the client's own hierarchy)", "widgets"],
  ["Script objects", "scriptObjects"],
  ["Globals", "globals"],
];

const SECTION_LINE = /^-- (.+?) -{5,}$/;
const EXPORT_TYPE = /^export type ([A-Za-z_][A-Za-z0-9_]*)(<[^>]*>)? = (.*)$/;
const DECLARE_FUNCTION = /^declare function ([A-Za-z_][A-Za-z0-9_]*)(<[^>]*>)?\((.*)$/;
const DECLARE_VALUE = /^declare ([A-Za-z_][A-Za-z0-9_]*): (.*)$/;
const EXTERN_TYPE = /^declare extern type ([A-Za-z_][A-Za-z0-9_]*)(?: extends ([A-Za-z_][A-Za-z0-9_]*))? with$/;
const METHOD = /^\tfunction ([A-Za-z_][A-Za-z0-9_]*)\((.*)$/;
const FIELD = /^\t+(\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_]*): (.*?),?$/;

/** `(self, a: T): R` (the text after the opening parenthesis) as a function type without `self`. */
function methodType(afterParen: string, generics: string | undefined): string {
  let depth = 1;
  let close = -1;
  for (let i = 0; i < afterParen.length && close < 0; i += 1) {
    const char = afterParen.charAt(i);
    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
      if (depth === 0) {
        close = i;
      }
    }
  }
  const params = splitTopLevel(afterParen.slice(0, close), ",")
    .filter((param) => param !== "self")
    .map((param) => (param.startsWith("...:") ? `...${param.slice(4).trim()}` : param));
  const returns = afterParen
    .slice(close + 1)
    .replace(/^\s*:\s*/, "")
    .trim();
  return `${generics ?? ""}(${params.join(", ")}) -> ${returns.length > 0 ? returns : "()"}`;
}

function parseField(line: string): Member | undefined {
  const match = FIELD.exec(line);
  if (match?.[1] === undefined || match[2] === undefined) {
    return undefined;
  }
  return { name: match[1], type: match[2].trim() };
}

interface Block {
  readonly opener: string;
  readonly body: readonly string[];
}

/** Collects lines until the block's closing line at column 0 (`}` or `end`). */
function readBlock(lines: readonly string[], start: number, closer: string): { block: Block; next: number } {
  const body: string[] = [];
  let i = start + 1;
  while (i < lines.length && lines[i] !== closer) {
    body.push(lines[i] ?? "");
    i += 1;
  }
  return { block: { opener: lines[start] ?? "", body }, next: i + 1 };
}

/** A two-level table such as Enum or Constants: `\tName: {` ... `\t},`. */
function readNestedTables(body: readonly string[]): Namespace[] {
  const tables: Namespace[] = [];
  let current: { name: string; members: Member[] } | undefined;
  for (const line of body) {
    const open = /^\t([A-Za-z_][A-Za-z0-9_]*): \{$/.exec(line);
    if (open?.[1] !== undefined) {
      current = { name: open[1], members: [] };
      continue;
    }
    if (line === "\t},") {
      if (current !== undefined) {
        tables.push({ name: current.name, members: current.members, tables: [] });
      }
      current = undefined;
      continue;
    }
    const field = parseField(line);
    if (field !== undefined && current !== undefined) {
      current.members.push(field);
    }
  }
  return tables;
}

interface Collected {
  header: string[];
  events: ApiEvent[];
  aliases: Alias[];
  enumValueTypes: string[];
  structures: Structure[];
  widgets: WidgetType[];
  scriptTypes: Map<string, string[]>;
  frameTypes: string[];
  functions: GlobalDeclaration[];
  values: GlobalDeclaration[];
  namespaces: Namespace[];
  enums: ApiEnum[];
  supplementStart: number;
}

function addStructureOrAlias(out: Collected, name: string, rhs: string, body: readonly string[] | undefined): void {
  if (body === undefined) {
    out.aliases.push({ name, type: rhs });
    return;
  }
  const bases = splitTopLevel(rhs.replace(/\{$/, "").trim(), "&");
  const fields = body.map(parseField).filter((field): field is Member => field !== undefined);
  out.structures.push({ name, bases, fields });
}

function handleExportType(out: Collected, section: Section, line: string, body: readonly string[] | undefined): void {
  const match = EXPORT_TYPE.exec(line);
  const name = match?.[1];
  const rhs = match?.[3];
  if (name === undefined || rhs === undefined) {
    return;
  }
  if (section === "events") {
    if (name === "EventPayloads" && body !== undefined) {
      for (const field of body.map(parseField)) {
        if (field !== undefined) {
          out.events.push({ name: field.name, payload: field.type });
        }
      }
    } else if (!/^FrameEvent_\d+$/.test(name)) {
      out.aliases.push({ name, type: rhs });
    }
    return;
  }
  if (section === "enumValueTypes") {
    out.enumValueTypes.push(name);
    return;
  }
  if (section === "widgets" && name.endsWith("ScriptType")) {
    out.scriptTypes.set(
      name.slice(0, -"ScriptType".length),
      splitTopLevel(rhs, "|").map((part) => part.replaceAll('"', "")),
    );
    return;
  }
  if (name === "FrameTypeMap" && body !== undefined) {
    for (const field of body.map(parseField)) {
      if (field !== undefined) {
        out.frameTypes.push(field.name);
      }
    }
    return;
  }
  if (section === "aliases") {
    out.aliases.push({ name, type: rhs });
    return;
  }
  addStructureOrAlias(out, name, rhs, body);
}

function handleDeclare(out: Collected, line: string, body: readonly string[] | undefined): void {
  const fn = DECLARE_FUNCTION.exec(line);
  if (fn?.[1] !== undefined && fn[3] !== undefined) {
    out.functions.push({ name: fn[1], type: methodType(fn[3], fn[2]) });
    return;
  }
  const value = DECLARE_VALUE.exec(line);
  const name = value?.[1];
  const type = value?.[2];
  if (name === undefined || type === undefined) {
    return;
  }
  if (body !== undefined) {
    if (name === "Enum") {
      for (const table of readNestedTables(body)) {
        out.enums.push({ name: table.name, values: table.members.map((member) => member.name) });
      }
    } else if (name === "Constants") {
      out.namespaces.push({ name, members: [], tables: readNestedTables(body) });
    } else {
      const members = body.map(parseField).filter((field): field is Member => field !== undefined);
      out.namespaces.push({ name, members, tables: [] });
    }
    return;
  }
  if (functionOverloads(type).length > 0) {
    out.functions.push({ name, type });
  } else {
    out.values.push({ name, type });
  }
}

function attachScripts(out: Collected): WidgetType[] {
  const creatable = new Set(out.frameTypes);
  return out.widgets.map((widget) => ({
    ...widget,
    scripts: out.scriptTypes.get(widget.name) ?? [],
    creatable: creatable.has(widget.name),
  }));
}

export function parseDefinitions(source: string): ParsedDefinitions {
  const lines = source.replaceAll("\r\n", "\n").split("\n");
  const out: Collected = {
    header: [],
    events: [],
    aliases: [],
    enumValueTypes: [],
    structures: [],
    widgets: [],
    scriptTypes: new Map(),
    frameTypes: [],
    functions: [],
    values: [],
    namespaces: [],
    enums: [],
    supplementStart: -1,
  };
  let section: Section = "header";
  let i = 0;
  while (i < lines.length) {
    const line = lines[i] ?? "";
    const title = SECTION_LINE.exec(line)?.[1];
    const named = SECTION_TITLES.find(([text]) => text === title);
    if (named !== undefined) {
      section = named[1];
      i += 1;
      continue;
    }
    if (line.startsWith("-- Appended from supplements")) {
      out.supplementStart = i + 1;
    }
    if (section === "header" && line.startsWith("-- ")) {
      out.header.push(line.slice(3));
    }
    const extern = EXTERN_TYPE.exec(line);
    if (extern?.[1] !== undefined && section === "enumValueTypes") {
      // An opaque enum type (its only members are the comparison metamethods).
      out.enumValueTypes.push(extern[1]);
      i = readBlock(lines, i, "end").next;
      continue;
    }
    if (extern?.[1] !== undefined) {
      const { block, next } = readBlock(lines, i, "end");
      const methods: Member[] = [];
      for (const bodyLine of block.body) {
        const method = METHOD.exec(bodyLine);
        if (method?.[1] !== undefined && method[2] !== undefined) {
          methods.push({ name: method[1], type: methodType(method[2], undefined) });
        }
      }
      out.widgets.push({
        name: extern[1],
        parent: extern[2],
        methods,
        scripts: [],
        creatable: false,
        section: section === "widgets" ? "widget" : "scriptObject",
      });
      i = next;
      continue;
    }
    const opensBlock = line.endsWith("{") && (line.startsWith("export type ") || line.startsWith("declare "));
    let body: readonly string[] | undefined;
    let next = i + 1;
    if (opensBlock) {
      const read = readBlock(lines, i, "}");
      body = read.block.body;
      next = read.next;
    }
    if (line.startsWith("export type ")) {
      handleExportType(out, section, line, body);
    } else if (line.startsWith("declare ")) {
      handleDeclare(out, line, body);
    }
    i = next;
  }
  return {
    header: out.header,
    events: out.events,
    aliases: out.aliases,
    enumValueTypes: out.enumValueTypes,
    structures: out.structures,
    widgets: attachScripts(out),
    frameTypes: out.frameTypes,
    functions: out.functions,
    values: out.values,
    namespaces: out.namespaces,
    enums: out.enums,
    supplementStart: out.supplementStart,
  };
}
