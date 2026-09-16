# Detection

How Phase 0 works out what is in the repo. Detect from files that exist, not from
extension counts alone - a repo with 400 `.js` files and no `package.json` is a static
site, not a Node project.

## Manifest to language

| Manifest | Language | Reference |
|---|---|---|
| `pom.xml`, `build.gradle`, `build.gradle.kts` | Java / Kotlin / JVM | `languages/java.md` |
| `package.json` | Node / TypeScript / frontend | `languages/node.md` |
| `pyproject.toml`, `setup.py`, `requirements.txt`, `Pipfile` | Python | `languages/python.md` |
| `go.mod` | Go | `languages/go.md` |
| `*.csproj`, `*.sln`, `*.fsproj` | .NET | `languages/dotnet.md` |
| `Cargo.toml` | Rust | `languages/rust.md` |
| `CMakeLists.txt`, `Makefile`, `configure.ac`, `meson.build` | C / C++ | `languages/generic.md` |
| `Gemfile` | Ruby | `languages/generic.md` |
| `composer.json` | PHP | `languages/generic.md` |
| `mix.exs` | Elixir | `languages/generic.md` |
| `Dockerfile` alone | not a language - a packaging choice | `deploy/registry.md` |

Anything not listed goes to `languages/generic.md`, and the report must say so: the
language has no dedicated reference, so its build and test commands come from the
interview rather than from a known convention. Never fill them in from what the ecosystem
"usually" does.

## Where each language lives

Record the *directory* each manifest was found in, not just the language. It drives:

- `paths:` filters on triggers, so a docs change does not run a full build
- `working-directory:` on every step
- whether one workflow or several make sense
- how the artifacts relate (one image, or one per component)

Common layouts:

| Shape | Looks like | Usually means |
|---|---|---|
| Single | one manifest at the root | one build, one artifact |
| Front + back | `frontend/package.json` + `backend/pyproject.toml` | two builds, often two images, one deploy |
| Monorepo | several manifests under `packages/*`, `services/*`, `apps/*` | matrix build, per-path triggers, independent versioning is a question to ask |
| Workspace | one root manifest declaring members (`go.work`, npm workspaces, Cargo workspace, Gradle multi-project) | one build tool call, several artifacts |

A workspace is not a monorepo for pipeline purposes - the build tool already handles the
fan-out, so do not build a matrix that fights it. Check for the workspace declaration
before concluding the repo is a monorepo.

## Useful scan commands

```bash
# manifests, excluding vendored trees
find . -maxdepth 4 \
  \( -name node_modules -o -name vendor -o -name .git -o -name target -o -name dist \) -prune -o \
  \( -name 'pom.xml' -o -name 'build.gradle*' -o -name 'package.json' \
     -o -name 'pyproject.toml' -o -name 'setup.py' -o -name 'requirements*.txt' \
     -o -name 'go.mod' -o -name '*.csproj' -o -name '*.sln' -o -name 'Cargo.toml' \
     -o -name 'CMakeLists.txt' -o -name 'Gemfile' -o -name 'composer.json' \) -print

# packaging and deploy hints. NOT `ls Dockerfile*` at the root - in a polyglot repo
# the Dockerfiles live per component, and a root-only check reports "no Dockerfile"
# about a file that is sitting in frontend/.
find . -maxdepth 4 -name .git -prune -o \( -name 'Dockerfile*' -o -name 'Containerfile' \
  -o -name 'docker-compose*.y*ml' -o -name 'Chart.yaml' -o -name 'kustomization.y*ml' \
  -o -name 'serverless.yml' -o -name 'template.yaml' \) -print 2>/dev/null

# competing lockfiles, per component directory
for d in $(find . -maxdepth 3 -name package.json -not -path '*/node_modules/*' -exec dirname {} \;); do
  n=$(ls "$d"/package-lock.json "$d"/yarn.lock "$d"/pnpm-lock.yaml "$d"/bun.lockb 2>/dev/null | wc -l)
  [ "$n" -gt 1 ] && echo "CONFLICT: $d has $n lockfiles"
done

# credentials committed to the repo - tracked files only, so a gitignored .env is not a hit.
# Note what is deliberately NOT anchored: `credentials` matches aws-credentials and
# gcp-credentials.json, which a (^|/)credentials$ anchor silently misses. Private keys are
# matched by extension because .key is by far the most common one in a real leak.
git ls-files | grep -Ei '(^|/)(\.env$|\.env\.[^.]*$|.*\.(pem|p12|pfx|key|jks|p8|ppk|keystore)$|id_(rsa|dsa|ecdsa|ed25519)$|.*credentials.*|.*\.tfvars$|.*\.kubeconfig$|kubeconfig$)'

# placeholder test scripts that will report green forever.
# The guard is not optional: with no package.json in the repo the command substitution
# expands to nothing, grep gets zero file arguments and falls back to reading stdin - which
# hangs the scan on every non-Node repo. Same shape for any `grep $(git ls-files ...)`.
pkgs=$(git ls-files '*package.json')
[ -n "$pkgs" ] && grep -l '"test"[[:space:]]*:[[:space:]]*"\(echo\|exit 0\|true\)' $pkgs 2>/dev/null

# existing CI, and other CI systems worth knowing about
ls .github/workflows/ 2>/dev/null
ls Jenkinsfile .gitlab-ci.yml .circleci/ azure-pipelines.yml .drone.yml 2>/dev/null

# what the repo already tags with
git tag --sort=-v:refname | head -20   # -v:refname, not -creatordate: tags cut in the
                                       # same second tie and fall back to alphabetical
git branch -r | head -30
```

Existing tags and remote branches are the cheapest evidence of the branch model and
versioning scheme the team already uses. Read them before Phase 2 and use them as the
prefill - then still confirm, because a repo's history is not a commitment.

## Red flags

A red flag is anything the code says that contradicts writing a working pipeline. Derive
them from what is actually there; each language reference names what a healthy repo in
that ecosystem looks like. These are the shapes that recur:

| Finding | Why it matters | Options to offer |
|---|---|---|
| No test suite | Nothing to gate on. A "test" job that runs zero tests is worse than none - it reports green | Write the pipeline with the test job omitted and an issue to add tests, or with a placeholder job that fails until tests exist |
| No lockfile | Builds are not reproducible; the same commit builds differently next week | Commit a lockfile first (small fix, usually one command), or accept non-reproducible builds and say so in the report |
| Two lockfiles for one manifest | `package-lock.json` + `yarn.lock` + `pnpm-lock.yaml`; the pipeline will pick one and it may not be the one that works | Ask which is authoritative, delete the others in a separate PR |
| Build tool config missing | The manifest exists but there is no way to invoke a build | Stop. This is unwritable - the user has to say what the build command is, or fix the repo |
| Wants a container image, no `Dockerfile` | Build job has nothing to build | Propose the issue. The workflow can be written against the expected path, but it will fail until the file exists - say so |
| Credential committed | A live secret in the repo is a leak, not a config problem | Report it as a finding at the top of the Phase 0 output, name the file, recommend rotation. Never quote the value |
| Existing workflow does not parse | It will keep failing alongside anything new | Ask whether to leave it, or open an issue |
| Language with no manifest at all | Nothing to detect a build from | Ask, or drop that language from the pipeline with the user's agreement |
| Generated or vendored code in tree | Scanners will flag third-party code as the repo's own | Ask which paths to exclude, and set the exclusions in the scanner config the workflow calls |

Every row above has a scan command in this file. Do not report a red flag as "none
found" unless the command that finds it actually ran - an unchecked category is "not
checked", not "clean".

**A red flag stops the skill only when it makes the pipeline unwritable** - no build
command, no manifest to work from, a repo that cannot build. Everything else is reported
with options and the interview continues.
