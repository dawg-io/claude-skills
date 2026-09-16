# Scanning, quality and testing catalog

Phase 3 material. Offer these explicitly rather than waiting to be asked. Leaving security
scanning out is the user's call, but it has to be a call they made, not one they never saw.

## Static analysis and code quality

| Tool | Covers | Needs | Notes |
|---|---|---|---|
| **CodeQL** (`github/codeql-action`) | Go, Java/Kotlin, JS/TS, Python, C#, C/C++, Ruby, Swift | `security-events: write`. Free on public repos; needs GitHub Advanced Security on private | Compiled languages need a build step in the workflow - autobuild often works, but not always |
| **SonarQube / SonarCloud** | most languages, plus coverage and duplication gates | server URL and token as secrets; `sonar-project.properties` or manifest config | Needs the coverage report from the test job, so it chains after tests. A quality gate that fails the build is the point - do not set it to soft-fail |
| **Language linters** | per ecosystem | config file in the repo | See the language reference. If no config exists, propose an issue rather than inventing one |
| **`actionlint`** | the workflows this skill just wrote | nothing | Cheap. Worth adding to the pipeline itself |

## Dependencies and supply chain

| Tool | Covers | Needs |
|---|---|---|
| **Dependabot** (`.github/dependabot.yml`) | version bumps, security advisories | repo config file, not a workflow |
| **Dependency review** (`actions/dependency-review-action`) | new vulnerable or badly-licensed dependencies in a PR diff | `pull_request` trigger; public repo or GHAS |
| **Trivy / Grype** | container image and filesystem CVEs | the built image - so it chains after build and pulls by tag |
| **SBOM** (`anchore/sbom-action`, `syft`) | CycloneDX or SPDX bill of materials | the built artifact. Often required by policy; attach to the release |
| **License check** | dependency licenses against an allowlist | the allowlist, which is a decision to ask about |

Note that Dependabot is a repo config file, not a workflow - if the user wants it, it is a
proposed follow-up issue under Phase 5, since it lives outside `.github/workflows/`.

## Secrets

| Tool | Covers |
|---|---|
| **GitHub secret scanning + push protection** | repo setting, not a workflow. Recommend enabling it; it cannot be set from a file |
| **Gitleaks / TruffleHog** | full history scan in CI, useful where push protection is unavailable |

A full-history scan is slow. Run it on a schedule, not on every push, and say so.

## Runtime and integration

| Kind | What it means | Ask |
|---|---|---|
| **Unit tests** | from the language reference | which command, and whether coverage is collected |
| **Integration tests** | need a database, a broker, a live dependency | service containers, or a real environment? |
| **Health / smoke check** | boot the built artifact and prove it answers | which endpoint, which port, how long to wait |
| **End-to-end** | Playwright, Cypress, Selenium | which browsers, and where the app under test runs |
| **Performance** | k6, JMeter, Locust, Lighthouse | what the thresholds are, and whether a regression fails the build or just reports |

Health checks and performance tests both boot the application, so they bind ports. On a
shared runner they cannot overlap - chain them. On separate runners they can, but keeping
them in one chain means the layout stays correct if the runners change.

## What to recommend by default

The set worth proposing for almost any repo, in the order they should run:

1. Build (produces the artifact everything else consumes)
2. Unit tests with coverage
3. Lint
4. CodeQL
5. Dependency review on PRs
6. Container scan, if the artifact is an image
7. SBOM, at release

Then, only when the repo or the user calls for it: SonarQube, license checks, full-history
secret scanning, performance thresholds, end-to-end tests.

## Where results go

- **SARIF-producing scanners** (CodeQL, Trivy, Gitleaks) upload to the Security tab with
  `github/codeql-action/upload-sarif`. That needs `security-events: write`, and on a
  private repo without GHAS the upload fails - check the repo's visibility from Phase 0
  before writing it in, and say so if it will not work.
- **PR comments** need `pull-requests: write`, and will not work on a fork PR's read-only
  token. Prefer the step summary or a check annotation where fork PRs are expected.
- **Failing the build** is the default for anything that is a gate. A scanner set to
  report-only is fine as an explicit choice, but say clearly in the review which findings
  will not stop a merge.
