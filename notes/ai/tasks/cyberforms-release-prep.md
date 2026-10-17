# cyberForms existing family publication specifications

- Status: sixteen PDFs published and verified; eight per-chain registrations pending.
- Updated: 2026-10-17.
- Authorization: owner authorized the non-SAFO webapp release and template registration, and waived a separate isolated review/testing cycle for this release.
- Base: `2510ff38723f6e084e7399325958220daa859d61`, current `origin/develop` when fetched for execution.
- Branch: `codex/cyberforms-release-prep`.
- Package: `/home/lex/repos/metalex-webapp/output/cyberforms-release-prep-20261017`.

Eight v1.4 specifications and `templates/releases/let-v1.4.json` identify approved combined cyberSPA packets and matching standalone instrument PDFs. All sixteen PDFs are pinned in the dedicated Pinata release group. Returned CIDs and fetched bytes match the frozen manifest and approved SHA-256 values. Global/party field order and plain-text encoding remain unchanged from v1.3.

Fresh registry reads on Ethereum, Base and Arbitrum found all eight new IDs unused and all predecessor field lists equal to the approved payloads. The implementations match the preparation snapshot. Execution evidence, including pinned block numbers and code hashes, is in `release-execution/registry-check-latest.json` in the package. These reads do not reserve IDs.

The owner selected `grantsDeployer`, but its encrypted account requires an unknown password. The empty-password check failed. The owner selected an unlocked browser wallet as the alternative; connection and signing remain pending. No registration transaction has been submitted. Recheck identities and IDs before execution, then verify complete template readbacks before application activation.

No Solidity implementation, ABI, storage, signature, authorization, deployment script or broadcast log is changed. The existing registry entry point supports this legal-text release. SAFO registration, integration and upgrades remain outside scope.

The app release branch is `codex/cyberforms-let-release`, based on current production, in the managed webapp release worktree. It adds v1.4 configurations and defaults while retaining v1.3 saved offerings and custom forms. Typecheck and formatting passed. A separate isolated test/review cycle was not run, as requested. Production merge/deployment remains pending successful registration.
