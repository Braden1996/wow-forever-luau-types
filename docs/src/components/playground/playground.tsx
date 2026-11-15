// The playground island: a CodeMirror editor checked against the WoW: Forever definitions in a Web Worker.
// Code is kept in the URL hash (#code=...) so a snippet can be shared without a server.

import type { ReactElement } from "react";

import type { Checker } from "./analysis.ts";

import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { useEffect, useRef, useState } from "react";

import { Button } from "../warcraftcn/button.tsx";
import { Spinner } from "../warcraftcn/spinner.tsx";
import { createChecker } from "./analysis.ts";
import { editorExtensions } from "./editor.ts";
import { DEFAULT_EXAMPLE, EXAMPLES } from "./examples.ts";

type Status = "loading" | "ready" | "error";

function encode(code: string): string {
  const bytes = new TextEncoder().encode(code);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function decode(value: string): string | undefined {
  try {
    const binary = atob(value.replaceAll("-", "+").replaceAll("_", "/"));
    return new TextDecoder().decode(Uint8Array.from(binary, (char) => char.charCodeAt(0)));
  } catch {
    return undefined;
  }
}

function initialCode(): string {
  const match = /^#code=(.+)$/.exec(window.location.hash);
  return (match?.[1] === undefined ? undefined : decode(match[1])) ?? DEFAULT_EXAMPLE;
}

export const Playground = (): ReactElement => {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | undefined>(undefined);
  const checker = useRef<Checker | undefined>(undefined);
  const [status, setStatus] = useState<Status>("loading");
  const [error, setError] = useState("");
  const [diagnostics, setDiagnostics] = useState<number | undefined>(undefined);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const parent = host.current;
    if (parent === null) {
      return undefined;
    }
    const editor = new EditorView({
      parent,
      state: EditorState.create({
        doc: initialCode(),
        extensions: [
          ...editorExtensions({ checker: () => checker.current, onDiagnostics: setDiagnostics }),
          EditorView.updateListener.of((update) => {
            if (update.docChanged) {
              window.history.replaceState(null, "", `#code=${encode(update.state.doc.toString())}`);
            }
          }),
        ],
      }),
    });
    view.current = editor;
    let disposed = false;
    createChecker().then(
      (created) => {
        if (disposed) {
          created.dispose();
          return;
        }
        checker.current = created;
        setStatus("ready");
        // Re-run the linter now that the checker exists.
        editor.dispatch({ changes: { from: 0, insert: "" } });
      },
      (reason: unknown) => {
        setError(reason instanceof Error ? reason.message : String(reason));
        setStatus("error");
      },
    );
    return () => {
      disposed = true;
      checker.current?.dispose();
      checker.current = undefined;
      editor.destroy();
    };
  }, []);

  const load = (code: string): void => {
    const editor = view.current;
    editor?.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: code } });
  };

  const share = (): void => {
    navigator.clipboard.writeText(window.location.href).then(
      () => {
        setCopied(true);
        window.setTimeout(() => {
          setCopied(false);
        }, 1500);
      },
      () => {
        setCopied(false);
      },
    );
  };

  return (
    <div className="pg not-content">
      <div className="pg-toolbar">
        <label className="pg-examples">
          <span>Example</span>
          <select
            defaultValue=""
            onChange={(event) => {
              const example = EXAMPLES.find((entry) => entry.id === event.target.value);
              if (example !== undefined) {
                load(example.code);
              }
            }}
          >
            <option value="" disabled>
              Choose...
            </option>
            {EXAMPLES.map((example) => (
              <option key={example.id} value={example.id}>
                {example.label}
              </option>
            ))}
          </select>
        </label>
        <Button type="button" variant="frame" className="pg-share" onClick={share}>
          {copied ? "Link copied" : "Copy link"}
        </Button>
        <span className="pg-status" aria-live="polite">
          {status === "loading" && (
            <>
              <Spinner className="size-5" /> Loading the checker (WASM, about 5 MB once)...
            </>
          )}
          {status === "error" && `The checker failed to start: ${error}`}
          {status === "ready" &&
            (diagnostics === undefined
              ? "Checking..."
              : diagnostics === 0
                ? "No problems: strict mode, new type solver"
                : `${diagnostics} ${diagnostics === 1 ? "problem" : "problems"}`)}
        </span>
      </div>
      <div ref={host} className="pg-editor" />
    </div>
  );
};
