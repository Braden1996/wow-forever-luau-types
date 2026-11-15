--!strict
-- One unit case: `run` returns the actual value and the expected one; scripts/unit.luau compares them as JSON.

export type Case = { name: string, run: () -> (unknown, unknown) }

return nil
