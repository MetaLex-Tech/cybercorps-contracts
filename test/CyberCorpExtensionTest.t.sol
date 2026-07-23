// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CompanyOfficer} from "../src/CyberCorpConstants.sol";
import {
    CyberCorpExtension,
    CyberCorpData
} from "../src/storage/extensions/CyberCorpExtension.sol";
import {
    CyberCorpExtensionV2,
    CyberCorpDataV2
} from "../src/storage/extensions/CyberCorpExtensionV2.sol";
import {
    CyberCorpComplianceExtension,
    CyberCorpComplianceData,
    FeeDetail
} from "../src/storage/extensions/CyberCorpComplianceExtension.sol";
import {
    CyberCorpFundExtension,
    CyberCorpFundData,
    PortfolioHolding
} from "../src/storage/extensions/CyberCorpFundExtension.sol";

contract CyberCorpExtensionTest is Test {
    address internal owner;
    BorgAuth internal auth;
    CyberCorp internal cyberCorp;

    function setUp() public {
        owner = makeAddr("owner");
        auth = new BorgAuth(owner);

        CompanyOfficer memory officer = CompanyOfficer({
            eoa: owner,
            name: "Owner",
            contact: "owner@corp.test",
            title: "CEO"
        });

        CyberCorp implementation = new CyberCorp();
        cyberCorp = CyberCorp(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeWithSelector(
                        CyberCorp.initialize.selector,
                        address(auth),
                        "CyberCorp",
                        "Corporation",
                        "Delaware",
                        "contact@corp.test",
                        "AAA",
                        address(0xBEEF),
                        owner,
                        officer,
                        address(0xCAFE),
                        address(0)
                    )
                )
            )
        );
    }

    function test_SetCyberCorpExtensionDataWithVersionedSchema() public {
        CyberCorpExtension corpExtension = CyberCorpExtension(address(new ERC1967Proxy(
            address(new CyberCorpExtension()),
            abi.encodeWithSelector(CyberCorpExtension.initialize.selector, address(auth))
        )));

        bytes memory encoded = corpExtension.encodeExtensionData(
            CyberCorpData({
                website: "https://corp.test",
                primaryBusinessLine: "Software",
                entityId: "DE-12345",
                metadataURI: "ipfs://corp-metadata"
            })
        );

        vm.startPrank(owner);
        cyberCorp.setExtension(
            address(corpExtension),
            corpExtension.EXTENSION_TYPE()
        );
        cyberCorp.setExtensionData(encoded);
        vm.stopPrank();

        assertEq(cyberCorp.extension(), address(corpExtension));
        assertEq(cyberCorp.extensionType(), corpExtension.EXTENSION_TYPE());
        assertEq(cyberCorp.extensionData(), encoded);
        assertEq(
            cyberCorp.getExtensionURI(),
            corpExtension.getExtensionURI(encoded)
        );
    }

    function test_RevertIf_ExtensionTypeUnsupported() public {
        CyberCorpExtension corpExtension = CyberCorpExtension(address(new ERC1967Proxy(
            address(new CyberCorpExtension()),
            abi.encodeWithSelector(CyberCorpExtension.initialize.selector, address(auth))
        )));

        vm.prank(owner);
        vm.expectRevert(CyberCorp.ExtensionTypeNotSupported.selector);
        cyberCorp.setExtension(
            address(corpExtension),
            keccak256("CYBERCORP_V2")
        );
    }

    function test_SettingNewExtensionClearsStaleExtensionData() public {
        CyberCorpExtension corpExtension = CyberCorpExtension(address(new ERC1967Proxy(
            address(new CyberCorpExtension()),
            abi.encodeWithSelector(CyberCorpExtension.initialize.selector, address(auth))
        )));

        CyberCorpExtensionV2 corpExtensionV2 = CyberCorpExtensionV2(address(new ERC1967Proxy(
            address(new CyberCorpExtensionV2()),
            abi.encodeWithSelector(CyberCorpExtensionV2.initialize.selector, address(auth))
        )));

        bytes memory encodedV1 = corpExtension.encodeExtensionData(
            CyberCorpData({
                website: "https://corp.test",
                primaryBusinessLine: "Software",
                entityId: "DE-12345",
                metadataURI: "ipfs://corp-metadata"
            })
        );

        bytes memory encodedV2 = corpExtensionV2.encodeExtensionData(
            CyberCorpDataV2({
                website: "https://corp.test",
                primaryBusinessLine: "Software",
                entityId: "DE-12345",
                metadataURI: "ipfs://corp-metadata-v2",
                investorRelationsURI: "https://corp.test/ir",
                transferAgent: "Transfer Agent LLC"
            })
        );

        vm.startPrank(owner);
        cyberCorp.setExtension(
            address(corpExtension),
            corpExtension.EXTENSION_TYPE()
        );
        cyberCorp.setExtensionData(encodedV1);
        cyberCorp.setExtension(
            address(corpExtensionV2),
            corpExtensionV2.EXTENSION_TYPE()
        );
        vm.stopPrank();

        assertEq(cyberCorp.extension(), address(corpExtensionV2));
        assertEq(cyberCorp.extensionType(), corpExtensionV2.EXTENSION_TYPE());
        assertEq(cyberCorp.extensionData().length, 0);

        vm.prank(owner);
        cyberCorp.setExtensionData(encodedV2);

        assertEq(cyberCorp.extensionData(), encodedV2);
        assertEq(
            cyberCorp.getExtensionURI(),
            corpExtensionV2.getExtensionURI(encodedV2)
        );
    }

    function test_SetComplianceExtensionDataWithErisaOwnershipFeesAndRestrictions() public {
        CyberCorpComplianceExtension complianceExtension = CyberCorpComplianceExtension(address(new ERC1967Proxy(
            address(new CyberCorpComplianceExtension()),
            abi.encodeWithSelector(CyberCorpComplianceExtension.initialize.selector, address(auth))
        )));

        string[] memory holderRestrictions = new string[](3);
        holderRestrictions[0] = "No sanctioned persons";
        holderRestrictions[1] = "Transfers to non-U.S. persons require review";
        holderRestrictions[2] = "Sensitive sector holders may require CFIUS review";

        FeeDetail[] memory feeDetails = new FeeDetail[](2);
        feeDetails[0] = FeeDetail({
            feeName: "Platform fee",
            feeBps: 250,
            flatFee: 0,
            recipient: address(0xFEE1),
            feeToken: "USDC",
            notes: "Charged on primary issuance proceeds"
        });
        feeDetails[1] = FeeDetail({
            feeName: "Transfer admin fee",
            feeBps: 0,
            flatFee: 500e6,
            recipient: address(0xFEE2),
            feeToken: "USDC",
            notes: "Flat fee per approved secondary transfer"
        });

        CyberCorpComplianceData memory complianceData = CyberCorpComplianceData({
            erisaAllowed: false,
            maxOwnershipBps: 1500,
            minNonZeroOwnershipBps: 5,
            maxHolderCount: 1999,
            cfiusApprovalRequired: true,
            holderRestrictions: holderRestrictions,
            feeDetails: feeDetails
        });

        bytes memory encoded =
            complianceExtension.encodeExtensionData(complianceData);

        vm.startPrank(owner);
        cyberCorp.setExtension(
            address(complianceExtension),
            complianceExtension.EXTENSION_TYPE()
        );
        cyberCorp.setExtensionData(encoded);
        vm.stopPrank();

        CyberCorpComplianceData memory decoded =
            complianceExtension.decodeExtensionData(cyberCorp.extensionData());

        assertEq(cyberCorp.extension(), address(complianceExtension));
        assertEq(
            cyberCorp.extensionType(),
            complianceExtension.EXTENSION_TYPE()
        );
        assertEq(decoded.erisaAllowed, false);
        assertEq(decoded.maxOwnershipBps, 1500);
        assertEq(decoded.minNonZeroOwnershipBps, 5);
        assertEq(decoded.maxHolderCount, 1999);
        assertEq(decoded.cfiusApprovalRequired, true);
        assertEq(decoded.holderRestrictions.length, 3);
        assertEq(decoded.holderRestrictions[2], holderRestrictions[2]);
        assertEq(decoded.feeDetails.length, 2);
        assertEq(decoded.feeDetails[0].feeBps, 250);
        assertEq(decoded.feeDetails[1].flatFee, 500e6);

        string memory extensionJson = cyberCorp.getExtensionURI();
        assertEq(
            extensionJson,
            complianceExtension.getExtensionURI(encoded)
        );
        assertTrue(
            bytes(extensionJson).length > 0,
            "compliance extension json should not be empty"
        );
        assertTrue(
            _contains(extensionJson, '"erisaAllowed": "false"'),
            "ERISA flag missing"
        );
        assertTrue(
            _contains(extensionJson, '"maxOwnershipBps": "1500"'),
            "max ownership missing"
        );
        assertTrue(
            _contains(extensionJson, '"minNonZeroOwnershipBps": "5"'),
            "min non-zero ownership missing"
        );
        assertTrue(
            _contains(extensionJson, '"cfiusApprovalRequired": "true"'),
            "CFIUS flag missing"
        );
        assertTrue(
            _contains(extensionJson, '"Platform fee"'),
            "fee details missing"
        );
        assertTrue(
            _contains(extensionJson, '"No sanctioned persons"'),
            "holder restrictions missing"
        );
    }

    function test_SetFundExtensionDataWithFundWideTermsAndDocuments() public {
        CyberCorpFundExtension fundExtension = CyberCorpFundExtension(address(new ERC1967Proxy(
            address(new CyberCorpFundExtension()),
            abi.encodeWithSelector(CyberCorpFundExtension.initialize.selector, address(auth))
        )));

        string[] memory governingDocumentURIs = new string[](3);
        governingDocumentURIs[0] = "ipfs://operating-agreement";
        governingDocumentURIs[1] = "ipfs://subscription-agreement";
        governingDocumentURIs[2] = "ipfs://ppm";

        PortfolioHolding[] memory portfolioHoldings = new PortfolioHolding[](1);
        portfolioHoldings[0] = PortfolioHolding({
            portfolioCompany: "Anthropic, PBC",
            securityKind: "Series C Preferred Stock",
            underlyingShares: 4_200_000
        });

        CyberCorpFundData memory fundData = CyberCorpFundData({
            fundEntityType: "LLC",
            icaExceptionRelied: "3(c)(1)",
            regSIssuerCategory: 3,
            holderCap: 100,
            totalUnitsOutstanding: 100_000_000,
            ratioStable: true,
            portfolioHoldings: portfolioHoldings,
            cfiusSensitive: false,
            provenanceAttestationHash: keccak256("gp-provenance-attestation"),
            documentRegistryURI: "ipfs://legion-af1-disclosures",
            governingDocumentURIs: governingDocumentURIs,
            metadataURI: "ipfs://fund-metadata"
        });

        bytes memory encoded = fundExtension.encodeExtensionData(fundData);

        vm.startPrank(owner);
        cyberCorp.setExtension(
            address(fundExtension),
            fundExtension.EXTENSION_TYPE()
        );
        cyberCorp.setExtensionData(encoded);
        vm.stopPrank();

        CyberCorpFundData memory decoded =
            fundExtension.decodeExtensionData(cyberCorp.extensionData());

        assertEq(cyberCorp.extension(), address(fundExtension));
        assertEq(cyberCorp.extensionType(), fundExtension.EXTENSION_TYPE());
        assertEq(decoded.fundEntityType, "LLC");
        assertEq(decoded.icaExceptionRelied, "3(c)(1)");
        assertEq(decoded.regSIssuerCategory, 3);
        assertEq(decoded.holderCap, 100);
        assertEq(decoded.totalUnitsOutstanding, 100_000_000);
        assertTrue(decoded.ratioStable);
        assertEq(decoded.portfolioHoldings.length, 1);
        assertEq(decoded.portfolioHoldings[0].portfolioCompany, "Anthropic, PBC");
        assertEq(decoded.portfolioHoldings[0].securityKind, "Series C Preferred Stock");
        assertEq(decoded.portfolioHoldings[0].underlyingShares, 4_200_000);
        assertFalse(decoded.cfiusSensitive);
        assertEq(decoded.provenanceAttestationHash, keccak256("gp-provenance-attestation"));
        assertEq(decoded.documentRegistryURI, "ipfs://legion-af1-disclosures");
        assertEq(decoded.governingDocumentURIs.length, 3);
        assertEq(decoded.governingDocumentURIs[2], "ipfs://ppm");
        assertEq(decoded.metadataURI, "ipfs://fund-metadata");

        string memory extensionJson = cyberCorp.getExtensionURI();
        assertEq(extensionJson, fundExtension.getExtensionURI(encoded));
        assertTrue(
            bytes(extensionJson).length > 0,
            "fund extension json should not be empty"
        );
        assertTrue(
            _contains(extensionJson, '"fundEntityType": "LLC"'),
            "fund entity type missing"
        );
        assertTrue(
            _contains(extensionJson, '"icaExceptionRelied": "3(c)(1)"'),
            "ICA exception missing"
        );
        assertTrue(
            _contains(extensionJson, '"regSIssuerCategory": 3'),
            "Reg S issuer category missing"
        );
        assertTrue(
            _contains(extensionJson, '"holderCap": 100'),
            "holder cap missing"
        );
        assertTrue(
            _contains(extensionJson, '"portfolioCompany": "Anthropic, PBC"'),
            "portfolio holding missing"
        );
        assertTrue(
            _contains(extensionJson, '"totalUnitsOutstanding": 100000000'),
            "total units outstanding missing"
        );
        assertTrue(
            _contains(extensionJson, "ipfs://operating-agreement"),
            "governing document missing"
        );
        assertTrue(
            _contains(extensionJson, '"documentRegistryURI": "ipfs://legion-af1-disclosures"'),
            "document registry URI missing"
        );
        assertTrue(
            _contains(extensionJson, '"metadataURI": "ipfs://fund-metadata"'),
            "metadata URI missing"
        );
    }

    function _contains(
        string memory haystack,
        string memory needle
    ) internal pure returns (bool) {
        bytes memory haystackBytes = bytes(haystack);
        bytes memory needleBytes = bytes(needle);

        if (needleBytes.length == 0) return true;
        if (needleBytes.length > haystackBytes.length) return false;

        for (uint256 i = 0; i <= haystackBytes.length - needleBytes.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < needleBytes.length; j++) {
                if (haystackBytes[i + j] != needleBytes[j]) {
                    matches = false;
                    break;
                }
            }

            if (matches) return true;
        }

        return false;
    }
}
