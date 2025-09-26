 
/* All software, documentation and other files and information in this repository (collectively, the "Software")
 are copyright MetaLeX Labs, Inc., a Delaware corporation.
 
 All rights reserved.
 
 The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published, 
 distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
 mechanical, including photocopying, recording, or by any information storage and retrieval system, 
 except with the express prior written permission of the copyright holder.*/
 
 pragma solidity ^0.8.28;

 //import cybercorp constants
 import "../CyberCorpConstants.sol";
 import "./IIssuanceManager.sol";
 
 enum RoundType {
     FCFS,
     FounderApproved
 }

 struct Round {
    bytes32 id;
    string seriesType;
    uint256 raiseCap;
    uint256 minTicket;
    uint256 maxTicket;
    RoundType roundType;
    uint256 startTime;
    uint256 endTime;
    bytes32 templateId;
    address[] certPrinter;
    address paymentToken;
    uint256 pricePerUnit;
    uint256 valuation;
    uint256 raised;
    // Normalized round price and primary security sold to new money
    uint256 roundPricePerShare; // normalized to priceDecimals
    uint8 roundPriceDecimals;
    SecurityClass primarySecurityClass;
    SecuritySeries primarySecuritySeries;
    address authorityOfficer;
    string[] roundPartyValues;
    bytes escrowedSignature;
}

struct CyberCertData {
    string name;
    string symbol;
    string uri;
    SecurityClass securityClass;
    SecuritySeries securitySeries;
    address extension;
    string[] defaultLegend;
}

struct EOI {
    string name;
    string investorType;
    string jurisdiction;
    string contact;
    uint256 minAmount;
    uint256 maxAmount;
}
 
interface IRoundManager {
    event RoundCreated(bytes32 indexed roundId, address corp, Round round, bool publicRound);
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
    event EOISubmitted(bytes32 indexed agreementId, bytes32 indexed roundId, address investor, address indexed corp, uint256 minAmount, uint256 maxAmount, uint256 expiry);
    event AllocationMade(bytes32 indexed agreementId, bytes32 indexed roundId, uint256 allocatedAmount, uint256 totalRaised, uint256[] certIds);
    event EOIRejected(bytes32 indexed agreementId, bytes32 indexed roundId);

    function createRound(
        SecuritySeries seriesType,
        uint256 raiseCap,
        uint256 minTicket,
        uint256 maxTicket,
        RoundType roundType,
        uint256 startTime,
        uint256 endTime,
        bytes32 templateId,
        CyberCertData[] calldata certData,
        address[] calldata conditions,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 valuation,
        address authorityOfficer,
        string calldata officerName,
        string calldata officerTitle,
        string calldata legalDetails,
        bytes calldata extensionData,
        string[] calldata roundPartyValues,
        bytes calldata escrowedSignature,
        bool publicRound
    ) external returns (bytes32 roundId);

    function submitEOI(
        bytes32 roundId,
        EOI calldata eoi,
        string[] calldata globalValues,
        string[] calldata partyValues,
        bytes calldata signature,
        uint256 salt,
        address[] calldata conditions,
        bytes32 secretHash
    ) external returns (bytes32 agreementId);

    function allocate(bytes32 agreementId, uint256 allocatedAmount) external;

    function reject(bytes32 agreementId) external;

    function issuanceManager() external view returns (IIssuanceManager);

    function setRoundEndTime(bytes32 roundId, uint256 newEndTime) external;

    function closeRoundNow(bytes32 roundId) external;

    function getCapTableSnapshotFields(bytes32 roundId)
        external view
        returns (
            uint256 totalCapitalSecuritiesOutstanding,
            uint256 totalConvertingSecurities,
            uint256 totalOptionsIssuedAndOutstanding,
            uint256 totalPromisedOptions,
            uint256 unissuedOptionPoolPreRound,
            uint256 unissuedOptionPoolIncreaseIncludedInCalc,
            uint256 cCapUsed
        );

    function getRoundingPolicyFields(bytes32 roundId)
        external view
        returns (uint8 mode, uint8 priceDecimals, uint8 shareDecimals);

    function getRoundPriceInfo(bytes32 roundId)
        external view
        returns (uint256 roundPricePerShare, uint8 roundPriceDecimals);

    function getPrimarySecurity(bytes32 roundId)
        external view
        returns (SecurityClass cls, SecuritySeries series);

    function roundExists(bytes32 roundId) external view returns (bool);

    function getPMVCSubseriesLabel(bytes32 roundId, uint256 pmvc) external view returns (string memory);

    function recallEOI(bytes32 agreementId) external;
} 