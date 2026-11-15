// A small reader for the Luau type expressions the generator emits. It is not a general Luau parser: the
// definitions file is generated, one declaration per line, so splitting at depth 0 is enough.

export type TokenKind = "type" | "builtin" | "name" | "string" | "punct" | "space";

export interface Token {
  readonly kind: TokenKind;
  readonly text: string;
}

const BUILTINS = new Set([
  "any",
  "boolean",
  "buffer",
  "never",
  "nil",
  "number",
  "string",
  "thread",
  "unknown",
  "vector",
  "keyof",
  "index",
  "typeof",
  "self",
]);

const IDENT = /[A-Za-z_][A-Za-z0-9_]*/y;
const SPACE = /\s+/y;
const STRING = /"(?:[^"\\]|\\.)*"/y;

function readAt(pattern: RegExp, text: string, at: number): string | undefined {
  pattern.lastIndex = at;
  const match = pattern.exec(text);
  return match?.[0];
}

function nextNonSpace(text: string, at: number): string | undefined {
  for (let i = at; i < text.length; i += 1) {
    const char = text[i];
    if (char !== " " && char !== "\t") {
      return char;
    }
  }
  return undefined;
}

/** Splits a type expression into tokens; identifiers followed by `:` are names (parameters, fields). */
export function tokenize(expr: string): Token[] {
  const tokens: Token[] = [];
  let at = 0;
  while (at < expr.length) {
    const space = readAt(SPACE, expr, at);
    if (space !== undefined) {
      tokens.push({ kind: "space", text: space });
      at += space.length;
      continue;
    }
    const str = readAt(STRING, expr, at);
    if (str !== undefined) {
      tokens.push({ kind: "string", text: str });
      at += str.length;
      continue;
    }
    const ident = readAt(IDENT, expr, at);
    if (ident !== undefined) {
      const after = nextNonSpace(expr, at + ident.length);
      let kind: TokenKind = "type";
      if (after === ":") {
        kind = "name";
      } else if (BUILTINS.has(ident)) {
        kind = "builtin";
      }
      tokens.push({ kind, text: ident });
      at += ident.length;
      continue;
    }
    const arrow = expr.startsWith("->", at) ? "->" : undefined;
    const dots = expr.startsWith("...", at) ? "..." : undefined;
    const punct = arrow ?? dots ?? expr.charAt(at);
    tokens.push({ kind: "punct", text: punct });
    at += punct.length;
  }
  return tokens;
}

/** The identifiers an expression uses in type position (deduplicated, in order). */
export function referencedTypes(expr: string): string[] {
  const seen = new Set<string>();
  for (const token of tokenize(expr)) {
    if (token.kind === "type") {
      seen.add(token.text);
    }
  }
  return [...seen];
}

/** Splits at `separator` where no bracket is open (`->` does not close an angle bracket). */
export function splitTopLevel(expr: string, separator: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let inString = false;
  let start = 0;
  for (let i = 0; i < expr.length; i += 1) {
    const char = expr.charAt(i);
    if (inString) {
      if (char === "\\") {
        i += 1;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }
    if (char === '"') {
      inString = true;
    } else if (char === "(" || char === "{" || char === "<" || char === "[") {
      depth += 1;
    } else if (char === ">" && expr.charAt(i - 1) === "-") {
      // `->` is an arrow, not a closing angle bracket.
    } else if (char === ")" || char === "}" || char === ">" || char === "]") {
      depth -= 1;
    } else if (depth === 0 && expr.startsWith(separator, i)) {
      parts.push(expr.slice(start, i).trim());
      start = i + separator.length;
      i += separator.length - 1;
    }
  }
  parts.push(expr.slice(start).trim());
  return parts.filter((part) => part.length > 0);
}

/** Removes one pair of parentheses that wraps the whole expression. */
export function stripOuterParens(expr: string): string {
  const trimmed = expr.trim();
  if (!trimmed.startsWith("(") || !trimmed.endsWith(")")) {
    return trimmed;
  }
  let depth = 0;
  for (let i = 0; i < trimmed.length; i += 1) {
    const char = trimmed.charAt(i);
    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
      if (depth === 0 && i < trimmed.length - 1) {
        return trimmed;
      }
    }
  }
  return trimmed.slice(1, -1).trim();
}

export interface Parameter {
  /** Undefined for an unnamed parameter or a variadic. */
  readonly name: string | undefined;
  readonly type: string;
  readonly optional: boolean;
  readonly variadic: boolean;
}

export interface FunctionShape {
  readonly generics: string | undefined;
  readonly params: readonly Parameter[];
  readonly returns: string;
}

function findMatchingParen(expr: string, open: number): number {
  let depth = 0;
  for (let i = open; i < expr.length; i += 1) {
    const char = expr.charAt(i);
    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
      if (depth === 0) {
        return i;
      }
    }
  }
  return -1;
}

function parseParameter(raw: string): Parameter {
  if (raw.startsWith("...")) {
    const rest = raw.slice(3).trim();
    const type = rest.startsWith(":") ? rest.slice(1).trim() : rest;
    return { name: undefined, type, optional: false, variadic: true };
  }
  const colon = splitTopLevel(raw, ":");
  const named = colon.length > 1 && /^[A-Za-z_][A-Za-z0-9_]*$/.test(colon[0] ?? "");
  const type = named ? colon.slice(1).join(":").trim() : raw.trim();
  return {
    name: named ? colon[0] : undefined,
    type,
    optional: type.endsWith("?"),
    variadic: false,
  };
}

/** Reads `<K>(a: T, b: U?) -> R`; returns undefined when the expression is not a function type. */
export function parseFunctionType(expr: string): FunctionShape | undefined {
  let text = stripOuterParens(expr);
  let generics: string | undefined;
  if (text.startsWith("<")) {
    const close = text.indexOf(">");
    generics = text.slice(1, close);
    text = text.slice(close + 1).trim();
  }
  if (!text.startsWith("(")) {
    return undefined;
  }
  const close = findMatchingParen(text, 0);
  const rest = text.slice(close + 1).trim();
  if (close < 0 || !rest.startsWith("->")) {
    return undefined;
  }
  const inner = text.slice(1, close).trim();
  const params = inner.length === 0 ? [] : splitTopLevel(inner, ",").map(parseParameter);
  return { generics, params, returns: rest.slice(2).trim() };
}

/** Overloads are emitted as `((a) -> b) & ((c) -> d)`; a plain function type is one overload. */
export function functionOverloads(expr: string): FunctionShape[] {
  const parts = splitTopLevel(expr, "&");
  const shapes = parts.map((part) => parseFunctionType(part));
  if (shapes.some((shape) => shape === undefined)) {
    const single = parseFunctionType(expr);
    return single === undefined ? [] : [single];
  }
  return shapes.filter((shape): shape is FunctionShape => shape !== undefined);
}

/** True when the type is the untyped placeholder `(...unknown) -> (...unknown)`. */
export function isUntypedFunction(expr: string): boolean {
  return expr.replaceAll(/\s+/g, "") === "(...unknown)->(...unknown)";
}
