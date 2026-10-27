# AGENTS.md — ansible/

This directory is a draft of a future standalone repository that provisions
the ADM machine (`ssh yandex-cloud-adm`) for operating a Yandex Cloud k8s
cluster and for hosting an agent runtime (candidate: ecc,
https://github.com/aal-zwork/ecc).

## Scope boundaries

- This repo only installs/configures tooling and k8s scaffolding. It does
  **not** create or rotate secrets — that lives in the sibling `secrets/`
  repo. Roles here only *consume* secrets already placed in `pass`/S3 by
  `secrets/`.
- `Makefile` here never knows about ADM and never wraps commands in its own
  `ssh ...` call. What it runs is `ansible-playbook`, and `ansible-playbook`
  itself is the remote-execution layer: it connects to the `adm` inventory
  host over ssh and applies changes *there*, regardless of where `make`/
  `ansible-playbook` was invoked from. So `make workspace`/`update`/`upgrade`
  can be run straight from a laptop (control node) — it still configures
  ADM, not the laptop. Contrast with `secrets/Makefile`, whose scripts run
  plain bash locally with no remote-execution layer — see
  `secrets/AGENTS.md` and `../docs/os-toolchain.md`.
- GPG master key generation and VM key issuance are strictly out of scope
  for this repo (see `secrets/gpg/master/` and `secrets/AGENTS.md`).

## Provider abstraction

- `group_vars/all.yml` holds the single switch `cloud_provider: yandex_cloud`.
- All provider-specific logic (CLI install, auth, k8s credentials, S3 CLI
  config) lives under `roles/providers/<name>/`. Generic roles
  (`k8s_cluster_access`, `ephemeral_runtime_dir`, `gnupg_pass`,
  `agent_runtime_scaffold`) must stay provider-agnostic and only delegate via
  `include_role`/`import_role` using `cloud_provider`.
- Adding a new provider = add `roles/providers/<new-name>/` with the same
  task-file set (`install_cli.yml`, `authenticate.yml`, `get_k8s_credentials.yml`,
  `s3_config.yml`) and a matching `secrets/providers/<new-name>/` on the
  secrets side. Do not touch generic roles to add a provider.
- See `../docs/provider-abstraction.md` for the full contract.

## Makefile conventions

- Targets: `ping` (read-only connectivity check via the ansible `ping`
  module, no confirmation prompt), `workspace` (full bootstrap,
  `bootstrap.yml`), `update` (`update.yml`, light refresh), `upgrade`
  (`upgrade.yml`, bump pinned tool versions).
- Every target that mutates state must print what it is about to do and ask
  for confirmation (`read -p "Apply? [y/N] "`), unless
  `GANIEVRF_MAKE_ASK_SKIP=yes` is set (automation mode — skip the prompt).
- `Makefile` targets a Ubuntu/GNU Make environment (that's what ADM runs).
  On macOS the same Makefile must still work: a small `_detect-os` target
  (a dependency of every real target) picks `gmake`/`gsed`/`ggrep` on macOS
  via Homebrew, and GNU tools directly on Ubuntu. It also prints which
  `make` binary/version is actually running (`$(MAKE_VERSION)`/`$(MAKE)`)
  and warns if invoked as plain `make` on Darwin instead of `gmake` — macOS
  ships an old GNU Make 3.81 as `/usr/bin/make`, which may parse this file
  but isn't the version this repo targets. Keep `_detect-os` trivial and
  side-effect-free — it runs on every invocation.
- See `../docs/os-toolchain.md` for the exact detection recipe.

## When adding a role

- Keep provider-specific code inside `roles/providers/<name>/` only.
- Any secret a role needs must be read from `pass` (already populated by the
  `secrets/` repo before this role runs) — never hardcode or re-derive
  secrets inside `ansible/`.
- Prefer idempotent tasks; `workspace`/`update`/`upgrade` must all be safe to
  re-run.
