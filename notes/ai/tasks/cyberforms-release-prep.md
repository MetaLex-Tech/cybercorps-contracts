# cyberForms existing family publication specifications

- Status: local preparation complete, unpublished/unregistered.
- Updated: 2026-10-17.
- Authorization: existing-family spec/app release preparation and precise SAFO scope proposal; no publication or deployment.
- Base: `2510ff38723f6e084e7399325958220daa859d61`, freshly fetched `origin/develop`.
- Branch: `codex/cyberforms-release-prep`.
- Package: `/home/lex/repos/metalex-webapp/output/cyberforms-release-prep-20261017`.

Eight v1.4 specs and `templates/releases/let-v1.4.json` identify the approved combined cyberSPA packets and matching standalone instrument PDFs. Offline CAR roots reproduce the exact PDF bytes. Global/party field order and plain-text encoding match the predecessor registration script, available predecessor specs and live registry reads on all five checked chains. The old Reg S SAFTE markdown is absent; its shared SAFTE schema was verified against the actual script/caller and onchain template instead.

All eight new IDs were unused at the pinned read blocks recorded in `qa/registry-preflight.json`. This does not reserve them. Every proposed registration calldata item round-tripped through the existing createTemplate ABI. No transaction was sent. Fresh pin/fetch verification, registry identity/ID checks and readback on each target chain precede later activation.

No Solidity implementation, test, ABI, storage, signature, authorization, deployment script or broadcast log was changed in this branch. No protocol upgrade is proposed for the existing-family legal revision. App changes live in the separate managed webapp release worktree on the same branch name. Existing registrations/custom forms are preserved, and active pickers remain v1.3.

Independent internal app/spec review passed after fixing a webapp configuration-order regression. The package contains exact validation receipts and a separate proposed SAFO integration/upgrade scope. SAFO extension implementation remains at `e294600d97210f2265cf45bb2d69abdcdb79d93f`; no new SAFO core implementation, registration or deployment is part of this spec branch.

Remaining release gates: external review required by AGENTS.local, target-company runtime verification and isolated affected-flow acceptance, publication approval, per-chain registration, deliberate frontend activation and source-library refresh. None is claimed by local preparation.
