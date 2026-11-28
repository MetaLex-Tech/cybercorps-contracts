// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {PostOfferParams} from "../../src/storage/SecondaryTradeStorage.sol";

/// @notice Signs the offeror's OfferorAgreement for a secondary offer, as the webapp does before postOffer.
library OfferorAgreementSigner {
    // Must byte-match SecondaryTradeStorage.OFFEROR_AGREEMENT_TYPEHASH.
    bytes32 constant TYPEHASH = keccak256(
        "OfferorAgreement(address offeror,uint8 side,address certPrinter,uint256 tokenId,uint256 units,address paymentToken,uint256 consideration,uint8 exemptionPathway,uint256 validUntil,bytes counterpartyRestrictions,bytes additionalTerms,bytes32 templateId,uint256 salt,string[] globalValues,string[] offerorPartyValues)"
    );

    function sign(Vm vm, address dealManager, address offeror, uint256 key, PostOfferParams memory p)
        internal
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("DealManager"),
            keccak256("1"),
            block.chainid,
            dealManager
        ));
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(key, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash(offeror, p))));
        return abi.encodePacked(r, s, v);
    }

    function structHash(address offeror, PostOfferParams memory p) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            TYPEHASH,
            offeror,
            uint8(p.side),
            p.certPrinter,
            p.tokenId,
            p.units,
            p.paymentToken,
            p.consideration,
            uint8(p.exemptionPathway),
            p.validUntil,
            keccak256(p.counterpartyRestrictions),
            keccak256(p.additionalTerms),
            p.templateId,
            p.salt,
            _hashStrings(p.globalValues),
            _hashStrings(p.offerorPartyValues)
        ));
    }

    function _hashStrings(string[] memory arr) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) hashes[i] = keccak256(bytes(arr[i]));
        return keccak256(abi.encodePacked(hashes));
    }
}
