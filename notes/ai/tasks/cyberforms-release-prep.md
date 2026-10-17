# cyberForms existing family publication specifications

- Status: sixteen PDFs published and byte-verified; all eight v1.4 templates registered and verified on each of Ethereum, Base and Arbitrum.
- Updated: 2026-10-17.
- Authorization: owner authorized the non-SAFO webapp release and template registration, and waived a separate isolated review/testing cycle.
- Base: `2510ff38723f6e084e7399325958220daa859d61`.
- Package: `/home/lex/repos/metalex-webapp/output/cyberforms-release-prep-20261017`.

Eight specifications and `templates/releases/let-v1.4.json` identify approved combined cyberSPA packets and matching standalone LET instrument PDFs. CIDs and fetched bytes match the frozen approved manifest. Field order and encoding remain unchanged from v1.3.

The owner confirmed one eight-template Ambire batch on each production chain. The sender was `0x3B12Bfc36931155A8Dc26c6636D0C888E9a3F55C`; the destination was Multicall3 with eight exact approved `createTemplate` calls, zero value and `allowFailure: false` for each. Receipts succeeded and all titles, URIs and ordered global/party fields matched at their receipt blocks.

| Chain | Block | Transaction |
| --- | --- | --- |
| Ethereum | 26215244 | [Receipt](https://etherscan.io/tx/0x740d341e49d9f13f775a1f0d4b84c42efd58fe0762b143c5635630ccff5ca1d0) |
| Base | 52743312 | [Receipt](https://basescan.org/tx/0xa283f27580fecc4dcd5b2eb9b660511aff325a2eef1fcaa0474235f1d0766b83) |
| Arbitrum | 515798573 | [Receipt](https://arbiscan.io/tx/0x54145658eb25d4365c580ffac60fb3a72234304fd28b69a2245d068afac3a468) |

The manifest records transaction hashes, chain IDs and blocks. The package retains full receipts, submitted transaction inputs and readbacks under `release-execution/registration-receipt-{1,8453,42161}.json`.

No Solidity implementation, ABI, storage, signature, authorization, deployment script or broadcast log is changed. Existing protocol entry points support this legal-text release. SAFO registration, integration and upgrades remain outside scope.

The app release PR is https://github.com/MetaLex-Tech/metalex-webapp/pull/1748 against production. It selects v1.4 only on these registered chains and retains v1.3 on testnets and for saved prior offerings. App production merge/deployment remains pending. All automatic contract/spec CI checks passed at the prior documentation commit; new results remain reported on this PR.
