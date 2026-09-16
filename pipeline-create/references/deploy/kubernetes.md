# Kubernetes

## The first question: push or pull

This decides the entire deploy job, so ask it before anything else.

**Push** - the pipeline holds cluster credentials and applies directly (`kubectl`, `helm
upgrade`). Simple, immediate, and it means a CI token can write to the cluster. Fine for a
homelab or a dev cluster; a real credential exposure risk for production.

**Pull / GitOps** - a controller in the cluster (Flux, Argo CD) watches a repo and
reconciles. The pipeline never touches the cluster; it updates an image tag in a manifest
repo and opens a commit or PR. More moving parts, but the cluster credential never leaves
the cluster, and the deployed state is auditable in git.

Recommend pull for anything production. Say why: the pipeline holding a cluster-admin
credential is the single largest blast radius in most CI setups.

## Manifest tooling

| Tool | Detect | Deploy step |
|---|---|---|
| Plain manifests | `*.yaml` with `kind:` | `kubectl apply -f` |
| Kustomize | `kustomization.yaml` | `kustomize edit set image`, then apply or commit |
| Helm | `Chart.yaml` | `helm upgrade --install`, or update `values.yaml` in a repo |
| Flux | `.flux.yaml`, `flux-system/` | commit the new tag; or let Flux's image automation do it |
| Argo CD | `Application` CRs | commit the new tag; Argo syncs |

If none of these exist in the repo, **do not write manifests**. Ask where they live - very
often it is a separate repo, which changes the deploy job into a cross-repo commit and
needs a token with write access to that repo.

## The push shape

```yaml
- uses: azure/setup-kubectl@v4
- env:
    # Through env:, never inlined into the script. `${{ }}` substitutes before bash parses
    # the line, so a kubeconfig containing a backtick or $(...) - legitimate in an `exec`
    # credential plugin block - would run as a command on the runner.
    KUBECONFIG_DATA: ${{ secrets.KUBECONFIG }}
    # Short SHA, matching what registry.md publishes. A deploy that names a tag
    # the build never pushed fails with ImagePullBackOff minutes later.
    IMAGE: ghcr.io/owner/repo:sha-${{ steps.ref.outputs.short_sha }}
  run: |
    set -euo pipefail
    # install -m 600, not `echo >`: a plain redirect creates the file at the umask default
    # (0644), and echo mangles backslashes.
    install -m 600 /dev/stdin "$RUNNER_TEMP/kubeconfig" <<< "$KUBECONFIG_DATA"
    kubectl --kubeconfig="$RUNNER_TEMP/kubeconfig" \
      set image deployment/app "app=$IMAGE"
    kubectl --kubeconfig="$RUNNER_TEMP/kubeconfig" \
      rollout status deployment/app --timeout=5m
```

`rollout status` is not optional - without it the job reports success the moment the API
accepts the change, whether or not a single pod started. Set `--timeout` and let a stalled
rollout fail the job.

Never write the kubeconfig to the workspace, and never `cat` it.

Both snippets here assume a `short_sha` computed earlier in the job, the same value
`registry.md` builds the image reference from:

```yaml
- id: ref
  run: echo "short_sha=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
```

Whatever the tag scheme ends up being, the deploy has to name the tag the build actually
pushed. The mismatch does not fail the pipeline - it fails the rollout, as an
`ImagePullBackOff` minutes later with nothing pointing back at the cause.

## The pull shape

The pipeline's job ends at updating a tag:

```yaml
- env:
    IMAGE_TAG: sha-${{ steps.ref.outputs.short_sha }}
  run: |
    set -euo pipefail
    # actions/checkout configures no committer identity, so `git commit` aborts with
    # "Author identity unknown" and exit 128 - and because the original of this snippet
    # chained the push with &&, the deploy then silently never happened.
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    cd deploy
    kustomize edit set image "app=ghcr.io/owner/repo:${IMAGE_TAG}"
    git commit -am "deploy: app ${IMAGE_TAG}"
    # Two merges landing close together both push to the same branch; without this the
    # second is rejected as non-fast-forward and that deploy is lost.
    git pull --rebase
    git push
```

Ask whether the update is a direct commit or a PR. A PR gives an approval gate for free,
which is usually what production wants.

## Ask about

- Push or pull, per environment.
- Which manifests, and whether they live in this repo or another one.
- Which environments and namespaces, in what order, and which need a manual approval gate.
  Approval gates are GitHub **Environments** with required reviewers - a repo setting the
  user has to create, not something a workflow file can declare.
- How the cluster is authenticated: a kubeconfig secret, OIDC to a cloud provider, or a
  cluster-side controller.
- Rollback: what happens when `rollout status` fails. `kubectl rollout undo`, or leave it
  broken and alert.

## Notes

- Ask for a **namespaced ServiceAccount scoped to what the deploy actually needs**, not
  cluster-admin. Tell the user what permissions it needs; do not create it.
- OIDC (`id-token: write`) beats a stored kubeconfig wherever the cloud provider supports
  it - short-lived credential, nothing to rotate.
- Never deploy from a topic branch. If the plan has a deploy job firing on a `feature/*`
  push, that is a bug in the plan.
