# Architecture Decision Records

One file per decision, numbered in the order the decision was *made*, not the
order it was written down. Format: context, decision, consequences — including
the ones we did not like. An ADR that lists only upside is marketing copy.

| # | Decision | Status |
|---|---|---|
| 0001 | Argo CD (pull-based) over `kubectl apply` from CI | backfill pending |
| 0002 | IRSA and GitHub OIDC instead of long-lived AWS keys | backfill pending |
| 0003 | Community Terraform modules over hand-rolled ones | backfill pending |
| 0004 | [Secrets and identifier handling](0004-secrets-and-identifier-handling.md) | accepted |

**On the gap at 0001–0003.** Those decisions were made in May 2026 and are
already implemented; they are backfills, and the numbering keeps them in the
order they actually happened rather than the order someone got around to
typing them up. The reasoning is preserved in the original design spec, which
now lives outside this repo — it was tooling output, not project documentation.

## Template

```markdown
# NNNN — <decision in one line>

**Status:** proposed | accepted | superseded by NNNN
**Date:** YYYY-MM-DD

## Context
What forced a decision. Constraints that were real at the time.

## Decision
What we chose, stated so someone can disagree with it.

## Consequences
What this makes easy, what it makes hard, and what we gave up.
```
