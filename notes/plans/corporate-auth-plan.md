# Corporate authority for new deployments

Status: locally implemented and validated, awaiting required independent review, 2026-10-07. Scoped implementation of protocol-improvement-plan P1; legacy migration and last-officer guards are excluded. No merge or production deployment.

## Model

Deploy a company-specific ERC1967 proxy backed by a shared BorgAuthV2 UUPS implementation. Keep legacy BorgAuth and legacy factory entry points available. New companies use independent bitmap memberships: director, officer, board executor, issuance manager, deal manager and round manager. No numeric role or inequality grants a V2 permission. Permission-to-role mappings are fixed in code. Root controls assignments and approved upgrades, with a two-step root transfer; it receives protocol configuration and upgrade permissions but no implicit operational permissions. Root may explicitly assign itself operational membership. The board executor is a contract implementing the company's collective decision process; director membership alone confers no execution authority. Building a voting or multisig system is outside this implementation.

CyberCorp is the sole narrow controller of officer membership. Root and board appoint/remove officers through CyberCorp's roster entry points, avoiding a second independently editable officer roster. Root administers other memberships. Membership updates preserve unrelated bits. There are no configurable adapters or permission-policy registries in this version.

## Permission boundaries

- MANAGE_OFFICERS: board executor, with root as an explicit governance override.
- SIGN_AS_OFFICER and company operations: officer membership.
- CONFIGURE_PROTOCOL and APPROVE_UPGRADE: root only.
- MANAGE_SECURITY_CLASSES: officers and round manager (round creation creates printers).
- ISSUE_SECURITIES: officers, deal manager and round manager.
- ADMINISTER_CERTIFICATES: officers, deal manager and round manager (settlement locks and register operations).
- MANAGE_DEALS and MANAGE_ROUNDS: officers.
- TRANSFER_POLICY: officers; exact configured issuance-manager calls to tokens remain valid.

Preserve self-call paths and investor/agreement signature checks. Configuration setters are root-only. Consumer upgrade gates keep their factory reference checks. BorgAuthV2 upgrades require root and the CyberCorpFactory's approved BorgAuth implementation. Freeze bootstrap privileges before a factory transaction returns. Bind root and board configuration into CREATE2 salts. Reject outdated component implementations on the new deployment path.

## Implementation sequence

1. Define roles, permission constants and a legacy-aware permission checker without changing consumer storage layout.
2. Implement BorgAuthV2, protected initialization/bootstrap, narrow officer-controller hook, two-step root transfer and approved UUPS upgrades.
3. Replace checks in CyberCorp, IssuanceManager, DealManager, RoundManager, certificate and scrip admin paths; update downstream company-auth consumers such as secondary conditions.
4. Add a factory-approved implementation and an explicit new-deployment entry point; retain legacy entry points.
5. Add local behavioral and integration tests, check contract sizes and update this plan/task evidence.

## Acceptance invariants established before implementation

- Officer/director/manager memberships never imply root, board execution or upgrade authority.
- Numeric updateRole, ownership-transfer and adapter APIs cannot escalate V2 authority.
- Root cannot sign as an officer without officer membership. Board membership does not confer officer signing powers.
- CyberCorp officer lifecycle preserves director membership; arbitrary callers cannot invoke its membership hook.
- Only the exact configured issuance manager mints/burns tokens; token admin exceptions require the intended permission.
- Board may appoint/remove/update officers; officers and directors alone are refused.
- Root transfer requires nominee acceptance; stale nominees cannot accept after replacement/cancellation.
- Unauthorized and unapproved upgrades fail; approved upgrades preserve root, memberships and AUTH address.
- Proxy initialization is atomic and cannot replay; implementation initialization is disabled.
- Factory leaves no bootstrap authority and rejects unsafe/incomplete component stacks.
- New and legacy deployments coexist; legacy access tests remain valid.

## Release gates

Unit and local transaction acceptance are separate from required independent external-model review, merge and deployment. This request authorizes implementation/local tests, not sending private code to external services, starting external audits, merging, deploying or signing real transactions. Preserve test-environment sign -> simulate -> submit coverage with explicit success/refusal cases. Record any unavailable gates without claiming release readiness.

## Deployment and client integration

Deploy/link CorporateAuthCheck and CorporateDeploymentLib alongside the existing protocol libraries. Deploy BorgAuthV2 once, then the platform authority publishes it using CyberCorpFactory.setBorgAuthImplementation. Select deployCyberCorpWithGovernance with an explicit nonzero root, board-executor contract and initial officer. The new path deploys the full stack, initializes the authority proxy and hands control to the chosen root in one transaction. Legacy deployment and deploy-and-offer/round entry points keep legacy BorgAuth; they do not automatically opt into this model.

Root is an administrative trust anchor and can ultimately change assignments or approve released code. Prefer a governance multisig or stockholder executor. Supplying a board contract does not prove that its voting/threshold policy is sound; this implementation checks contract presence, not the supplied governance contract's internal decision process.

Clients must use memberships/hasRole, hasPermission and CyberCorp.isCyberCORPOfficer for new companies. V2 userRoles intentionally remains zero, and numeric role-update/adapter/ownership APIs revert. Do not infer authority from director titles or numeric comparisons. Root proposes/cancels transfer with proposeRootTransfer; the nominee calls acceptRootTransfer. Officer roster changes go through CyberCorp; root setMembership cannot independently change the officer bit.

Shared platform factories, extension implementations and singleton conditions may continue using their separate platform BorgAuth. Company-scoped condition checks now consult company permissions. The legacy RoundManagerUpgradeHelper remains a legacy retrofit helper; new companies receive a RoundManager at creation. Root dependency setters do not automatically move manager memberships; explicitly revoke/grant the appropriate bits when replacing a manager.

## Reproducing local transaction acceptance

Start disposable Anvil on loopback port 18545 with chain ID 31337. Set CORPORATE_AUTH_LOCAL_ROOT_KEY to Anvil's public default first-account key and CORPORATE_AUTH_LOCAL_OFFICER to its second account. Run the local-only script:

```powershell
forge script script/test-corporate-auth-local.s.sol:TestCorporateAuthLocal --rpc-url http://127.0.0.1:18545 --broadcast --offline
./script/test-corporate-auth-local.ps1 -AuthAddress <printed CORPORATE_AUTH> -CorpAddress <printed CORPORATE_CORP>
```

The PowerShell acceptance runner signs each transaction, simulates its call, submits the signed bytes, checks receipt status and verifies resulting state. It includes authorized root configuration and officer signing, refused officer configuration and refused root signing without officer membership, refused unapproved/unauthorized authority upgrades, and an approved root upgrade preserving authority state. Fixtures and public development keys are for a disposable local chain only. The runner expects a fresh fixture because it checks that exactly one signature was accepted and a distinct approved upgrade is pending.

## Local validation milestone

On the uncommitted implementation based on d28a602d4afb01fbeacaafadc313a611d3473cf7: 513 tests pass across 20 selected suites, including 19 new corporate-auth/factory tests, plus a 256-run role-separation fuzz case. Seven local Anvil cases pass sign -> simulate -> submit acceptance with explicit successful and refused transactions. All production contracts pass EIP-170 size checks; LedgerEntryToken is 24,307 bytes (269 bytes remaining) and CyberCorpFactory is 22,124 bytes. The task record holds validation commands and scope. Independent external-model review remains required before release.
