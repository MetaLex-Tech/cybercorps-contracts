// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CorpFactoryMetadataLib} from "../src/libs/CorpFactoryMetadataLib.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberCertData as RM_CyberCertData} from "../src/storage/RoundManagerStorage.sol";

/// @notice The typehash strings of the original PumpCorpFactoryLib, copied verbatim from before the
/// migration to CorpFactoryMetadataLib. Officer signatures already exist over these, so they are
/// frozen. Declared here independently of the library under test, so a change there fails the test.
library LegacyPumpMetadataLib {
    bytes32 constant FACTORY_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 constant OFFICER_TYPEHASH = keccak256(
        "CompanyOfficer(address eoa,string name,string contact,string title)"
    );
    bytes32 constant CERT_DATA_TYPEHASH = keccak256(
        "CyberCertData(string name,string symbol,string uri,uint8 securityClass,uint8 securitySeries,address extension,bytes seriesData,string[] defaultLegend)"
    );
    bytes32 constant ROUND_SUPPLEMENTAL_TYPEHASH = keccak256(
        "RoundSupplementalData(bytes32 corpSalt,address companyPayable,bool publicRound,bool allowTimedOffers,bool restrictEndTimeReduction,CompanyOfficer officer,string companyName,string companyType,string companyJurisdiction,string companyContactDetails,string defaultDisputeResolution,bytes[] extensionData,string[] roundPartyValues,string[] legalDetails,CyberCertData[] certData,address[] conditionAddresses)CompanyOfficer(address eoa,string name,string contact,string title)CyberCertData(string name,string symbol,string uri,uint8 securityClass,uint8 securitySeries,address extension,bytes seriesData,string[] defaultLegend)"
    );
}

/// @title Digest equivalence for the shared deployment metadata library
/// @notice PumpCorpFactory moved from its own PumpCorpFactoryLib to CorpFactoryMetadataLib. Officer
/// signatures already exist for the old encoding, so the digest must not change. The helpers below
/// are the original PumpCorpFactoryLib encoding, copied verbatim and kept independent of the
/// library under test. A change to the library that alters the digest fails these tests./// @title Digest equivalence for the shared deployment metadata library
/// @notice PumpCorpFactory moved from its own PumpCorpFactoryLib to CorpFactoryMetadataLib. Officer
/// signatures already exist for the old encoding, so the digest must not change. LegacyPumpMetadataLib
/// above is that original encoding, copied verbatim and independent of the library under test. A
/// change to the library that alters the digest fails these tests.
contract CorpFactoryMetadataLibTest is Test {
    function test_TypehashesAreUnchanged() public pure {
        assertEq(
            CorpFactoryMetadataLib.FACTORY_DOMAIN_TYPEHASH,
            LegacyPumpMetadataLib.FACTORY_DOMAIN_TYPEHASH,
            "domain typehash changed"
        );
        assertEq(
            CorpFactoryMetadataLib.OFFICER_TYPEHASH,
            LegacyPumpMetadataLib.OFFICER_TYPEHASH,
            "officer typehash changed"
        );
        assertEq(
            CorpFactoryMetadataLib.CERT_DATA_TYPEHASH,
            LegacyPumpMetadataLib.CERT_DATA_TYPEHASH,
            "cert typehash changed"
        );
        assertEq(
            CorpFactoryMetadataLib.ROUND_SUPPLEMENTAL_TYPEHASH,
            LegacyPumpMetadataLib.ROUND_SUPPLEMENTAL_TYPEHASH,
            "supplemental typehash changed"
        );
    }




    function test_DomainSeparationBetweenFactories() public view {
        CorpFactoryMetadataLib.RoundSupplementalData memory d;
        _fillSample(d, false);

        bytes32 pump = _newDigest("PumpCorpFactory", address(0xBEEF), d);
        assertTrue(
            pump != _newDigest("CyberCorpFactory", address(0xBEEF), d),
            "the domain name must separate the factories"
        );
        assertTrue(
            pump != _newDigest("PumpCorpFactory", address(0xCAFE), d),
            "the verifying contract must separate the deployments"
        );
    }


    /// @dev One digest call per function. Two 17-word encodes in the same frame do not fit the stack.
    function _newDigest(
        string memory domainName,
        address verifyingContract,
        CorpFactoryMetadataLib.RoundSupplementalData memory d
    ) private view returns (bytes32) {
        return CorpFactoryMetadataLib.digest(domainName, verifyingContract, d);
    }



    /// @dev Fills `d` in place. A memory struct is a reference, so returning one instead would add a
    /// 16-value copy that does not fit the stack.
    function _fillSample(CorpFactoryMetadataLib.RoundSupplementalData memory d, bool emptyArrays)
        private
        pure
    {
        d.corpSalt = keccak256("salt");
        d.companyPayable = address(0xF00D);
        d.publicRound = true;
        d.allowTimedOffers = true;
        d.restrictEndTimeReduction = false;
        d.officer.eoa = address(0x5678);
        d.officer.name = "Officer A";
        d.officer.contact = "officer@corp.com";
        d.officer.title = "CEO";
        d.companyName = "Signed Company Name";
        d.companyType = "C-Corp";
        d.companyJurisdiction = "DE";
        d.companyContactDetails = "contact@seedcorp.com";
        d.defaultDisputeResolution = "Arbitration";

        if (emptyArrays) {
            d.extensionData = new bytes[](0);
            d.roundPartyValues = new string[](0);
            d.legalDetails = new string[](0);
            d.certData = new RM_CyberCertData[](0);
            d.conditionAddresses = new address[](1);
            return;
        }

        d.extensionData = new bytes[](2);
        d.extensionData[0] = hex"dead";
        d.extensionData[1] = bytes("");

        d.roundPartyValues = new string[](2);
        d.roundPartyValues[0] = "Officer A";
        d.roundPartyValues[1] = "0x0376aac07ad725e01357b1725b5cec61ae10473c";

        d.legalDetails = new string[](1);
        d.legalDetails[0] = "SEED SAFE legal details";

        d.conditionAddresses = new address[](2);
        d.conditionAddresses[0] = address(0xABCD);
        d.conditionAddresses[1] = address(0);

        d.certData = new RM_CyberCertData[](2);
        _fillCert(d.certData[0], true);
        _fillCert(d.certData[1], false);
    }

    function _fillCert(RM_CyberCertData memory cd, bool restricted) private pure {
        if (restricted) {
            cd.name = "SEED SAFE";
            cd.symbol = "SEEDSAFE";
            cd.uri = "ipfs://seed-safe";
            cd.securityClass = SecurityClass.SAFE;
            cd.securitySeries = SecuritySeries.SeriesSeed;
            cd.extension = address(0x1234);
            cd.seriesData = hex"c0ffee";
            cd.defaultLegend = new string[](2);
            cd.defaultLegend[0] = "RESTRICTED";
            cd.defaultLegend[1] = "NOT TRANSFERABLE WITHOUT ISSUER CONSENT";
            return;
        }
        cd.name = "PREFERRED";
        cd.symbol = "PREF";
        cd.uri = "ipfs://pref";
        cd.securityClass = SecurityClass.PreferredStock;
        cd.securitySeries = SecuritySeries.SeriesA;
        cd.extension = address(0);
        cd.seriesData = bytes("");
        cd.defaultLegend = new string[](0);
    }
}
