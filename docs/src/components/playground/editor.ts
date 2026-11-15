// CodeMirror 6 wiring for the playground: Lua highlighting, diagnostics as lint, hover types and completion,
// all answered by the in-browser checker.

import type { CompletionContext, CompletionResult } from "@codemirror/autocomplete";
import type { Diagnostic } from "@codemirror/lint";
import type { Extension, Text } from "@codemirror/state";
import type { AnalysisPosition } from "@luau-rs/luau/analysis/worker";

import type { Checker } from "./analysis.ts";

import { autocompletion, closeBrackets } from "@codemirror/autocomplete";
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands";
import { bracketMatching, indentOnInput, indentUnit, StreamLanguage, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { lua } from "@codemirror/legacy-modes/mode/lua";
import { linter, lintGutter } from "@codemirror/lint";
import { drawSelection, highlightActiveLine, hoverTooltip, keymap, lineNumbers } from "@codemirror/view";

export function toPosition(doc: Text, offset: number): AnalysisPosition {
  const line = doc.lineAt(offset);
  return { line: line.number - 1, column: offset - line.from };
}

export function toOffset(doc: Text, position: AnalysisPosition): number {
  const lineNumber = Math.min(Math.max(position.line + 1, 1), doc.lines);
  const line = doc.line(lineNumber);
  return Math.min(line.from + position.column, line.to);
}

export interface EditorHooks {
  readonly checker: () => Checker | undefined;
  readonly onDiagnostics: (count: number) => void;
}

function lintSource(hooks: EditorHooks): Extension {
  return linter(
    async (view) => {
      const checker = hooks.checker();
      if (checker === undefined) {
        return [];
      }
      const doc = view.state.doc;
      const diagnostics = await checker.check(doc.toString());
      hooks.onDiagnostics(diagnostics.length);
      return diagnostics.map(
        (diagnostic): Diagnostic => ({
          from: toOffset(doc, diagnostic.location.begin),
          to: Math.max(toOffset(doc, diagnostic.location.end), toOffset(doc, diagnostic.location.begin)),
          severity: diagnostic.severity,
          message: diagnostic.message,
          source: `Luau ${diagnostic.kind} ${String(diagnostic.code)}`,
        }),
      );
    },
    { delay: 350 },
  );
}

function hoverTypes(hooks: EditorHooks): Extension {
  return hoverTooltip(async (view, pos) => {
    const checker = hooks.checker();
    const word = view.state.wordAt(pos);
    if (checker === undefined || word === null) {
      return null;
    }
    const type = await checker.typeAt(view.state.doc.toString(), toPosition(view.state.doc, pos));
    if (type === undefined) {
      return null;
    }
    return {
      pos: word.from,
      end: word.to,
      above: true,
      create: () => {
        const dom = document.createElement("div");
        dom.className = "pg-hover";
        const code = document.createElement("code");
        code.textContent = `${view.state.sliceDoc(word.from, word.to)}: ${type}`;
        dom.append(code);
        return { dom };
      },
    };
  });
}

function completions(hooks: EditorHooks): (context: CompletionContext) => Promise<CompletionResult | null> {
  return async (context) => {
    const checker = hooks.checker();
    const word = context.matchBefore(/[A-Za-z_][A-Za-z0-9_]*/);
    const trigger = context.matchBefore(/[.:]$/);
    if (checker === undefined || (word === null && trigger === null && !context.explicit)) {
      return null;
    }
    const entries = await checker.complete(context.state.doc.toString(), toPosition(context.state.doc, context.pos));
    return {
      from: word?.from ?? context.pos,
      options: entries.map((entry) => ({
        label: entry.label,
        type: entry.kind === "property" ? "property" : entry.kind === "keyword" ? "keyword" : "variable",
        ...(entry.type === undefined ? {} : { detail: entry.type.length > 80 ? `${entry.type.slice(0, 80)}...` : entry.type }),
        ...(entry.deprecated ? { boost: -10 } : {}),
      })),
      validFor: /^[A-Za-z0-9_]*$/,
    };
  };
}

export function editorExtensions(hooks: EditorHooks): Extension[] {
  return [
    lineNumbers(),
    history(),
    drawSelection(),
    highlightActiveLine(),
    indentOnInput(),
    indentUnit.of("\t"),
    bracketMatching(),
    closeBrackets(),
    StreamLanguage.define(lua),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
    lintGutter(),
    lintSource(hooks),
    hoverTypes(hooks),
    autocompletion({ override: [completions(hooks)], activateOnTyping: true }),
  ];
}
