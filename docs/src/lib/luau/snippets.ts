// Build-time type checking of the site's Luau code blocks, in the manner of TypeScript's Twoslash: every ```luau block
// is checked against the generated definitions by Luau's own checker (luau-web-checker, the release luau-lsp uses,
// new solver, strict mode), and every identifier's type is kept for the hover cards.
//
// Conventions inside a block:
//   -- ---cut---      lines above it are checked but not shown (a hidden prelude, as Twoslash's `// ---cut---`)
//   ... -- error      the line must have a type or syntax error (shown underlined, with the message on hover);
//                     no other line may have one, so an example that stops compiling fails the build
// Lint warnings (unused locals and the like) are ignored: examples are fragments.
// A block with a top-level `declare` is a definitions file (an addon's `addon.d.luau`): it is shown as written, since
// definitions cannot be loaded into a checker that has started checking. tests/pass covers real ones.

/** Whether a block is a definitions file rather than a module. */
export function isDefinitionsFile(code: string): boolean {
  return /^declare\s/mu.test(code);
}

import type { Checker, Diagnostic, Hover } from "luau-web-checker";

export const CUT = "-- ---cut---";

/** `-- error` or `-- error: why`, as the end-of-line comment that marks an expected error. */
const ERROR_MARK = /--\s*error\b/u;

const ERROR_KINDS: ReadonlySet<string> = new Set(["TypeError", "SyntaxError", "InternalCompilerError"]);

export interface CheckedSnippet {
  /** How many lines at the top are hidden (the prelude and the cut line). */
  readonly hidden: number;
  /** The errors, with lines counted in the shown code (1-based). */
  readonly errors: readonly Diagnostic[];
  /** Each shown identifier with its type, lines counted in the shown code. */
  readonly hovers: readonly Hover[];
}

/** A code block that does not check as it claims to; the message lists every problem. */
export class SnippetError extends Error {
  constructor(problems: readonly string[], code: string) {
    super(`Luau code block does not type-check as marked:\n  ${problems.join("\n  ")}\n--- code ---\n${code}`);
    this.name = "SnippetError";
  }
}

function shift<T extends Diagnostic | Hover>(entry: T, hidden: number): T {
  return { ...entry, line: entry.line - hidden, endLine: entry.endLine - hidden };
}

/**
 * Checks one code block. `checker` must already have the definitions; the block is added as module `name` and removed
 * again afterwards.
 *
 * @throws SnippetError when an unmarked line has an error or a marked line has none.
 */
export function checkSnippet(checker: Checker, name: string, code: string): CheckedSnippet {
  const lines = code.split("\n");
  const cutIndex = lines.findIndex((line) => line.trim() === CUT);
  const hidden = cutIndex === -1 ? 0 : cutIndex + 1;
  // The cut line becomes a blank line, so positions in the checked source equal positions in the block.
  const source = cutIndex === -1 ? code : lines.map((line, index) => (index === cutIndex ? "" : line)).join("\n");

  checker.setSource(name, source);
  try {
    const errors = checker.check(name).filter((diagnostic) => ERROR_KINDS.has(diagnostic.kind));
    const hovers = checker.hovers(name);

    const marked = new Set(lines.flatMap((line, index) => (ERROR_MARK.test(line) ? [index + 1] : [])));
    const problems: string[] = [];
    for (const error of errors) {
      if (error.line <= hidden) {
        problems.push(`hidden prelude, line ${String(error.line)}: ${error.kind}: ${error.message}`);
      } else if (!marked.has(error.line)) {
        problems.push(`line ${String(error.line - hidden)}: ${error.kind}: ${error.message}`);
      }
    }
    for (const line of marked) {
      if (line <= hidden) {
        problems.push(`hidden prelude, line ${String(line)}: an "-- error" mark belongs in the shown code`);
      } else if (!errors.some((error) => error.line === line)) {
        problems.push(`line ${String(line - hidden)} is marked "-- error" but has no error`);
      }
    }
    if (problems.length > 0) {
      throw new SnippetError(problems, code);
    }

    return {
      hidden,
      errors: errors.map((error) => shift(error, hidden)),
      hovers: hovers.filter((hover) => hover.line > hidden).map((hover) => shift(hover, hidden)),
    };
  } finally {
    checker.removeSource(name);
  }
}
