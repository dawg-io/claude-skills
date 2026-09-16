# Anything without a dedicated reference

C, C++, Ruby, PHP, Elixir, shell, Terraform, or anything else. There is no convention here
to fall back on, which makes rule 1 load-bearing: **every command in the pipeline comes
from the interview or from the repo, not from what the ecosystem usually does.**

Say this out loud in the Phase 0 report: the language has no dedicated reference, so its
build and test commands will be asked for rather than inferred.

## What to look for in the repo first

Before asking, read what is already there - it is usually faster and always more accurate:

| Source | What it gives |
|---|---|
| `Makefile` | the real targets. `make -qp \| grep '^[a-zA-Z]'` lists them |
| `justfile`, `Taskfile.yml` | same, for the modern equivalents |
| `CONTRIBUTING.md`, `README.md` | the build and test commands a human is told to run |
| `Dockerfile` | the build steps, already written out |
| `.tool-versions`, `.envrc` | pinned toolchain versions |
| any existing CI config | commands known to have worked |

Present what you found and ask the user to confirm or correct it. A command lifted from the
README is evidence; it is still not a confirmation.

## What to ask, at minimum

One sheet, all of it required - there are no safe prefills:

| Field | Why |
|---|---|
| Toolchain and version | what to install on the runner, and how |
| How the toolchain is installed | a `setup-*` action, a package manager, a container image, or already on a self-hosted runner |
| Build command | |
| Test command, and how failure is reported | exit code is assumed; a tool that always exits 0 needs different handling |
| Lint / static analysis command, if any | |
| Where the build output lands | the path the artifact is collected from |
| Whether the build needs system packages | `apt-get install` steps, or a container |

## Artifacts

Whatever the build produces. The common shapes:

- **Container image** - always available regardless of language, if there is a Dockerfile.
  This is the most reliable answer for an unfamiliar ecosystem, because the image build is
  the same whatever is inside it.
- **Compiled binary or library** - collected from the output path, uploaded as an artifact.
- **OS package** (`.deb`, `.rpm`) - see `deploy/packages.md`.
- **Tar or zip** - the fallback that always works.

## Notes

- **Run the build inside a container** when the toolchain is awkward to install on a
  runner. `container:` on the job, or a build step inside the image. It is more
  reproducible than a pile of `apt-get` steps, and it works identically on self-hosted.
- **Caching** needs the cache path, which is toolchain-specific. Ask for it, or leave
  caching out of the first pass and propose it as a follow-up issue.
- **CodeQL** covers C/C++ and Ruby, and needs the build to run in the workflow. It does not
  cover most other languages - check before writing the job, and say so if it will not work.
- For C/C++ specifically: sanitizer builds (`-fsanitize=address,undefined`) are the highest
  value addition to a CI pipeline and are usually missing. Worth offering.
