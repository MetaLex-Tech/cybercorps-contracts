// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LeXcheXBadge} from "../src/creds/lexchexBadge.sol";
import {ZKPassportBadgeIssuer} from "../src/creds/ZKPassportBadgeIssuer.sol";
import {K_ZKP_NATIONALITY_OUT} from "../src/interfaces/ILexChexBadge.sol";
import {IZKPassportVerifier, ProofVerificationParams} from "../src/interfaces/IZKPassportVerifier.sol";
import {NonUSNationalityConditionHelper} from "./NonUSNationalityConditionForkTest.t.sol";

/// @notice Real-proof coverage for ZKPassportBadgeIssuer against the deployed ZKPassport verifier.
///
/// The point of interest is which parts of `ProofVerificationParams` the verifier actually authenticates.
/// `domain` and `scope` are committed to the proof and cannot be altered. `serviceConfig.validityPeriodInSeconds`
/// is NOT: it is plain calldata the submitter chooses, and the verifier accepts the same proof bytes whatever it
/// says. The issuer derives the credential's expiry from it, so `maxValidityPeriod` is what keeps a holder from
/// granting themselves standing that never needs re-proving. These tests pin that against a real proof.
contract ZKPassportBadgeIssuerForkTest is Test {
    address constant REAL_VERIFIER = 0x1D000001000EFD9a6371f4d90bB8920D5431c0D8;
    string constant PROOF = "test/res/sample-non-us-sanctioned-countries-sanctioned-list-proof-call.json";

    // The proof is time-sensitive, so the fork and the clock are both pinned to when it was signed.
    uint256 constant SIGNED_TS = 1772783327;
    uint256 constant DECLARED_VALIDITY = 7 days; // what the proof call was generated with
    uint256 constant MAX_VALIDITY = 365 days;

    string constant DOMAIN = "localhost";
    string constant SCOPE = "hello-world";

    BorgAuth internal auth;
    LeXcheXBadge internal badge;
    ZKPassportBadgeIssuer internal issuer;
    string[] internal excludedCountries;

    function setUp() public {
        vm.createSelectFork("sepolia", 10408265);

        excludedCountries = new string[](9);
        excludedCountries[0] = "IRN";
        excludedCountries[1] = "IRQ";
        excludedCountries[2] = "LBY";
        excludedCountries[3] = "PRK";
        excludedCountries[4] = "SDN";
        excludedCountries[5] = "SOM";
        excludedCountries[6] = "SYR";
        excludedCountries[7] = "USA";
        excludedCountries[8] = "YEM";

        auth = new BorgAuth(address(this));
        badge = LeXcheXBadge(
            address(new ERC1967Proxy(address(new LeXcheXBadge()), abi.encodeCall(LeXcheXBadge.initialize, (address(auth)))))
        );
        issuer = ZKPassportBadgeIssuer(
            address(
                new ERC1967Proxy(
                    address(new ZKPassportBadgeIssuer()),
                    abi.encodeCall(
                        ZKPassportBadgeIssuer.initialize,
                        (address(auth), address(badge), DOMAIN, SCOPE, REAL_VERIFIER, MAX_VALIDITY)
                    )
                )
            )
        );
        auth.updateRole(address(issuer), auth.ADMIN_ROLE());
    }

    /// @notice A real proof mints the nationality-exclusion credential, expiring per the declared validity period.
    function test_RealProof_MintsNationalityOutCredential() public {
        (ProofVerificationParams memory params, address account) =
            NonUSNationalityConditionHelper.parseProofFromJson(PROOF);
        assertEq(params.serviceConfig.validityPeriodInSeconds, DECLARED_VALIDITY, "sample proof validity changed");

        vm.warp(SIGNED_TS);
        uint256 tokenId = issuer.submitProofAndMint(params, K_ZKP_NATIONALITY_OUT, excludedCountries);

        assertTrue(badge.hasValidCredentialOf(account, K_ZKP_NATIONALITY_OUT), "credential vests in the bound wallet");
        assertEq(uint256(badge.getCredential(tokenId).expiryDate), SIGNED_TS + DECLARED_VALIDITY);

        (string[] memory list,) = badge.getZkpNationalityOut(account);
        assertEq(list.length, excludedCountries.length);
    }

    /// @notice The submitter rewrites the validity period on an unmodified proof. Nothing is forged — the proof
    /// bytes, domain and scope are untouched, and the wallet is the one the holder genuinely proved control of —
    /// and the real verifier still accepts it, which is exactly why maxValidityPeriod has to exist. Without it a
    /// 7-day proof would mint a 10-year credential.
    function test_ValidityPeriodIsNotBoundToTheProof_CapRefusesIt() public {
        (ProofVerificationParams memory params, address account) =
            NonUSNationalityConditionHelper.parseProofFromJson(PROOF);

        params.serviceConfig.validityPeriodInSeconds = 3650 days; // the only edit

        // The verifier is content: the tampered field is not part of what it authenticates.
        vm.warp(SIGNED_TS);
        (bool verified,,) = IZKPassportVerifier(REAL_VERIFIER).verify(params);
        assertTrue(verified, "the same proof verifies with a rewritten validity period");

        // The issuer is not.
        vm.expectRevert(ZKPassportBadgeIssuer.MaxValidityPeriodExceeded.selector);
        issuer.submitProofAndMint(params, K_ZKP_NATIONALITY_OUT, excludedCountries);
        assertFalse(badge.hasValidCredentialOf(account, K_ZKP_NATIONALITY_OUT), "no credential issued");
    }

    /// @notice The neighbouring fields in the very same struct ARE committed to the proof: rewriting `domain` or
    /// `scope` the way the validity period was rewritten makes the verifier itself reject the proof. That contrast
    /// is the whole point — `serviceConfig` is authenticated field by field, and the validity period is not among
    /// the authenticated ones.
    function test_DomainAndScopeAreBoundToTheProof() public {
        (ProofVerificationParams memory params,) = NonUSNationalityConditionHelper.parseProofFromJson(PROOF);

        params.serviceConfig.domain = "evil.example";
        params.serviceConfig.scope = "evil-scope";

        vm.warp(SIGNED_TS);
        vm.expectRevert(bytes("Invalid domain or scope"));
        issuer.submitProofAndMint(params, K_ZKP_NATIONALITY_OUT, excludedCountries);
    }

    /// @notice The issuer must also be the audience the proof was made for: a proof for another app is refused even
    /// though it is authentic.
    function test_ProofForAnotherAudienceIsRefused() public {
        (ProofVerificationParams memory params,) = NonUSNationalityConditionHelper.parseProofFromJson(PROOF);

        ZKPassportBadgeIssuer other = ZKPassportBadgeIssuer(
            address(
                new ERC1967Proxy(
                    address(new ZKPassportBadgeIssuer()),
                    abi.encodeCall(
                        ZKPassportBadgeIssuer.initialize,
                        (address(auth), address(badge), "other.example", "other-scope", REAL_VERIFIER, MAX_VALIDITY)
                    )
                )
            )
        );

        vm.warp(SIGNED_TS);
        vm.expectRevert(ZKPassportBadgeIssuer.InvalidScope.selector);
        other.submitProofAndMint(params, K_ZKP_NATIONALITY_OUT, excludedCountries);
    }
}
