# Go

## Detect

`go.mod` - the module path and the Go version are both in it, so the version never has to
be guessed. `go.work` means a workspace: the build tool handles the fan-out, so do not
build a matrix over the modules.

`main` packages under `cmd/*` are the binaries the pipeline produces; find them with
`go list -f '{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./...`.

## Healthy looks like

- `go.sum` committed. Without it the build is not reproducible.
- Tests alongside the code (`*_test.go`). Go has no separate test directory, so absence is
  easy to miss - check with `go list -f '{{.ImportPath}} {{len .TestGoFiles}}' ./...`.
- `.golangci.yml` if linting is expected. Without it, `golangci-lint` uses defaults, which
  is workable but worth confirming.

## Commands

| Job | Command |
|---|---|
| Build | `go build ./...`, or `go build -o dist/<name> ./cmd/<name>` |
| Test | `go test -race -coverprofile=coverage.out ./...` |
| Vet | `go vet ./...` |
| Lint | `golangci-lint run` via `golangci/golangci-lint-action` |
| Format check | `test -z "$(gofmt -l .)"` |
| Tidy check | `go mod tidy && git diff --exit-code go.mod go.sum` |

`-race` on tests is the default recommendation - it catches the class of bug that is
hardest to find later, at the cost of a slower run. Rule 3 says take the slower run.

## Setup and caching

```yaml
- uses: actions/setup-go@v5
  with:
    go-version-file: go.mod     # not a hardcoded version
    cache: true                 # on by default in v5
```

`go-version-file: go.mod` is better than a literal version - one source of truth, and it
cannot drift.

## Artifacts

| Artifact | When | Registry |
|---|---|---|
| **Container image** | a service | GHCR. Go images are tiny - `scratch` or `distroless` |
| **Static binaries** | a CLI, an agent | release assets, one per platform |
| **Both** | common | build once per platform, wrap the linux one in an image |

Cross-compilation is free: `GOOS`/`GOARCH` in a matrix, no toolchain per target. That makes
a multi-platform release matrix cheap and worth recommending for anything CLI-shaped.

For releases, `goreleaser` handles the matrix, checksums, and release assets in one step.
Offer it when the artifact is binaries - it replaces a lot of hand-written YAML.

## Tagging

Go modules require a **`v` prefix**: `v1.4.0`, not `1.4.0`. The module proxy will not
resolve a tag without it. Major versions past v1 also need the major in the module path
(`/v2`), which is a code change, not a pipeline one - flag it if the user wants to release
a v2 and `go.mod` does not say `/v2`.

There is no version in the manifest. The git tag *is* the version, which makes the pipeline
simpler than most: inject it with `-ldflags "-X main.version=${GITHUB_REF_NAME}"`.

## Notes

- Builds are fast enough that a cache miss is rarely painful. Do not over-engineer caching.
- `CGO_ENABLED=0` produces a static binary that runs in `scratch`. If cgo is needed
  (sqlite, some crypto), the image needs a real base - check before recommending distroless.
- CodeQL supports Go and needs the build to run.
