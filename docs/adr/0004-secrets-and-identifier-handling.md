# 0004 — Secrets and identifier handling in a public repository

**Status:** accepted
**Date:** 2026-09-07

## Context

This repository is public, and it provisions real AWS infrastructure. That
combination puts three different classes of value under the same "don't commit
it" instinct, even though they need different handling:

1. **Credentials** — access keys, webhook URLs, database passwords. Committing
   one is an incident.
2. **Identifiers** — AWS account id, role ARNs, cluster endpoints. Not secret
   in any cryptographic sense; AWS itself prints them in the console and in
   error messages. But an account id enables role-name enumeration and gives a
   support-desk social engineering attempt a concrete handle, so there is no
   reason to publish one.
3. **Configuration that happens to look sensitive** — region, repository name,
   cluster name. Harmless, and hiding it makes the repo harder to read.

The second class is the awkward one. `gitleaks` with its stock ruleset does not
flag account identifiers, because by its definition they are not leaks. A clean
scan therefore says nothing about them.

There is also a structural constraint specific to GitOps. Argo CD is
pull-based: it reads desired state from git and nothing else. Anything the
cluster needs to know must either be in the repository — and therefore public —
or be injected by something outside it. A GitHub Actions secret solves this for
CI and does nothing at all for Argo CD.

## Decision

**No long-lived credentials anywhere.** GitHub Actions authenticates to AWS via
OIDC with trust policies scoped to this repository and to specific refs. There
are no static AWS keys to rotate, and nothing to leak.

**Identifiers are withheld, not treated as secrets.** They are kept out of the
repository, but their exposure is not modelled as a breach. Practically:

- CI reads the account id from the `AWS_ACCOUNT_ID` repository secret.
- Argo CD, which cannot read secrets, gets no such value committed. The image
  registry is injected at bootstrap. The local `kind` path uses a locally
  loaded image and needs no registry at all.
- The chart wraps `image.repository` in Helm's `required`, so an unset value
  fails at render time with the fix in the message, rather than surfacing much
  later as an `ImagePullBackOff` that the operator has to go digging for.

**The scan is extended to cover class 2.** `.gitleaks.toml` adds rules for
account ids in ECR URLs and in ARNs, on top of the default ruleset. It runs in
`make lint-secrets` and in a pre-commit hook installed by `make hooks`.

**On exposure, we rotate or decommission — we do not rewrite history.**
Rewriting a public repository's history does not remove data from GitHub;
orphaned commits stay reachable by SHA until the forge is asked directly to
collect them. A force-push edits the ref graph and produces the *appearance* of
remediation, which is worse than none. The AWS account backing this project is
ephemeral by design — stood up for a recorded demo, then destroyed — so
decommissioning is both the correct response and one already on the schedule.

## Consequences

**The AWS path is not clone-and-run.** It requires a bootstrap step that
supplies the registry. This is a deliberate trade: the alternative is a public
repository that names the account it deploys into. The local `kind` path stays
clone-and-run, and that is the path a reader is asked to try.

**One historical commit carries an account id** and is allowlisted in
`.gitleaks.toml` by SHA. The allowlist is a record, not an exemption: it names
one commit, so anything new is still caught. If that list ever grows past one
entry, the policy above is not being followed.

**The scan runs through git, not over the filesystem.** A directory scan also
reads downloaded dependencies — `.terraform/` modules, vendored subcharts —
which are gitignored, cannot be committed, and are full of example ARNs that
match the rules above. Excluding them by path would mean maintaining a second
copy of `.gitignore` that silently rots. Scanning through git makes the
exclusion structural: if git cannot see a file, it cannot be committed, so it
is not in the threat model.

`make lint-secrets` covers history and staged changes; the pre-commit hook
scans staged changes only, which is the gate that decides what enters the
repository. The gap this leaves — a secret sitting in the working tree,
unstaged — cannot reach GitHub without passing the hook first.

**Identifiers in Terraform state are out of scope here.** State lives in a
private, encrypted, versioned S3 bucket with public access blocked. It is not
in this repository and is treated as sensitive in full.
