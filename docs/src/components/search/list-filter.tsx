// Filters a server-rendered list in place: hides `[data-filter-name]` items in `#<target>` that do not match.
// The list stays plain HTML (indexable, works without JavaScript); this island only toggles `hidden`.

import type { ChangeEvent, ReactElement } from "react";

import { useCallback, useId, useState } from "react";

import { Input } from "../warcraftcn/input.tsx";

interface ListFilterProps {
  readonly target: string;
  readonly label: string;
  readonly total: number;
}

function applyFilter(target: string, query: string): number {
  const root = document.getElementById(target);
  if (root === null) {
    return 0;
  }
  const needle = query.trim().toLowerCase();
  let shown = 0;
  for (const item of root.querySelectorAll<HTMLElement>("[data-filter-name]")) {
    const match = needle.length === 0 || (item.dataset["filterName"] ?? "").toLowerCase().includes(needle);
    item.hidden = !match;
    shown += match ? 1 : 0;
  }
  for (const group of root.querySelectorAll<HTMLElement>("[data-filter-group]")) {
    group.hidden = group.querySelector("[data-filter-name]:not([hidden])") === null;
  }
  return shown;
}

export const ListFilter = ({ target, label, total }: ListFilterProps): ReactElement => {
  const id = useId();
  const [shown, setShown] = useState(total);
  const onChange = useCallback(
    (event: ChangeEvent<HTMLInputElement>) => {
      setShown(applyFilter(target, event.target.value));
    },
    [target],
  );
  return (
    <div className="api-filter not-content">
      <label htmlFor={id} className="sr-only">
        {label}
      </label>
      <Input id={id} type="search" placeholder={label} onChange={onChange} autoComplete="off" spellCheck={false} />
      <span className="api-filter-count" aria-live="polite">
        {shown === total ? `${total}` : `${shown} of ${total}`}
      </span>
    </div>
  );
};
