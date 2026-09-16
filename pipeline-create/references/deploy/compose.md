# Docker Compose and single-host deploys

The common homelab and small-service shape: an image in a registry, a compose file on a
host, and a pipeline that tells the host to pull and restart.

## The deploy step

The pipeline does not run compose - the host does. Three routes:

| Route | Shape | Notes |
|---|---|---|
| **SSH** | `ssh host 'cd /srv/app && docker compose pull && docker compose up -d'` | Simplest. Needs a key as a secret |
| **Self-hosted runner on the host** | the runner *is* the host; run compose locally | No credential at all. Best option when it applies |
| **Watchtower / pull-based agent** | the pipeline only pushes the image; the host polls | No inbound access needed |

If a self-hosted runner already lives on the target host, recommend it - there is no
credential to store and nothing to expose.

## The SSH route

```yaml
- name: Deploy
  env:
    SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
    HOST: ${{ vars.DEPLOY_HOST }}
  run: |
    install -m 600 /dev/stdin "$RUNNER_TEMP/key" <<< "$SSH_KEY"
    ssh -i "$RUNNER_TEMP/key" -o StrictHostKeyChecking=accept-new \
      "$HOST" 'cd /srv/app && docker compose pull && docker compose up -d --remove-orphans'
```

Tell the user what to create: a dedicated deploy user on the host, key-only, with access to
just that compose project - not root, and not their own login key. Say it plainly in the
Phase 5 review: "you need to create an SSH keypair, put the public half in the deploy
user's `authorized_keys`, and add the private half as `DEPLOY_SSH_KEY`."

`StrictHostKeyChecking=accept-new` trusts the host on first connect. Pinning the host key
in a secret is stricter; offer it and let the user choose.

## Ask about

- Where the compose file lives - this repo, the host, or a separate config repo. **If it
  does not exist, do not write one.** Propose the issue.
- Whether the compose file references the image by a moving tag (`:latest`, `:develop`) or
  gets rewritten with the immutable tag on each deploy. The moving tag is simpler; the
  immutable tag is what makes a rollback possible. Recommend the immutable tag.
- How many hosts, and whether the deploy is sequential.
- Rollback: `docker compose up -d` with the previous tag. Only works if the tag is
  immutable and still in the registry - another reason to recommend it.
- Whether the service needs a health check after restart, and what URL proves it is up.

## Notes

- `docker compose pull` before `up -d` is what makes the deploy actually take the new
  image. Without the pull, a moving tag already present locally is reused silently.
- `--remove-orphans` cleans up containers dropped from the file. Ask before adding it -
  it removes containers, and on a shared compose project that is destructive.
- LAMP, Tomcat, and plain systemd deploys are the same shape: the pipeline publishes an
  artifact, an SSH step tells the host to fetch and restart it, and a health check proves
  it worked. See `packages.md` if the artifact is a package rather than an image.
