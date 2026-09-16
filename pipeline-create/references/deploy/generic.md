# Deploy targets without a dedicated reference

Tomcat, LAMP, systemd services, Windows services, Nexus-fed installers, an appliance
image, an internal platform, or anything else. Rule 1 applies hardest here: **every step
comes from the interview, not from a guess about how that platform usually works.**

Say so in the review: the target has no dedicated reference, so the deploy job was written
from the user's description and should be read closely before it runs.

## The questions that define any deploy

Ask all of these. There are no safe prefills.

| Question | Why it matters |
|---|---|
| What receives the artifact? | a host, a cluster, a registry, an appliance |
| How does it get there? | SSH/SCP, an agent, an API call, a pull from a registry, a git commit |
| Does the pipeline push, or does the target pull? | decides whether CI holds a credential at all |
| What credential does that need, and what is the least-privileged form? | this is what goes in the review's secrets table |
| What restarts or reloads the service? | `systemctl restart`, a servlet container redeploy, an API call |
| How do you know it worked? | an endpoint, a log line, an exit code. Without this the job reports success on delivery, not on running |
| How do you roll back? | previous artifact, previous symlink, a snapshot, or nothing |
| Which environments, in what order, which are gated? | approval gates are GitHub Environments - a repo setting |

If the user cannot answer "how do you know it worked", that is a finding worth raising:
a deploy job with no verification reports green whether or not the service came up.

## Shapes that recur

**Push over SSH** - the most common. Copy the artifact, run a command, verify. See
`compose.md` for the credential handling; it is identical whatever the artifact is. Prefer
a self-hosted runner on the target host where one exists - no credential to store.

**Drop into a watched directory** - Tomcat's `webapps/`, a spool directory, an autodeploy
path. The copy is the deploy; verification is a health check, and it needs a wait because
the container picks the file up asynchronously.

**API call** - an internal platform with a deploy endpoint. A token as a secret, a `curl`,
and then polling for the result. Ask what the endpoint returns and what "finished" looks
like, because a 202 is not a successful deploy.

**Pull** - the target polls a registry or a repo. The pipeline's job ends at publishing;
there is no deploy step and no credential. The best shape when it is available.

## Notes

- **Never invent a deploy command.** If the answer to "what restarts the service" is
  unclear, stop and ask. A wrong restart command runs unattended on a real host.
- Ask for a dedicated deploy account with only the access the deploy needs - not root, not
  a personal login. Name what it needs in the review; never create it.
- **Never deploy from a topic branch.** Pushing the pipeline branch in Phase 6 fires
  matching triggers, so a deploy job that matches `feature/*` would fire on this skill's
  own push.
- If the target needs a file the repo does not have - a systemd unit, a Tomcat context
  descriptor, an installer manifest - propose the issue, do not write the file.
