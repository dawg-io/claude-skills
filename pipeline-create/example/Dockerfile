# Two stages so the runtime image carries the built wheel and nothing else — no build
# backend, no dev tooling. requirements-dev.txt is deliberately NOT installed here: pytest
# and ruff belong in CI, not in a shipped image.
#
# Honest caveat, since references/languages/python.md tells you to install from the
# lockfile: `python -m build` still resolves hatchling from the network at build time, so
# this is not a fully reproducible build. widgetsvc has no runtime dependencies, which is
# what makes that acceptable here and would not make it acceptable in a real service.
FROM python:3.12-slim AS build
WORKDIR /src
COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir build==1.2.2 && python -m build --wheel --outdir /dist

FROM python:3.12-slim
LABEL org.opencontainers.image.source="https://github.com/dawg-io/claude-skills"
RUN useradd --create-home --uid 10001 widget
COPY --from=build /dist/*.whl /tmp/
RUN pip install --no-cache-dir /tmp/*.whl && rm /tmp/*.whl
USER widget
ENTRYPOINT ["widgetsvc"]
