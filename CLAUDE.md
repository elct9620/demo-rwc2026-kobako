# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A **talk demo**: a Rails 8.1 app (Ruby 3.4.7, module `DynamicFlexMessage`) that
runs untrusted mruby inside a **Kobako** WASM sandbox to produce a LINE Flex
Message payload — the message layout is code the sandbox evaluates, not a
template baked into the app.

It exists to be read and shown on stage, not deployed. So the demo is the
smallest thing that makes the idea visible end-to-end: one slice, no
abstraction added before a second caller needs it, no layer the demo cannot
show. Prefer vanilla Rails (`app/models`, Concerns) over a service layer;
prefer deleting a step over generalising it.

## Stack

Modern Rails "no-Redis" defaults — everything is SQLite: four databases
(primary/cache/queue/cable) backed by `solid_cache` / `solid_queue` /
`solid_cable`; Puma behind Thruster. The Web UI is server-rendered HTML with
Hotwire, served by Propshaft; JavaScript ships through **importmap** — there is
no Node toolchain, so no bundler, no CSS framework build step.

## Commands

```bash
bin/setup                                # install gems, prepare DB
bin/ci                                   # full gate (pipeline in config/ci.rb); run before pushing
bin/rails test path/to/file_test.rb:NN   # single test by line
bin/dev                                  # dev server (:3000)
```

## Conventions

- **Style:** `rubocop-rails-omakase` (`.rubocop.yml`); note omakase's spaces
  inside array/hash brackets — `[ a, b ]`.
- **Comments state intent, not process.** A comment carries the *why* of the
  code as it stands now — the constraint it satisfies, the rule it enforces. It
  does not narrate staging or history: no `Phase 1`/`v2` labels, no
  `TODO`/"for now"/"later", no "originally X, changed to Y". When understanding
  changes, rewrite the comment into the fact now true rather than appending a
  patch.
- **Tests:** Minitest + fixtures, E2E-first. A slice needs at least one test
  that walks the whole path through the real entry points and asserts the final
  observable outcome — the sandbox ran, the Flex Message JSON came back — never
  stopping at an intermediate redirect or pinning a mid-step return value.
- **The sandbox boundary is the point of the demo.** Guest mruby is untrusted;
  its failures (timeout, resource limit, exception) are values the app handles
  and shows, never host exceptions that leak host detail.

## Workflow

Trunk-based: commit directly to `main`, one concern per commit. Quality is
gated at two cadences — Claude Code hooks (`.claude/`: RuboCop autocorrect per
edit, `bin/rails test` before a turn ends) and `bin/ci` before pushing.
