# Java / Kotlin / JVM

## Detect

`pom.xml` -> Maven. `build.gradle` or `build.gradle.kts` -> Gradle. A `settings.gradle`
listing subprojects, or a `<modules>` block in the POM, means multi-module - one build tool
invocation covers all of it, so do not build a matrix over the modules.

Read the POM or build script for the Java version, the packaging type (`jar`, `war`), and
the distribution management / publishing config.

## Healthy looks like

- A wrapper committed: `mvnw` / `gradlew` plus its `.properties`. Without one the CI build
  uses whatever version the runner has, which is not reproducible - flag it.
- A declared Java version (`maven.compiler.release`, `java.toolchain`, or the Gradle
  `sourceCompatibility`).
- Tests under `src/test/java` with a real framework (JUnit 5, TestNG).
- For Spring Boot, a `spring-boot-maven-plugin` or the Gradle equivalent - that is what
  produces the executable jar.

## Commands

| Job | Maven | Gradle |
|---|---|---|
| Build | `./mvnw -B package -DskipTests` | `./gradlew build -x test` |
| Test | `./mvnw -B verify` | `./gradlew test` |
| Lint / static | `./mvnw checkstyle:check spotbugs:check` | `./gradlew checkstyleMain spotbugsMain` |
| Coverage | JaCoCo, bound to `verify` | `./gradlew jacocoTestReport` |
| Publish | `./mvnw deploy` | `./gradlew publish` |

`-B` (batch mode) on Maven, always - interactive output in CI logs is noise.

## Setup and caching

```yaml
- uses: actions/setup-java@v4
  with:
    java-version: '21'
    distribution: temurin
    cache: maven        # or gradle
```

Gradle builds benefit more from `gradle/actions/setup-gradle`, which handles the build
cache and configuration cache properly. Use it when the repo is Gradle.

## Artifacts

| Artifact | When | Registry |
|---|---|---|
| **Container image** | a Spring Boot service, anything deployed | GHCR |
| **Jar** | a library, or a service deployed as a jar | Maven Central, GitHub Packages, or Nexus |
| **War** | deployed to Tomcat or another servlet container | Nexus, or a release asset |

Spring Boot can build its own image with `./mvnw spring-boot:build-image` (buildpacks), no
`Dockerfile` needed. Worth offering when the repo is Boot and has no Dockerfile - it turns
a proposed issue into a config choice.

## Tagging

Maven versions are semver-shaped but `-SNAPSHOT` is special: a snapshot version is mutable
and gets a timestamped filename on deploy. Snapshots belong on the integration branch;
releases must not be snapshots. If the POM version ends in `-SNAPSHOT`, a release build has
to strip it, and that is a decision to ask about - Maven Release Plugin, `versions:set`, or
a CI-supplied `-Drevision`.

## Notes

- JVM builds are slow and cache-sensitive. The dependency cache is worth more here than in
  most ecosystems.
- Publishing to Maven Central needs GPG signing - the key and passphrase are secrets, and
  the whole flow is enough setup that it is worth confirming the user actually wants it
  rather than GitHub Packages or a private Nexus.
- Multi-module: test reports and coverage come from every module. Sonar and the coverage
  gate need aggregating config, which may not exist yet - a finding if it does not.
- CodeQL on Java needs the project to compile in the workflow. Autobuild usually manages
  Maven and Gradle, but a build with unusual setup steps needs a manual build command.
