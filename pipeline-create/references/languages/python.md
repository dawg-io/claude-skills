# Python

## Detect

`pyproject.toml` (modern), `setup.py`/`setup.cfg` (legacy), `requirements*.txt`, `Pipfile`.
Read `pyproject.toml`'s `[build-system]` to find the backend and `[project]` for the
version and entry points. `[tool.poetry]` means Poetry; `[tool.uv]` or a `uv.lock` means uv.

## Healthy looks like

- A lockfile: `poetry.lock`, `uv.lock`, `Pipfile.lock`, or a pinned `requirements.txt`.
  A bare unpinned `requirements.txt` is not reproducible - flag it.
- A test directory with `pytest` or `unittest` tests, and `pytest` configured in
  `pyproject.toml` or `pytest.ini`.
- A declared Python version - `requires-python` in `pyproject.toml`, or `.python-version`.
- Linter config: `ruff.toml`, `[tool.ruff]`, `.flake8`, or `[tool.black]`.

Missing any of these is a Phase 0 finding with an option, not a stop - except a missing
Python version, which has to be asked for, because the matrix depends on it.

## Commands

Ask which of these the repo actually uses; do not assume the package manager.

| Job | pip / venv | Poetry | uv |
|---|---|---|---|
| Install | `pip install -e ".[dev]"` or `pip install -r requirements.txt` | `poetry install` | `uv sync` |
| Test | `pytest --cov=<pkg> --cov-report=xml` | `poetry run pytest` | `uv run pytest` |
| Lint | `ruff check .` | `poetry run ruff check .` | `uv run ruff check .` |
| Format check | `ruff format --check .` or `black --check .` | | |
| Types | `mypy <pkg>` or `pyright` | | |
| Build | `python -m build` | `poetry build` | `uv build` |

## Setup and caching

```yaml
- uses: actions/setup-python@v5
  with:
    python-version: ${{ matrix.python }}
    cache: pip          # or poetry - needs the lockfile committed
```

`cache:` on `setup-python` needs a lockfile or requirements file at a path it can find; if
the repo has neither, the cache line is a lie and should be left out.

## Version matrix

Ask. Recommend the versions in `requires-python` plus the current stable release. A matrix
across 3-4 versions is normal for a library; a single version is normal for an application
that controls its own runtime.

## Artifacts

| Artifact | When | Registry |
|---|---|---|
| **Container image** | an application or service | GHCR, or wherever it deploys |
| **Wheel + sdist** | a library | PyPI, or a private index / Nexus |
| **Zip / tar** | a script bundle, a Lambda payload | release assets, or S3 |

Recommend the container image for anything deployed, wheels for anything imported.

## Tagging

PyPI versions follow **PEP 440**, which is semver-compatible for normal releases but
differs on pre-releases: `1.4.0rc1`, not `1.4.0-rc.1`. If the repo publishes to a package
index, the tag scheme must be PEP 440 or the upload is rejected. Container tags have no
such constraint.

The version lives in `pyproject.toml` under `[project] version`, unless the repo uses a
dynamic backend (`setuptools-scm`, `hatch-vcs`) that derives it from the git tag. Check
which, and never write a pipeline that bumps a version in a second place.

## Notes

- **Publishing to PyPI should use trusted publishing (OIDC)**, not a long-lived API token.
  It needs `id-token: write` and a one-time configuration on PyPI. Recommend it, and say
  the PyPI side is the user's step.
- Coverage for SonarQube must be `--cov-report=xml`; Sonar cannot read the default format.
- A `Dockerfile` for Python should install from the lockfile, not from `pip install .` -
  worth noting if one is being proposed as an issue.
