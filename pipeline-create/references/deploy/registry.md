# Container registries and image builds

The default handoff for almost any deployed artifact. If the user is undecided about
artifacts, this is the one to steer toward: the registry is the reuse mechanism, the
immutable tag is the provenance, and every downstream job is a `docker pull`.

## Registry choice

| Registry | When | Auth in CI |
|---|---|---|
| **GHCR** (`ghcr.io`) | default for a GitHub repo | `GITHUB_TOKEN` with `packages: write`. No secret to create |
| Docker Hub | public distribution, existing account | username + PAT as secrets |
| Cloud-native (ECR, GAR, ACR) | deploying into that cloud | OIDC federation, no long-lived key |
| Self-hosted (Harbor, Nexus, registry:2) | homelab, air-gapped | username + password as secrets, plus a CA cert if self-signed |

GHCR needs no secret at all, which is a real advantage - recommend it unless the deploy
target argues otherwise.

## Build

```yaml
- uses: docker/setup-buildx-action@v3
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
- name: Compute the immutable reference
  id: ref
  run: |
    set -euo pipefail
    # Two things this line is doing, both load-bearing:
    #   ${VAR,,}     GHCR rejects an uppercase path, and github.repository preserves the
    #                owner's casing - MyOrg/MyService pushes fail with
    #                "repository name must be lowercase".
    #   ${VAR::7}    the short SHA. patterns.md and gitflow.md both specify sha-<short>,
    #                and a downstream retag reconstructs it the same way - push the full
    #                40-char SHA here and every promotion fails with "manifest unknown".
    echo "image=ghcr.io/${GITHUB_REPOSITORY,,}:sha-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

- uses: docker/build-push-action@v6
  with:
    push: true
    tags: ${{ steps.ref.outputs.image }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

`docker/metadata-action` generates the tag set from the event, which is cleaner than
hand-writing the tag logic - offer it once there is more than one tag.

## Tagging and promotion

Always push an **immutable** tag (`sha-<short>`, `pr-<n>`) alongside any moving one. The
immutable tag is what downstream jobs pull; without it they have to rebuild.

**Promotion is a retag, never a rebuild.** Moving an image from `pr-142` to `develop`, or
`develop` to `1.4.0`:

```bash
docker buildx imagetools create \
  --tag ghcr.io/owner/repo:1.4.0 \
  ghcr.io/owner/repo:sha-a1b2c3d
```

No pull, no rebuild, no new layers - the digest is identical, so the thing that was scanned
is provably the thing being shipped. `regctl` and `crane` do the same.

## Multi-arch

Needed for arm64 targets - a Raspberry Pi, Graviton, Apple silicon. `docker/setup-qemu-action`
plus `platforms: linux/amd64,linux/arm64` on the build. Emulated arm64 builds are slow;
a native arm64 runner is much faster if one is available. Ask which before writing it in.

## Ask about

- Which registry, and whether the repo already pushes anywhere.
- Public or private image, and who needs to pull it.
- Whether a `Dockerfile` exists. If not: **do not write one**. Propose the issue, note that
  the build job will fail until it exists. Some ecosystems can build an image without one
  (Spring Boot buildpacks, `dotnet publish /t:PublishContainer`, `ko` for Go) - offer that
  route where it applies.
- Retention. Registries fill up with `pr-*` and `sha-*` tags; a cleanup policy or a
  scheduled prune workflow is worth proposing.

## Notes

- **A fork PR gets a read-only `GITHUB_TOKEN`** and cannot push to GHCR. On a public repo
  expecting fork PRs, the PR path has to build without pushing, and the reuse chain breaks
  there by necessity - say so rather than writing a job that will fail.
- Scan the image after it is built and before it is promoted. See `scanning.md`.
- On a persistent self-hosted runner, set a per-job `DOCKER_CONFIG` - see `patterns.md`.
