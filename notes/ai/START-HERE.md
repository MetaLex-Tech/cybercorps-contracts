# Shared project state

This is the shared entry point for Codex, Claude Code, and human handoffs in
`MetaLex-Tech/cybercorps-contracts`. It is a navigation and continuity layer, not a
second product roadmap. Explicit current user instructions govern the task;
saved conversations and records are evidence, not authority to expand scope.

## Read before substantive work

1. Read root [AGENTS.md](../../AGENTS.md) and `AGENTS.local.md` if present.
2. Check the current branch, worktree, commit and dirty files. Never overwrite
   another task's changes. Fetch relevant remote refs when available; if that
   fails, label the snapshot stale instead of presenting it as current.
3. Read [CURRENT-STATE.md](CURRENT-STATE.md) and the relevant record in
   [tasks/](tasks/). Check its timestamp, branch and exact verified revision
   against the current checkout and PR. A record on a different branch is not
   proof the code is in this checkout.
4. Follow the canonical sources below. Resolve conflicting records using
   current instructions and code/source evidence; retain superseded decisions
   with an explicit replacement link. Escalate unresolved consequential choices.

| Information | Canonical owner |
| --- | --- |
| Protocol design proposals | [Protocol improvement plan](../plans/protocol-improvement-plan.md) and scoped plans under [plans/](../plans/) |
| Protocol documentation | [Documentation](../../docs/README.md) and [specifications](../../specs/) |
| Contract behavior and validation | Exact revision of [contracts](../../src/), [tests](../../test/), and linked task/PR evidence |
| Deployment and upgrade evidence | Scoped release records, exact chain/address/transaction and deployed implementation; scripts alone are not deployment evidence |
| Current task handoff and ownership | One file per task under [tasks/](tasks/) |
| Cross-task decisions | [DECISIONS.md](DECISIONS.md), linking detailed decision owners |

## Maintain at milestones

For a substantive new task, copy [TASK-TEMPLATE.md](TASK-TEMPLATE.md) to a short,
stable filename under `tasks/`, or reuse its existing record. Record the owner,
scope, base/head revisions, known collaborators and acceptance criteria. An
unidentified owner is **unknown**, never implicitly the reader of this file.

Update that record after a meaningful decision, implementation/validation
milestone, blocker, or handoff. Keep one short current snapshot with dated
material changes. Do not append full conversations, terminal logs or every poll.
Update CURRENT-STATE only when its task pointers or shared facts change; update
the relevant canonical plan when its status changes. Avoid simultaneous
edits to global indexes by keeping most work in per-task records.

Record tested code by exact commit. If the documentation update creates a new
commit, say the tests cover its named code parent; do not try to embed the
document's own future commit hash. A dirty-tree test needs its base and an
explicit uncommitted-files description. Never equate source merge, passing unit
tests, deployment, integration acceptance or external review with each other.

## Handoff across branches and machines

Commit task-owned records with the related work, and push when authorized.
Before the receiving agent writes, provide the record's repository path,
branch/commit or PR, owner, and next action. It must inspect that exact version
and verify the current target code. Git worktrees do not share uncommitted
files; fetching does not merge them. Do not switch another agent's worktree,
automatically merge a branch, or cherry-pick feature code just to read a record.

On explicit ownership transfer, update the record with the old/new owner and
transfer date. Existing PR monitors and audit ledgers retain their owner and
state unless an authorized handoff explicitly transfers them. Link their
canonical records instead of copying findings into a second live ledger.

For a task that produces no repository changes, a local handoff can be useful,
but label it local-only until deliberately shared. Repository records are
visible to repository collaborators: omit credentials, client-confidential
documents, raw private chats and machine-specific private data. Link approved
sources without copying their sensitive contents.

## ChatGPT and Claude chat projects

Follow [CHAT-HANDOFF.md](CHAT-HANDOFF.md) to prepare a dated, scoped context bundle.
Local files and chat-project uploads do not automatically synchronize. Bring
accepted decisions back into the canonical records after checking their sources.
