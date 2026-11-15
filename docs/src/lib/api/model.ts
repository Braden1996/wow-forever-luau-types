// The API model the reference pages render. Built at build time from definitions/wow-forever.d.luau and
// definitions/coverage.json; nothing here runs in the browser except through the small JSON indexes.

export type SymbolKind =
  | "namespace"
  | "function"
  | "value"
  | "widget"
  | "scriptObject"
  | "event"
  | "enum"
  | "structure"
  | "alias";

export type CoverageStatus = "typed" | "untyped" | "excluded";

export interface Coverage {
  readonly status: CoverageStatus;
  /** Which upstream typed it: docs, annotations, client, generator or supplements. */
  readonly source: string | undefined;
  /** Why it is untyped or excluded, or how a widget was derived. */
  readonly reason: string | undefined;
}

/** A named member with a Luau type expression: a table field, a structure field or a namespace function. */
export interface Member {
  readonly name: string;
  readonly type: string;
}

export interface Namespace {
  readonly name: string;
  readonly members: readonly Member[];
  /** Nested tables (Constants.AuctionConstants, Enum is modelled separately). */
  readonly tables: readonly Namespace[];
}

export interface Structure {
  readonly name: string;
  /** The `Base & {...}` bases, nearest first. */
  readonly bases: readonly string[];
  readonly fields: readonly Member[];
}

export interface Alias {
  readonly name: string;
  readonly type: string;
}

export interface WidgetType {
  readonly name: string;
  readonly parent: string | undefined;
  /** Methods as `Name` + a function type without `self`: `(a: number) -> string`. */
  readonly methods: readonly Member[];
  /** Script handler names SetScript accepts (from `<Name>ScriptType`), empty for script objects. */
  readonly scripts: readonly string[];
  /** True when `CreateFrame("<name>")` returns this type (it is a key of FrameTypeMap). */
  readonly creatable: boolean;
  readonly section: "widget" | "scriptObject";
}

export interface ApiEvent {
  readonly name: string;
  /** The handler's function type: `(level: number) -> ()`. */
  readonly payload: string;
}

export interface ApiEnum {
  readonly name: string;
  readonly values: readonly string[];
}

export interface GlobalDeclaration {
  readonly name: string;
  readonly type: string;
}

/** Everything parsed from the definitions file, before cross-referencing. */
export interface ParsedDefinitions {
  readonly header: readonly string[];
  readonly events: readonly ApiEvent[];
  readonly aliases: readonly Alias[];
  readonly enumValueTypes: readonly string[];
  readonly structures: readonly Structure[];
  readonly widgets: readonly WidgetType[];
  readonly frameTypes: readonly string[];
  readonly functions: readonly GlobalDeclaration[];
  readonly values: readonly GlobalDeclaration[];
  readonly namespaces: readonly Namespace[];
  readonly enums: readonly ApiEnum[];
  readonly supplementStart: number;
}
