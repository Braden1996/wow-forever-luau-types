// Symbol search over every API name: a header button that opens a dialog (Ctrl+. or Cmd+.), or an inline box.
// The index (~20k names) is fetched on first focus from /api/search.json; ranking lives in search-core.ts.
// Results are plain links: Tab reaches them, arrow keys move the highlight, Enter opens the highlighted one.

import type { KeyboardEvent, ReactElement } from "react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { Input, Spinner } from "starlight-warcraft/react";

import type { SearchEntry, SearchKind } from "../../lib/api/indexes.ts";
import { withBase } from "../../lib/site.ts";
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

const SearchPanel = (): ReactElement => {
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

  const kinds = FILTERS[filter]?.[1];
  const hits = useMemo(() => searchSymbols(entries, query, kinds), [entries, query, kinds]);

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
        aria-describedby={`${id}-status`}
        placeholder="C_QuestLog.GetInfo, Button:SetText, PLAYER_LEVEL_UP..."
        value={query}
        onFocus={ensureLoaded}
        onChange={(event) => {
          setQuery(event.target.value);
          setActive(0);
        }}
        onKeyDown={onKeyDown}
        autoComplete="off"
        spellCheck={false}
        className="sym-input"
      />
      <fieldset className="sym-filters">
        <legend className="sr-only">Kinds</legend>
        {FILTERS.map(([label], index) => (
          <button
            key={label}
            type="button"
            className="sym-filter"
            aria-pressed={filter === index}
            onClick={() => {
              setFilter(index);
              setActive(0);
            }}
          >
            {label}
          </button>
        ))}
        <span id={`${id}-status`} className="sym-count" aria-live="polite">
          {state === "loading" && <Spinner className="sym-spinner" />}
          {state === "error" && "The search index failed to load."}
          {state === "ready" && query.length > 0 && `${hits.length} shown`}
        </span>
      </fieldset>
      <ul ref={listRef} className="sym-results" aria-label="Results">
        {hits.map((hit, index) => (
          <li key={`${hit.entry[1]}:${hit.entry[0]}`} data-index={index} data-active={index === active}>
            <a
              href={withBase(hit.entry[2])}
              onMouseEnter={() => {
                setActive(index);
              }}
            >
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

function isShortcut(event: globalThis.KeyboardEvent): boolean {
  return event.key === "." && (event.ctrlKey || event.metaKey) && !event.altKey;
}

interface SymbolSearchProps {
  readonly mode: "inline" | "dialog";
}

export const SymbolSearch = ({ mode }: SymbolSearchProps): ReactElement => {
  const dialogRef = useRef<HTMLDialogElement>(null);

  const show = useCallback(() => {
    // showModal() focuses the first focusable element: the search box, which loads the index on focus.
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
    return <SearchPanel />;
  }
  return (
    <>
      <button type="button" className="sym-open" onClick={show} aria-keyshortcuts="Control+.">
        <span>API</span>
        <kbd className="sym-kbd">Ctrl .</kbd>
      </button>
      <dialog ref={dialogRef} className="sym-dialog" aria-label="Search API symbols">
        <SearchPanel />
        <form method="dialog" className="sym-close">
          <button type="submit" className="sym-filter">
            Close (Esc)
          </button>
        </form>
      </dialog>
    </>
  );
};
