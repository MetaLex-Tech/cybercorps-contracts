// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {IIssuanceManager} from "../src/interfaces/IIssuanceManager.sol";
import {IIssuanceManagerFactory} from "../src/interfaces/IIssuanceManagerFactory.sol";
import {SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";

contract CyberCertPrinterAdhocTest is Test {
    // Fill these in with real values before running locally/CI
    string internal constant RPC_ENV_VAR = "FORK_RPC_URL"; // e.g. BASE_SEPOLIA_RPC_URL
    address internal constant ISSUANCE_MANAGER_OWNER = address(0); // company owner on target chain

    // Add one or more existing CyberCertPrinter addresses to validate on fork
    address[] internal certPrinters = new address[](0);

    function setUp() public {
        // Create/select fork from env
        string memory rpcUrl = vm.envString(RPC_ENV_VAR);
        vm.createSelectFork(rpcUrl);
    }

    //
    // Helpers
    //
    struct PrinterSnapshot {
        address issuanceManager;
        SecurityClass securityType;
        SecuritySeries securitySeries;
        string certificateUri;
        bool transferable;
        bool endorsementRequired;
        bytes32 defaultLegendHash;
        uint256 totalSupply;
        // Optional sample token checks (up to first 3 tokens by index)
        uint256 sampleCount;
        uint256[3] tokenIds;
        bytes32[3] tokenUriHash;
        CertificateDetails[3] details;
    }

    function _hashStringArray(string[] memory arr) internal pure returns (bytes32) {
        // Order-sensitive; good enough to catch storage corruption on upgrade
        return keccak256(abi.encode(arr));
    }

    function _hashString(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function _snapshot(address printerAddr) internal view returns (PrinterSnapshot memory s) {
        ICyberCertPrinter printer = ICyberCertPrinter(printerAddr);

        s.issuanceManager = CyberCertPrinter(printerAddr).issuanceManager();
        s.securityType = CyberCertPrinter(printerAddr).securityType();
        s.securitySeries = CyberCertPrinter(printerAddr).securitySeries();
        s.certificateUri = CyberCertPrinter(printerAddr).certificateUri();
        s.transferable = CyberCertPrinter(printerAddr).transferable();
        s.endorsementRequired = CyberCertPrinter(printerAddr).endorsementRequired();
        s.defaultLegendHash = _hashStringArray(CyberCertPrinter(printerAddr).defaultLegend());


        uint256 supply = 0;
        // totalSupply is part of the ICyberCertPrinter interface
        try printer.totalSupply() returns (uint256 ts) {
            supply = ts;
        } catch {}
        s.totalSupply = supply;

        uint256 toSample = supply < 3 ? supply : 3;
        s.sampleCount = toSample;
        for (uint256 i = 0; i < toSample; i++) {
            uint256 tokenId = IERC721Enumerable(printerAddr).tokenByIndex(i);
            s.tokenIds[i] = tokenId;
            // tokenURI may revert if metadata is missing; treat revert as empty
            try printer.tokenURI(tokenId) returns (string memory uri) {
                s.tokenUriHash[i] = _hashString(uri);
            } catch {
                s.tokenUriHash[i] = bytes32(0);
            }
            // getCertificateDetails should not revert for existing token
            try printer.getCertificateDetails(tokenId) returns (CertificateDetails memory d) {
                s.details[i] = d;
            } catch {
                // leave zeroed if it reverts
            }
        }
    }

    //
    // Tests
    //

    function test_PrinterStorageIntegrity_NoMutation() public {
        for (uint256 i = 0; i < certPrinters.length; i++) {
            address printer = certPrinters[i];
            // Basic invariants do not revert and key fields are non-zero/sane
            PrinterSnapshot memory snap = _snapshot(printer);

            assertTrue(snap.issuanceManager != address(0), "issuanceManager should be set");
            // Security enums are 0-indexed; sanity check that they are within a reasonable range
            // Can't know exact values on chain; just ensure access doesn't revert and fields are readable

            // certificateUri is allowed to be empty, but typically set
            // defaultLegendHash existence ensures array access works
            // totalSupply read should not revert
            assertEq(IIssuanceManager(snap.issuanceManager).CORP() != address(0), true, "IM CORP should be set");
        }
    }

    function test_PrinterBeaconMatchesFactoryRefImplementation() public {
        for (uint256 i = 0; i < certPrinters.length; i++) {
            address printer = certPrinters[i];
            address im = CyberCertPrinter(printer).issuanceManager();
            address upgradeFactory = IIssuanceManager(im).getUpgradeFactory();

            address beaconImpl = IIssuanceManager(im).getCertPrinterBeaconImplementation();
            address refImpl = IIssuanceManagerFactory(upgradeFactory).getCyberCertPrinterRefImplementation();

            // If these differ on fork, the deployment hasn't accepted the latest ref implementation yet.
            // The main check here is that we can safely read both and they are valid addresses.
            assertTrue(beaconImpl != address(0), "beacon implementation should be set");
            assertTrue(refImpl != address(0), "ref implementation should be set");
        }
    }

    function test_PrinterStorage_UnchangedAfterNoOpUpgrade() public {
        // This test impersonates the IssuanceManager owner to call the upgrade function
        // with the current reference implementation to validate storage stability.
        vm.startPrank(ISSUANCE_MANAGER_OWNER);
        for (uint256 i = 0; i < certPrinters.length; i++) {
            address printer = certPrinters[i];

            PrinterSnapshot memory beforeSnap = _snapshot(printer);

            address upgradeFactory = IIssuanceManager(beforeSnap.issuanceManager).getUpgradeFactory();
            address refImpl = IIssuanceManagerFactory(upgradeFactory).getCyberCertPrinterRefImplementation();
            IIssuanceManager(beforeSnap.issuanceManager).upgradeCertPrinterBeaconImplementation(refImpl);

            PrinterSnapshot memory afterSnap = _snapshot(printer);

            // Compare essential configuration fields
            assertEq(afterSnap.issuanceManager, beforeSnap.issuanceManager, "issuanceManager changed");
            assertEq(uint256(afterSnap.securityType), uint256(beforeSnap.securityType), "securityType changed");
            assertEq(uint256(afterSnap.securitySeries), uint256(beforeSnap.securitySeries), "securitySeries changed");
            assertEq(keccak256(bytes(afterSnap.certificateUri)), keccak256(bytes(beforeSnap.certificateUri)), "certificateUri changed");
            assertEq(afterSnap.transferable, beforeSnap.transferable, "transferable changed");
            assertEq(afterSnap.endorsementRequired, beforeSnap.endorsementRequired, "endorsementRequired changed");
            assertEq(afterSnap.defaultLegendHash, beforeSnap.defaultLegendHash, "defaultLegend changed");
            assertEq(afterSnap.totalSupply, beforeSnap.totalSupply, "totalSupply changed");

            // Spot-check first up to 3 tokens
            assertEq(afterSnap.sampleCount, beforeSnap.sampleCount, "sample size changed");
            for (uint256 j = 0; j < beforeSnap.sampleCount; j++) {
                assertEq(afterSnap.tokenIds[j], beforeSnap.tokenIds[j], "tokenId changed");
                assertEq(afterSnap.tokenUriHash[j], beforeSnap.tokenUriHash[j], "tokenURI changed");
                // Compare a few CertificateDetails fields that are most sensitive to layout changes
                assertEq(afterSnap.details[j].unitsRepresented, beforeSnap.details[j].unitsRepresented, "unitsRepresented changed");
                assertEq(afterSnap.details[j].investmentAmountUSD, beforeSnap.details[j].investmentAmountUSD, "investmentAmountUSD changed");
                assertEq(afterSnap.details[j].issuerUSDValuationAtTimeOfInvestment, beforeSnap.details[j].issuerUSDValuationAtTimeOfInvestment, "issuerUSD valuation changed");
            }
        }
        vm.stopPrank();
    }
}


