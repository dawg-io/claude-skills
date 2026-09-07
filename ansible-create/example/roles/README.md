# roles/

## Prefer a public, validated role over writing your own

Before adding anything here, check whether a maintained role already does the job.
A public role has had its edge cases found by more people than you will find alone —
`geerlingguy.docker` in `requirements.yml` is an example. Pin it and move on.

Write a custom role only when nothing suitable exists, or when what you need is genuinely
specific to this fleet. `chrony/` is here as the pattern to copy, not because chrony has no
public role — it does.

Prefix project-specific custom roles with the project name (`acme-billing-api`), so they
never collide with something installed from Galaxy.

## Layout

```
roles/<role-name>/
  defaults/main.yml     every tunable, prefixed with the role subject, commented
  tasks/main.yml        the work
  handlers/main.yml     restarts, named exactly as the notify: string
  templates/*.j2        config files
  meta/main.yml         galaxy_info and dependencies
```

Role directories are kebab-case; groups in the inventory are snake_case.

Do not commit `ansible-galaxy init` boilerplate — empty `files/`, `vars/`, a stub
`meta/main.yml` with placeholder text. Delete what the role does not use.

## House rules the linter will not enforce

- **Every tunable in `defaults/main.yml`, prefixed and commented.** An undefined variable is
  a hard failure at run time — ansible's default, no `ansible.cfg` setting needed — rather
  than an empty string in a config file. That is the behaviour you want; give it somewhere
  to land.
- **No `command:`/`shell:` where a module exists.** An unqualified `command` reports changed
  on every run forever, which makes the play useless for spotting real drift. Where it is
  genuinely unavoidable, add `creates:`, `removes:` or `changed_when:`.
- **Handlers for restarts**, named as the exact `notify:` string. A typo means the handler
  silently never fires and the config change never takes effect.
- **Never a literal secret.** Use an empty default plus an `assert` that fails on the
  placeholder, or a vault reference. Add `no_log: true` to any task handling a token.
- **Vars belong in the role, not in vaulted `group_vars/`.** A vaulted group_vars file is
  decrypted whenever any member of that group appears in *any* play — including the nightly
  `common.yml`. Scope a secret with `vars_files` in the one playbook that needs it.
