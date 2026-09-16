# Serverless and managed platforms

Lambda, Cloud Functions, Azure Functions, Cloud Run, App Runner, and the PaaS platforms
that take a container or a zip and run it.

## Authenticate with OIDC, not a stored key

This is the one recommendation to make firmly. Every major cloud supports GitHub's OIDC
federation, which gives the job a short-lived credential scoped to a role:

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::<account>:role/<role>
      aws-region: <region>
```

The equivalents: `google-github-actions/auth` with workload identity federation,
`azure/login` with a federated credential.

There is no long-lived key to store, leak or rotate, and the trust policy can be scoped to
this repo and even this branch. Tell the user what to create on the cloud side - the role,
the trust policy, the permissions - and say plainly that it is their step. Never ask for an
access key to be pasted.

If the user insists on stored keys, that is their call; say once what the tradeoff is and
move on.

## Deploy shapes

| Platform | Artifact | Deploy |
|---|---|---|
| **Lambda** | zip, or a container image in ECR | `aws lambda update-function-code`, or SAM / Serverless Framework / CDK |
| **Cloud Run** | container image in GAR | `gcloud run deploy --image` |
| **Cloud Functions** | source zip | `gcloud functions deploy` |
| **Azure Functions** | zip or image | `azure/functions-action` |
| **App Runner / Fly / Render** | container image | platform CLI or action |

The container-image platforms slot straight into the reuse chain: the deploy is a pointer
update to an image already built and scanned. The zip-based ones need the artifact carried
from the build job - `upload-artifact` / `download-artifact`, never a rebuild.

## Infrastructure as code

If the repo has Terraform, SAM, CDK, Pulumi or a Serverless Framework config, the deploy
goes through that tool, not through a raw CLI call. Ask which, and ask **where the state
lives** - a deploy job that cannot reach the state backend fails in a confusing way.

A Terraform deploy job needs a plan/apply split and usually an approval gate between them.
That is more pipeline than most users expect - flag it rather than writing an unattended
`terraform apply`.

## Ask about

- Which cloud, which region, which account or project per environment.
- OIDC or stored credentials.
- Which environments, in what order, and which need an approval gate (a GitHub Environment
  with required reviewers - a repo setting, not a workflow file).
- Whether the deploy is versioned with aliases or traffic shifting, or a straight replace.
- What proves the deploy worked - a smoke test against the new endpoint is worth adding and
  is usually missing.
- Rollback: alias repoint, previous version redeploy, or nothing.

## Notes

- Lambda zips have a size limit (50 MB zipped direct, 250 MB unzipped); a build that
  exceeds it needs layers or the container route. Worth checking against the build output
  before writing the job.
- Cold-start-sensitive deploys often want a warm-up call after deploy. Ask.
- Never deploy from a topic branch.
