# MTLX1-41: permissionless deployment authorization

Checked against the uncommitted implementation on 2026-09-16. This describes the
working-tree changes, not a completed on-chain rollout.

## Implementation

The proposed abstract `ComponentFactory` base contract has been removed. The four
existing component factories still inherit `BorgAuthACL` directly and use the
stateless `src/libs/FactoryDeploymentLib.sol` for salt derivation and compatibility
checks. Each exposes `deploymentSalt(bytes32 salt, address deployer)`. There is no
new deployed helper contract, storage, platform allowlist or deployment role.

## Address commitments

CyberCorpSingleFactory, IssuanceManagerFactory, DealManagerFactory and
RoundManagerFactory remain public. Each derives its CREATE2 salt as
`keccak256(abi.encode(msg.sender, salt))`. A direct caller or another corporate
factory therefore cannot occupy addresses in the intended corporate factory's
namespace. Retrofits use a separate salt derivation described below.

CyberCorpFactory and PumpCorpFactory additionally derive their input salt from
`keccak256(abi.encode(userSalt, companyName, companyType, companyJurisdiction,
companyContactDetails, defaultDisputeResolution, companyPayable, officer))`.
The full CompanyOfficer struct is included. Changing the officer or payout address
produces different company and manager addresses, even when the attacker supplies
valid signatures of their own. The victim's offering signature cannot be reused at
those different addresses. BorgAuth is deployed by the corporate factory itself,
using `keccak256(abi.encodePacked("auth", deploymentSalt))`, with that same
configuration commitment as `deploymentSalt`.

Standalone `deployCyberCorp` stays public and puts no condition on the caller. The
configuration commitment makes a caller restriction unnecessary. A caller that
changes the officer or the payout address gets different addresses. A caller that
keeps them gives the owner role to that officer and keeps no role, so it cannot
create a round. Relayers also use the public signed round functions:
CyberCorpFactory's `deployCyberCorpAndCreateRound` and PumpCorpFactory's
`deployCyberCorpAndCreateRoundFor`. Their argument lists are unchanged; any caller
can submit valid officer signatures.

The existing metadata signature covers certificates, conditions, agreement values
and configuration, and the escrow signature covers round economics and the
predicted addresses. These remain two separate authorizations; see the remaining
concerns below. Primary-offer factory calls continue to set `officer.eoa` to
`msg.sender`, whose transaction authorizes the actual offering and escrow inputs.

CyberCorpFactory's public `deployAndInitializeRoundManager` requires the caller to
hold OWNER_ROLE in the existing corporation's AUTH. It passes
`keccak256(abi.encode("retrofit", salt, cyberCorpAddress))` to RoundManagerFactory,
which then applies the corporate factory's caller namespace. PumpCorpFactory's
RoundManager deployment helper remains internal.

## Client migration

1. Keep the original user salt for the metadata signature and public factory call.
   Combined functions still convert their uint256 salt with
   `keccak256(abi.encodePacked(salt))` before computing the configuration commitment.
2. Call `computeDeploymentSalt` on the corporate factory with that bytes32 salt
   and the exact company configuration.
3. Pass the returned salt and the **corporate factory proxy address** to the
   component's new two-argument `compute…Address(salt, deployer)` overload.
4. Sign the escrowed round or primary agreement using the newly predicted addresses.
   The primary agreement's finalizer is the predicted DealManager.

For primary-offer predictions, use the actual transaction caller as `officer.eoa`,
because that entry point overwrites the supplied field. For retrofit predictions,
use the retrofit salt above and the CyberCorpFactory proxy as the deployer.

For direct component deployments, the existing one-argument prediction helper
uses the querying caller's namespace. Off-chain clients should prefer the explicit
two-argument overload with the address that will actually call the component.

New deployment predictions change. Previously prepared escrow/agreement signatures
must be regenerated; the supplemental metadata type and domain are unchanged.
Standalone deployment accepts any caller, so a contract caller still works. A
Multicall3 batch that pays a fee and forms a company in one transaction is one
such caller. Existing deployed corporations and managers retain their addresses,
state and permissions. This change adds no storage fields to the upgraded
factories.

## Rollout and validation

Upgrade all four component factories and both corporate factories together. The
updated corporate factories call `requireNamespaces` before deployment and revert
with `IncompatibleComponentFactory(factory)` if a component does not expose the
expected namespace calculation. The public retrofit path checks its RoundManager
factory too. This detects legacy components; it does not protect a corporate
factory that has not itself been upgraded, or attest that an arbitrary component's
deployment code matches the value returned by its helper.

Prefer an atomic governance batch. `script/upgrade-v5.s.sol` broadcasts multiple
transactions; its singleton rollout is not atomic. It upgrades the four configured
component targets before the corporate factories and requires `PUMP_CORP_FACTORY`
on Base (optional on the other supported chains). Check the actual component
references on both corporate proxies: the script does not discover or upgrade an
additional, separate set of Pump component proxies automatically. Clients must
wait until the complete stack is upgraded before issuing new signed packages.

Inventory other top-level factories sharing these components, including
ParentCoFactory and MetaDAOFactory where deployed. Their client predictions also
need the correct caller namespace; their own authorization flows are outside this
patch's regression coverage. Existing component reference implementations need
not change for this fix alone, although the broader v5 script updates them for
other changes.

The regression suite in `test/FactoryRoundAuthReplayPOC.t.sol` covers permissionless
component calls, separate caller namespaces, self-signed hostile deployments, payout
substitution, rejection of a stolen round signature, rejection of a legacy component
during a partial upgrade, and successful deployment of the original signed package
afterward. Two tests cover the standalone path: a substituted payout address moves
the corp address, and a named officer receives the owner role while the caller
receives none. The Pump happy-path test calls `For` from an address other than the
officer.

`test/MulticallFormationFeeForkTest.t.sol` guards the contract caller. It upgrades
the corporate factory and its four components on a Base fork, then forms a company
through Multicall3.

CyberCorpForkTest predicts the DealManager from the company configuration each test
deploys. Three tests deploy a different company from the others, so they pass their
own name, jurisdiction and dispute resolution to `_predictedDealManager`.

The last run passed the unit tier with no failures and the fork tier with 173 tests
and no failures. A live client signing and relaying rehearsal has not been done.

## Remaining concerns

- **Separate signatures can be combined across revisions.** The deployment salt
  commits to corporate configuration, not offering terms. The supplemental digest
  does not include the escrow digest or round ID, and the escrow digest does not
  include supplemental metadata. Source review therefore identifies a remaining
  risk when the same officer signs multiple versions for the same salt and company
  configuration: metadata from one version can be combined with economics from
  another. This case is not covered by the current regression tests. Use a fresh
  salt for each revised package; a shared signed package commitment would enforce
  the pairing on-chain and remains unimplemented.
- **No deployment cancellation or authorization expiry was added.** A salt is
  effectively consumed by successful CREATE2 deployment, rather than a nonce
  registry. Issuing a replacement package does not revoke an older signed package.
  The existing round start/end terms are not a separate deployment-signature
  deadline. Nonce cancellation and an explicit deadline would need further work.
- **Rollout and client compatibility require coordination.** Predicted addresses
  change, old address-bound signatures need regeneration, and every actual
  component dependency must be upgraded. The local test results do not establish
  that the deployed proxies or external clients have been migrated correctly.
- **The fix is not retroactive.** Upgrading factories does not repair a previously
  squatted corporation or invalidate signatures usable on its existing managers.
  Any such deployment needs separate investigation and remediation.
- **Exact-copy relaying remains possible.** Someone may submit an unchanged valid
  signed combined call first. It executes the signed configuration and offering;
  the later duplicate reverts because the deployment already exists. This does
  not let the relayer substitute their officer or payout address.
