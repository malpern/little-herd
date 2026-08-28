# Transfer spike 1 — Air → mini

A deliberately small move, run by hand, to find out what breaks before any of
it is built into the app. Nothing here is app code.

## The work

Add one test to `LittleHerdTests/AgentFanLayoutTests.swift`.

`thereIsAlwaysSpaceBetweenThem` only checks the gap in the case where the fan
is centred and unclamped. When a fan is clamped to a window edge the positions
are recomputed from a different origin, and nothing asserts the gap survives
that. Add a test named `theGapSurvivesBeingClampedToAnEdge` that lays a fan out
against the left edge — a centre small enough to force clamping — and asserts
every adjacent pair is exactly `gap` apart, the same way the existing test
does.

## How to know it worked

    xcodebuild test -scheme LittleHerd -destination 'platform=macOS' \
      -only-testing:LittleHerdTests/AgentFanLayoutTests

Nine tests should pass, where there were eight. If the suite does not pass,
stop and leave the branch as it is rather than making the test pass by changing
`AgentFanLayout`.

## What the successor should know

- The repository is `little-herd`, checked out at `~/local-code/little-herd`.
- Work on this branch, `transfer/spike-1`. Commit, and push to origin.
- Commit messages here are prose explaining *why*, in the codebase's voice.
  Read `git log` before writing one.
- There is no uncommitted work travelling with this brief.
- `xcodegen` is only needed when files are added or removed; this adds neither.

## What is being measured

Whether a successor started non-interactively on another machine can pick up a
written brief and finish the work without a person in the loop, and what it
costs to find out.
