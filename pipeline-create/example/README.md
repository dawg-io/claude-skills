# Example: a repo with no CI, for `pipeline-create` to practise on

A small, working Python service with tests, a linter config and a `Dockerfile` — and
**deliberately no `.github/workflows/`**. That absence is the point: it is the exact state
[`pipeline-create`](../) exists to fix.

Copy it somewhere, run `/pipeline-create` against it, and compare what you get with
[`expected-pipeline/`](expected-pipeline/), which is what a fast-path run produces for this
repo and why.

It is the counterpart to [`pipeline-monitor`](../../pipeline-monitor/), which watches a pipeline that
already exists. This one is about the repo that has nothing yet.

## Files

| Path | What it is |
|---|---|
| `pyproject.toml` | hatchling build, `requires-python = ">=3.11"`, ruff and pytest config. The manifest Phase 0 detects |
| `requirements-dev.txt` | Pinned dev tooling. **Delete it to see the "no lockfile" red flag fire** |
| `src/widgetsvc/` | Stdlib-only widget lookup plus a CLI entry point. No runtime dependencies |
| `tests/` | 8 pytest tests across two files. Real assertions — a placeholder suite is itself a Phase 0 finding |
| `Dockerfile` | Two-stage, non-root, installs the built wheel. Makes "container image" a real answer in Phase 1 |
| `expected-pipeline/` | The seven workflows and the plan a fast-path run writes for this repo |

## Quick start

```bash
cp -r pipeline-create/example ~/widgetsvc && cd ~/widgetsvc
rm -rf expected-pipeline          # it's the answer key — don't let the skill scan it
git init && git add . && git commit -m "Initial commit"

python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt -e .

pytest            # 8 passed
ruff check .      # All checks passed!
docker build -t widgetsvc:dev .
python -m widgetsvc sprocket
```

`/pipeline-create` needs a real remote to push a branch to, so push this to a GitHub repo of
your own before running it — Phases 0–5 work without one, but Phase 6 cannot.

## What the skill should say about it

If the scan comes back differently from this, that is worth reading closely — either the
repo drifted or the skill guessed, and it is not supposed to guess.

- **One language**, Python, at the repo root. Build tool hatchling, from `[build-system]`.
- **Tests exist** and are real, so a test job has something to gate on.
- **A `Dockerfile` exists**, so a container image is available as an artifact without the
  skill having to propose a follow-up issue for a missing file.
- **`requires-python = ">=3.11"`**, so the version matrix is confirmed rather than asked for.
- **No red flags that block.** No competing lockfiles, no committed credentials, no
  placeholder test script, no unparseable existing workflow.
- **Fast path**, therefore: one language, no deployment target, `feature → main`. One
  filled-in sheet, not a twenty-question interview.

## Things to break, to see the other branches

The example is healthy on purpose. Each of these turns it unhealthy in one specific way:

| Change | What Phase 0 should report |
|---|---|
| `rm requirements-dev.txt` | No lockfile — builds are not reproducible. A finding with options, not a stop |
| `touch yarn.lock package-lock.json` and add a `package.json` | Two languages, and competing lockfiles in one tree |
| `rm Dockerfile` | A container image now needs a file that does not exist — a proposed issue, never a `Dockerfile` the skill writes itself |
| `rm -rf tests/` | Nothing to gate on. It should offer either an omitted test job or one that fails until tests exist — not a job that runs zero tests and reports green |
| Add an empty `.github/workflows/ci.yml` | Not greenfield any more. It should ask whether to reuse or ignore before continuing, and never edit that file uninvited |
| `echo "SECRET=hunter2" > .env && git add -f .env` | A committed credential, reported at the top of Phase 0 as a leak needing rotation — with the file named and the value never quoted |

## What was verified

| Check | Result |
|---|---|
| `pytest` (installed here, `PYTHONPATH=src`) | 8 passed |
| `ruff check .` (0.15.8) | All checks passed |
| `ruff format --check .` | 5 files already formatted |
| `docker build` | **not run** — no Docker daemon in the environment this was written in |
| `/pipeline-create` against a real remote | **not run** |
