# Package registries and OS packages

For repos where "deployed" means "published to a registry something else consumes", and for
`.rpm`/`.deb` artifacts that land on a package server.

## Language package registries

| Ecosystem | Public | Private options | Auth |
|---|---|---|---|
| npm | npmjs.com | GitHub Packages, Verdaccio, Nexus, Artifactory | granular token, or OIDC trusted publishing |
| PyPI | pypi.org | devpi, Nexus, Artifactory, CodeArtifact | **OIDC trusted publishing** - recommend over a token |
| Maven | Central | GitHub Packages, Nexus, Artifactory | user + token; Central also needs GPG signing |
| NuGet | nuget.org | GitHub Packages, Azure Artifacts | API key |
| crates.io | crates.io | a private registry | token. **Publishes are permanent** - gate it |
| Go | the module proxy | none needed | none - a git tag is the publish |

**Prefer OIDC trusted publishing** wherever the registry supports it (PyPI, npm). It needs
`id-token: write` and a one-time configuration on the registry side, and there is no
long-lived credential to leak or rotate. Say clearly that the registry-side setup is the
user's step.

**GitHub Packages** needs no new secret - `GITHUB_TOKEN` with `packages: write` covers it.
That makes it the low-friction default for a private package, and worth offering when the
consumer is also on GitHub.

## Publishing gates

A publish is usually irreversible - crates.io cannot be replaced, npm unpublish is limited,
Maven Central is permanent. So:

- Publish from a **tag**, not from a branch push.
- Put a GitHub Environment with required reviewers in front of it. That is a repo setting
  the user creates; name it in the review.
- Publish the artifact that was already built and scanned. Never rebuild in the publish
  job - see rule 2.

## OS packages

| Artifact | Build | Where it goes |
|---|---|---|
| `.rpm` | `rpmbuild`, or `nfpm` from a config file | a yum/dnf repo, Nexus, or a release asset |
| `.deb` | `dpkg-deb`, `fpm`, or `nfpm` | an apt repo, Nexus, or a release asset |

`nfpm` builds both from one small YAML file and needs no packaging toolchain on the runner.
Recommend it over hand-rolled `rpmbuild` spec files unless the repo already has a spec.

Publishing to a self-hosted yum/apt repo is usually: upload the package, then run
`createrepo_c` or `reprepro` on the repo host. Ask how the repo is served and how the index
is regenerated - it is often an SSH step, same shape as `compose.md`.

Signing: a package repo that verifies signatures needs a GPG key as a secret. Tell the user
what is needed; never generate a key.

## Ask about

- Which registry, and whether the repo already publishes anywhere - check `.npmrc`,
  `distributionManagement` in the POM, `[[registries]]` in Cargo config, `nuget.config`.
- Public or private, and who consumes it.
- Whether a publish should be automatic on tag, or gated behind an approval.
- Prerelease handling - does an `rc` version publish, and to what channel or dist-tag.
- For OS packages: which distributions and versions, since that decides the build container.

## Notes

- The version in the manifest and the git tag must agree, or the publish ships the wrong
  version. Decide which is the source of truth in Phase 2 and enforce it in the publish job
  with a check, not a comment.
- A failed publish halfway through a multi-artifact release leaves a partial release. Ask
  whether that matters; if it does, publish everything or nothing, which usually means one
  job doing all the publishes.
