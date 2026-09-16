# .NET

## Detect

`*.sln`, `*.csproj`, `*.fsproj`, `*.vbproj`. A solution file lists the projects; build the
solution, not each project. `global.json` pins the SDK version - use it if present.

The `TargetFramework` in the csproj gives the runtime (`net8.0`, `net9.0`). `OutputType`
`Exe` versus `Library` tells you whether the artifact is an application or a package.

## Healthy looks like

- `global.json` pinning the SDK, or the target framework consistent across projects.
- A test project (`*.Tests.csproj`) referencing xUnit, NUnit or MSTest.
- `Directory.Build.props` or `Directory.Packages.props` for centrally managed versions -
  their absence is not a problem, but with them the version has one home.
- `packages.lock.json` if lock files are enabled. Not the default in .NET, so absence is
  normal - but mention that builds are not fully reproducible without it.

## Commands

| Job | Command |
|---|---|
| Restore | `dotnet restore` |
| Build | `dotnet build --no-restore -c Release` |
| Test | `dotnet test --no-build -c Release --collect:"XPlat Code Coverage"` |
| Format check | `dotnet format --verify-no-changes` |
| Publish | `dotnet publish -c Release -o out` |
| Pack | `dotnet pack -c Release -o nupkgs` |

Chain `restore` -> `build --no-restore` -> `test --no-build`. Letting each step
re-restore and rebuild is the ecosystem's most common wasted CI time, and it violates
rule 2 within a single job.

## Setup and caching

```yaml
- uses: actions/setup-dotnet@v4
  with:
    global-json-file: global.json     # or dotnet-version:
- uses: actions/cache@v4
  with:
    path: ~/.nuget/packages
    key: nuget-${{ hashFiles('**/*.csproj', '**/packages.lock.json') }}
```

`setup-dotnet` has no built-in NuGet cache, so it is an explicit `actions/cache` step.

## Artifacts

| Artifact | When | Registry |
|---|---|---|
| **Container image** | a web app or service | GHCR. `dotnet publish /t:PublishContainer` builds one with no Dockerfile |
| **NuGet package** | a library | nuget.org, GitHub Packages, or a private feed |
| **Self-contained binary** | a CLI, or a deploy with no runtime installed | release assets. `-r <rid> --self-contained` |
| **Zip of `publish/`** | deploying to App Service or IIS | release asset |

`dotnet publish /t:PublishContainer` is worth offering when the artifact is an image and
there is no Dockerfile - it turns a proposed issue into a build flag.

## Tagging

NuGet versions are semver with a NuGet-specific twist on prereleases (`1.4.0-rc.1` sorts
correctly, but `1.4.0-rc1` and `1.4.0-rc.1` are different versions). The version lives in
the csproj as `<Version>`, or centrally in `Directory.Build.props`.

CI-supplied versions go in as `-p:Version=${VERSION}` rather than editing the file - one
source of truth, and no commit needed to release.

## Notes

- Coverage comes out as Cobertura from `XPlat Code Coverage`, in a GUID-named subdirectory.
  Sonar and coverage reporters need the path, so a glob or `--results-directory` is needed.
- Windows-only projects (WPF, WinForms, full Framework) need `windows-latest`, which is
  more expensive and slower. Ask whether the target framework is cross-platform before
  writing `ubuntu-latest`.
- CodeQL supports C#, and needs the build to run in the workflow.
