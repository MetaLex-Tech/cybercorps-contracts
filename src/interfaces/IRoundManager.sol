/* All software, documentation and other files and information in this repository (collectively, the "Software")
 are copyright MetaLeX Labs, Inc., a Delaware corporation.
 
 All rights reserved.
 
 The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
 distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
 mechanical, including photocopying, recording, or by any information storage and retrieval system, 
 except with the express prior written permission of the copyright holder.*/
 
 pragma solidity ^0.8.28;

 import "../CyberCorpConstants.sol";
 import "./IIssuanceManager.sol";
 import "../libs/RoundLib.sol";
 import "../storage/RoundManagerStorage.sol";
 
 interface IRoundManager {
    event RoundCreated(bytes32 indexed roundId, address indexed corp, Round round, bool publicRound);
    event RoundSnapshotSet(
        bytes32 indexed roundId,
        uint256 totalCapitalSecuritiesOutstanding,
        uint256 totalConvertingSecurities,
        uint256 totalOptionsIssuedAndOutstanding,
        uint256 totalPromisedOptions,
        uint256 unissuedOptionPoolPreRound,
        uint256 unissuedOptionPoolIncreaseIncludedInCalc,
        uint256 cCapUsed
    );
    event RoundingPolicySet(bytes32 indexed roundId, uint8 mode, uint8 priceDecimals, uint8 shareDecimals);
    event PMVCSubseriesLabelSet(bytes32 indexed roundId, uint256 pmvc, string label);
    event RoundEndTimeUpdated(bytes32 indexed roundId, uint256 oldEndTime, uint256 newEndTime);
    event RoundClosed(bytes32 indexed roundId, uint256 closedAt);
    event EOISubmitted(bytes32 agreementId, bytes32 indexed roundId, address investor, address indexed corp, uint256 minAmount, uint256 maxAmount, uint256 expiry);
    event AllocationMade(bytes32 agreementId, bytes32 indexed roundId, address indexed buyer, uint256 allocatedAmount, uint256 totalRaised, uint256[] certIds);
    event EOIRejected(bytes32 agreementId, address indexed investor, bytes32 indexed roundId);

    function DEPLOY_VERSION() external view returns (string memory);

    function createRound(
        Round memory roundDraft,
        CyberCertData[] memory certData
    ) external returns (bytes32 roundId);

    function submitEOI(
        bytes32 roundId,
        EOI memory eoi,
        string[] memory globalValues,
        string[] memory partyValues,
        bytes memory signature,
        uint256 salt,
        address[] memory conditions,
        bytes32 secretHash
    ) external returns (bytes32 agreementId, uint256 tokenId);

    function allocate(bytes32 agreementId, uint256 allocatedAmount) external returns (uint256 tokenId);

    function reject(bytes32 agreementId) external;
    function reject(bytes32 agreementId, bool isVoidAgreement) external;

    function recallEOI(bytes32 agreementId) external;
    function recallEOI(bytes32 agreementId, bool isVoidAgreement) external;

    function issuanceManager() external view returns (IIssuanceManager);

    function setRoundEndTime(bytes32 roundId, uint256 newEndTime) external;
    function closeRoundNow(bytes32 roundId) external;

    function setRoundPricePerShare(bytes32 roundId, uint256 price, uint8 priceDecimals) external;
    function setPrimarySecurity(bytes32 roundId, SecurityClass cls, SecuritySeries series) external;

    function getRoundPriceInfo(bytes32 roundId)
        external view
        returns (uint256 roundPricePerShare, uint8 roundPriceDecimals);

    function getPrimarySecurity(bytes32 roundId)
        external view
        returns (SecurityClass cls, SecuritySeries series);

    function roundExists(bytes32 roundId) external view returns (bool);

    function computeFee(uint256 size) external view returns (uint256);
    function getPlatformPayable() external view returns (address);

    function setLexChex(address _lexchex) external;
    function getLexChex() external view returns (address);
}