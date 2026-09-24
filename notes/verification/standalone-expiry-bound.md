# Expiry-bound standalone agreement creation

Baseline: develop `d05b24ff9f808ff0d90b60b4bcef4d12ce59b88d`. User authorized this scoped fix on 2026-09-24. Related application finding: MetaLex-Tech/metalex-webapp PR 1310, V12 run 8281 / F288159 (original severity High; https://v12.sh/runs/8281). This corrects a new creation path; it does not repair or change exposed legacy identities.

## Invariants and implementation

- Existing selectors, ID formulas, signature domains, stored signatures, delegations and legacy templates remain unchanged.
- `createStandaloneContractAndSignExpiryBoundFor` creates and signs atomically. Its domain-separated ID binds template ID, salt, global values, ordered parties, every party-value row and expiry. Secret hash and finalizer are fixed to zero.
- Parties must be nonempty, distinct and nonzero; the first assigned party authorizes creation (existing delegation rules apply). Invalid signatures roll back all state. Exact relaying is harmless; replay cannot reset an existing agreement.
- Public legacy template creation accepts caller-selected IDs. The new path therefore stores templates by agreement ID in a separate mapping, preventing hostile template pre-creation. Agreement signing/details/JSON select this isolated template; legacy `getTemplateDetails` remains in its original namespace. Consumers of new agreements must use agreement details/JSON. `ExpiryBoundContractCreated` identifies the new path. No indexer attribution/configuration changes are included.
- Storage slots 0–9 retain their labels, offsets and types; the isolated template mapping occupies former gap slot 10, and the 39-slot gap begins at 11. Agreement and delegation structures are unchanged.

## Deployment size and renderer

The baseline runtime was 24,366 bytes, only 210 below EIP-170. The initial additive implementation passed unit tests but failed real local deployment with `CreateContractSizeLimit`. Moving the existing read-only JSON renderer unchanged into the linked `AgreementJsonRenderer` library brings the runtime to 23,638 bytes (938 below 24,576). Deployment must link the reviewed renderer; no code-size-limit override is used. The application Anvil acceptance test asserts the size limit and deploys linked artifacts recursively.

## Direct evidence

- Four new regression cases failed against the baseline (missing safe entry point), then passed after implementation: competing legacy expiry creation, changed expiry, changed unsigned-party row and invalid-signature rollback.
- `forge test --match-path test/StandaloneExpiryBoundTest.t.sol` with the repository's OpenZeppelin dependency remappings: **33 passed**, including 24 inherited registry tests and nine new tests.
- New coverage includes hostile template pre-creation, subsequent signing, replay refusal, duplicate/zero/absent parties, missing rows, past expiry, delegated first signature and wrong creator.
- A populated proxy upgraded from the exact baseline fixture preserves byte-for-byte JSON, domain, delegation and signed state, completes a legacy agreement, and creates a new bound agreement.
- `forge inspect ... storage-layout --json` confirms old slots 0–9 and the single reserved-slot consumption. The baseline fixture is the baseline source with only contract-name and import-path adjustments.
- The webapp's isolated Anvil test deploys the linked library/implementation/proxy under normal limits and uses the actual frontend EIP-712 payload and transaction encoding. It covers ordered signatures, simulation/submission, wrong-signer refusal, first-signer retirement, replacement with fresh signatures, second-signature refusal to retire, completion, and competing legacy template/expiry creation.
- Internal review checked the actual diff, all agreement-template read sites, fixture equivalence and exact renderer extraction. This is not independent external review.

## Open release gates

No merge, hosted deployment/upgrade, real signing, external audit or private-code upload is authorized. Independent external review and reviewed deployed-runtime acceptance remain pending. The webapp feature remains OFF and no deployed code hash is newly approved. Legacy exposed requests retain their original identity and residual legacy collision risk; the new path is not a retroactive fix. Hosted authenticated acceptance remains separately pending.
