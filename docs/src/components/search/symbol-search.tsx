// Symbol search over every API name: a header button that opens a dialog (Ctrl+. or Cmd+.), or an inline box.
// The index (~20k names) is fetched on first use from /api/search.json; ranking lives in search-core.ts.

import type { KeyboardEvent, ReactElement } from "react";

import type { SearchEntry, SearchKind } from "../../lib/api/indexes.ts";

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";

import { withBase } from "../../lib/site.ts";
import { Input } from "../warcraftcn/input.tsx";
import { Spinner } from "../warcraftcn/spinner.tsx";
import { loadSearchIndex } from "./load-index.ts";
import { KIND_LABELS, searchSymbols } from "./search-core.ts";

type LoadState = "idle" | "loading" | "ready" | "error";

const FILTERS: ReadonlyArray<readonly [string, ReadonlySet<SearchKind> | undefined]> = [
  ["All", undefined],
  ["Functions", new Set<SearchKind>(["function", "method"])],
  ["Types", new Set<SearchKind>(["widget", "structure", "alias", "enum"])],
  ["Events", new Set<SearchKind>(["event"])],
  ["Namespaces", new Set<SearchKind>(["namespace"])],
];

interface ResultsProps {
  readonly mode: "inline" | "dialog";
}

const SearchPanel = ({ mode }: ResultsProps): ReactElement => {
  const id = useId();
  const [entries, setEntries] = useState<readonly SearchEntry[]>([]);
  const [state, setState] = useState<LoadState>("idle");
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState(0);
  const [active, setActive] = useState(0);
  const listRef = useRef<HTMLUListElement>(null);

  const ensureLoaded = useCallback(() => {
    if (state !== "idle") {
      return;
    }
    setState("loading");
    loadSearchIndex().then(
      (loaded) => {
        setEntries(loaded);
        setState("ready");
      },
      () => {
        setState("error");
      },
    );
  }, [state]);

  useEffect(() => {
    if (mode === "dialog") {
      ensureLoaded();
    }
  }, [mode, ensureLoaded]);

  const kinds = FILTERS[filter]?.[1];
  const hits = useMemo(() => searchSymbols(entries, query, kinds), [entries, query, kinds]);

  useEffect(() => {
    setActive(0);
  }, [query, filter]);

  useEffect(() => {
    listRef.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: "nearest" });
  }, [active]);

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>): void => {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      setActive((index) => Math.min(index + 1, hits.length - 1));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      setActive((index) => Math.max(index - 1, 0));
    } else if (event.key === "Enter") {
      const hit = hits[active];
      if (hit !== undefined) {
        window.location.assign(withBase(hit.entry[2]));
      }
    }
  };

  return (
    <div className="sym-search">
      <label htmlFor={id} className="sr-only">
        Search API symbols
      </label>
      <Input
        id={id}
        type="search"
        role="combobox"
        aria-expanded={hits.length > 0}
        aria-controls={`${id}-results`}
        aria-activedescendant={hits.length > 0 ? `${id}-hit-${active}` : undefined}
        placeholder="C_QuestLog.GetInfo, Button:SetText, PLAYER_LEVEL_UP..."
        value={query}
        onFocus={ensureLoaded}
        onChange={(event) => {
          setQuery(event.target.value);
        }}
        onKeyDown={onKeyDown}
        autoComplete="off"
        spellCheck={false}
        autoFocus={mode === "dialog"}
        className="w-full"
      />
      <div className="sym-filters" role="group" aria-label="Kinds">
        {FILTERS.map(([label], index) => (
          <button
            key={label}
            type="button"
            className="sym-filter"
            aria-pressed={filter === index}
            onClick={() => {
              setFilter(index);
            }}
          >
            {label}
          </button>
        ))}
        {state === "loading" && <Spinner className="size-5" />}
        {state === "error" && <span className="sym-error">The search index failed to load.</span>}
        {state === "ready" && query.length > 0 && <span className="sym-count">{hits.length} shown</span>}
      </div>
      <ul ref={listRef} id={`${id}-results`} role="listbox" className="sym-results" aria-label="Results">
        {hits.map((hit, index) => (
          <li
            key={`${hit.entry[1]}:${hit.entry[0]}`}
            id={`${id}-hit-${index}`}
            role="option"
            aria-selected={index === active}
            data-index={index}
            onMouseEnter={() => {
              setActive(index);
            }}
          >
            <a href={withBase(hit.entry[2])}>
              <code>{hit.entry[0]}</code>
              <span className="sym-kind">{KIND_LABELS[hit.entry[1]]}</span>
              {hit.entry[3] === 1 && <span className="api-chip api-chip-untyped">untyped</span>}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
};

interface SymbolSearchProps {
  readonly mode: "inline" | "dialog";
}

function isShortcut(event: globalThis.KeyboardEvent): boolean {
  return event.key === "." && (event.ctrlKey || event.metaKey) && !event.altKey;
}

export const SymbolSearch = ({ mode }: SymbolSearchProps): ReactElement => {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);

  const show = useCallback(() => {
    setOpen(true);
    dialogRef.current?.showModal();
  }, []);

  useEffect(() => {
    if (mode !== "dialog") {
      return undefined;
    }
    const onKey = (event: globalThis.KeyboardEvent): void => {
      if (isShortcut(event)) {
        event.preventDefault();
        show();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [mode, show]);

  if (mode === "inline") {
    return <SearchPanel mode="inline" />;
  }
  return (
    <>
      <button type="button" className="sym-open" onClick={show} aria-keyshortcuts="Control+.">
        <span>API</span>
        <kbd className="sym-kbd">Ctrl .</kbd>
      </button>
      <dialog
        ref={dialogRef}
        className="sym-dialog"
        aria-label="Search API symbols"
        onClose={() => {
          setOpen(false);
        }}
        onClick={(event) => {
          if (event.target === dialogRef.current) {
            dialogRef.current.close();
          }
        }}
      >
        {open && <SearchPanel mode="dialog" />}
      </dialog>
    </>
  );
};
