// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {CompanyOfficer} from "../CyberCorpConstants.sol";
import {CyberCertData as RM_CyberCertData} from "../storage/RoundManagerStorage.sol";

/// @notice Officer authorization over the deployment metadata of a corp-and-round deployment.
/// @dev The escrowed round signature covers the round economics only. It binds the RoundManager
/// address and the CyberCorp address, and both come from the salt. It does not cover the payout
/// address, the conditions, the certificate configuration or the agreement values. A top-level
/// factory that takes those fields from the caller must verify this second signature over them.
/// Each factory passes its own EIP-712 domain name, so a signature made for one factory does not
/// verify on another.
library CorpFactoryMetadataLib {
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

    /// @notice The deployment metadata that the escrowed round signature does not cover.
    struct RoundSupplementalData {
        bytes32 corpSalt;
        address companyPayable;
        bool publicRound;
        bool allowTimedOffers;
        bool restrictEndTimeReduction;
        CompanyOfficer officer;
        string companyName;
        string companyType;
        string companyJurisdiction;
        string companyContactDetails;
        string defaultDisputeResolution;
        bytes[] extensionData;
        string[] roundPartyValues;
        string[] legalDetails;
        RM_CyberCertData[] certData;
        address[] conditionAddresses;
    }

    /// @notice EIP-712 helper for encoding an array of addresses
    /// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-712.md#definition-of-encodedata
    function hashAddresses(address[] memory addrs) internal pure returns (bytes32) {
        bytes32[] memory padded = new bytes32[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            padded[i] = bytes32(uint256(uint160(addrs[i])));
        }
        return keccak256(abi.encodePacked(padded));
    }

    function hashStringArray(string[] memory data) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hashes[i] = keccak256(bytes(data[i]));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashBytesArray(bytes[] memory data) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hashes[i] = keccak256(data[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashCertData(RM_CyberCertData memory cd) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            CERT_DATA_TYPEHASH,
            keccak256(bytes(cd.name)),
            keccak256(bytes(cd.symbol)),
            keccak256(bytes(cd.uri)),
            cd.securityClass,
            cd.securitySeries,
            cd.extension,
            keccak256(cd.seriesData),
            hashStringArray(cd.defaultLegend)
        ));
    }

    function hashCertDataArray(RM_CyberCertData[] memory data) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            hashes[i] = hashCertData(data[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function hashOfficer(CompanyOfficer memory officer) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            OFFICER_TYPEHASH,
            officer.eoa,
            keccak256(bytes(officer.name)),
            keccak256(bytes(officer.contact)),
            keccak256(bytes(officer.title))
        ));
    }

    /// @notice Builds the EIP-712 digest for the deployment metadata.
    /// @param domainName EIP-712 domain name of the calling factory
    /// @param verifyingContract The calling factory
    function digest(
        string memory domainName,
        address verifyingContract,
        RoundSupplementalData memory data
    ) internal view returns (bytes32) {
        bytes32 domainSep = keccak256(abi.encode(
            FACTORY_DOMAIN_TYPEHASH,
            keccak256(bytes(domainName)),
            keccak256(bytes("1")),
            block.chainid,
            verifyingContract
        ));
        bytes32 structHash = keccak256(abi.encode(
            ROUND_SUPPLEMENTAL_TYPEHASH,
            data.corpSalt,
            data.companyPayable,
            data.publicRound,
            data.allowTimedOffers,
            data.restrictEndTimeReduction,
            hashOfficer(data.officer),
            keccak256(bytes(data.companyName)),
            keccak256(bytes(data.companyType)),
            keccak256(bytes(data.companyJurisdiction)),
            keccak256(bytes(data.companyContactDetails)),
            keccak256(bytes(data.defaultDisputeResolution)),
            hashBytesArray(data.extensionData),
            hashStringArray(data.roundPartyValues),
            hashStringArray(data.legalDetails),
            hashCertDataArray(data.certData),
            hashAddresses(data.conditionAddresses)
        ));
        return keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
    }

    /// @notice True when `signature` is the officer's signature over the deployment metadata.
    /// @dev tryRecover, so a malformed signature is a plain false. The caller supplies the bytes,
    /// and every rejection reason gets the same answer.
    function isValid(
        string memory domainName,
        address verifyingContract,
        RoundSupplementalData memory data,
        bytes memory signature
    ) internal view returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) =
            ECDSA.tryRecover(digest(domainName, verifyingContract, data), signature);
        return err == ECDSA.RecoverError.NoError && recovered == data.officer.eoa;
    }
}
