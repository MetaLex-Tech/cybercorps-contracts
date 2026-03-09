/*    .o.
     .888.
    .8"888.
   .8' `888.
  .88ooo8888.
 .8'     `888.
o88o     o8888o



ooo        ooooo               .             ooooo                  ooooooo  ooooo
`88.       .888'             .o8             `888'                   `8888    d8'
 888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P
 8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'
 8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.
 8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b
o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o



  .oooooo.                .o8                            .oooooo.
 d8P'  `Y8b              "888                           d8P'  `Y8b
888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.
888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b
888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888
`88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o.
 `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P
             .o..P'                                                                     888
             `Y8P'                                                                     o888o
_______________________________________________________________________________________________________

All software, documentation and other files and information in this repository (collectively, the "Software")
are copyright MetaLeX Labs, Inc., a Delaware corporation.

All rights reserved.

The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
mechanical, including photocopying, recording, or by any information storage and retrieval system,
except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./ICertificateExtension.sol";
import "../../CyberCorpConstants.sol";
import "../../libs/auth.sol";

// ══════════════════════════════════════════════════════════════════════════════
//  Enums
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Liquidation preference payout structure
enum LiquidationPreferenceType {
    NonParticipating,       // single-dip: greater of preference or as-converted
    Participating,          // double-dip: preference + pro rata share of remainder
    CappedParticipating     // participating, but capped at a multiple of original issue price
}

/// @notice Anti-dilution protection mechanism
enum AntiDilutionType {
    None,
    BroadBasedWeightedAverage,
    NarrowBasedWeightedAverage,
    FullRatchet
}

/// @notice Dividend accrual behavior
enum DividendType {
    None,
    NonCumulative,      // dividends declared at board discretion, unpaid amounts do not accrue
    Cumulative          // dividends accrue whether or not declared
}

/// @notice Transfer restriction regime applicable to shares.
enum TransferRestrictionType {
    None,
    BoardConsentRequired,       // Section 8.9(a) of Bylaws — no transfer without board consent
    ROFRAndCoSale,              // subject to ROFR/Co-Sale agreement
    LockUp,                     // time-based lock-up restriction
    SecuritiesActRestriction,   // Securities Act restricted legend (standard "not registered" legend)
    CustomRestriction           // custom restriction defined by agreement or board resolution
}

/// @notice Redemption mechanism type
enum RedemptionType {
    None,
    HolderOptional,
    CompanyOptional,
    Mandatory,
    EventTriggered
}

/// @notice Types of mandatory/automatic conversion triggers
enum MandatoryConversionTriggerType {
    QualifiedIPO,
    ClassVote,
    DeemedLiquidation,
    Custom
}

/// @notice Scope of a voting right — distinguishes class-wide votes from series-specific votes.
/// Under DGCL section 151(a), the certificate of incorporation may provide that holders of any
/// class or series shall vote as a separate class or series.
enum VotingScope {
    ClassWide,          // all series sharing the same shareClassKey vote together
    SeriesSpecific      // only this series votes
}

/// @notice Share representation form (DGCL §158)
enum ShareRepresentationType {
    Certificated,       // traditional paper or PDF certificate
    Uncertificated,     // book-entry (DGCL §158 uncertificated shares)
    Tokenized           // on-chain tokenized representation
}

// ══════════════════════════════════════════════════════════════════════════════
//  Structs
// ══════════════════════════════════════════════════════════════════════════════

/// @notice Mandatory/automatic conversion trigger definition.
/// Supports compound conditions (e.g., QualifiedIPO requires price AND proceeds AND listing).
struct MandatoryConversionTrigger {
    MandatoryConversionTriggerType triggerType;
    uint256 primaryThreshold;       // e.g., IPO price per share threshold (18 dec)
    uint256 secondaryThreshold;     // e.g., minimum aggregate proceeds threshold (18 dec); 0 if single-condition
    string additionalConditions;    // human-readable additional conditions (e.g., "listed on NYSE or NASDAQ")
    string description;             // human-readable description of the full trigger condition
}

/// @notice Matter-specific voting right (used for protective provisions and special class/series votes)
struct SpecialVotingRight {
    bytes32 matterType;     // e.g., MATTER_CHARTER_AMENDMENT, MATTER_MERGER_APPROVAL, etc.
    uint256 votesPerShare;  // votes per share for this specific matter (18 decimals)
    uint256 threshold;      // approval threshold (4 decimal percentage, e.g. 5010 = 50.1%)
    bool isVetoRight;       // true = blocking/consent right rather than affirmative vote
    VotingScope scope;      // whether this right is exercised at the class level or series level
    string description;     // human-readable description
}

/// @notice Exception to a transfer restriction (Bylaws section 8.9(b) compliance)
struct TransferRestrictionException {
    bytes32 exceptionType;      // e.g., keccak256("ESTATE_PLANNING_TRANSFER"), keccak256("AFFILIATE_TRANSFER")
    string exceptionText;       // human-readable description of the exception
    bool requiresEvidence;      // whether evidence must be presented for this exception to apply
}

/// @notice A single transfer restriction with full legal text (DGCL section 202 compliance)
struct TransferRestriction {
    TransferRestrictionType restrictionType;
    string restrictionText;     // actual legal legend / restriction notice text
    string sourceAgreement;     // pointer to imposing agreement (e.g., "Bylaws section 8.9")
    bool isRemovable;           // whether this restriction can be removed (e.g., Rule 144 legend removal)
    TransferRestrictionException[] exceptions;  // carved-out exceptions to this restriction
}

/// @notice Record of a stock split applied to a series
struct SplitRecord {
    uint256 numerator;          // split ratio numerator (e.g., 10000 for a 10,000:1 split)
    uint256 denominator;        // split ratio denominator (e.g., 1)
    uint256 timestamp;          // when the split was recorded
    string sourceAuthorityURI;  // pointer to the board resolution or charter amendment authorizing the split
}

/// @notice Canonical series-wide terms, stored once per class/series.
/// All price/value fields use 18-decimal precision.
/// Percentage fields use 4-decimal precision (10**4 basis, 5010 = 50.10%).
/// NOTE: Dynamic arrays (mandatoryConversionTriggers, specialVotingRights, transferRestrictions)
/// are stored in separate mappings and managed via dedicated CRUD functions.
struct SeriesTerms {
    // --- Identity & Classification ---
    bytes32 shareClassKey;              // extensible class identifier (use CLASS_COMMON, CLASS_PREFERRED, or custom)
    string seriesName;                  // human-readable display name
    uint256 parValue;                   // par value per share (18 decimals)
    uint256 authorizedShares;           // total authorized shares for this class/series
    uint256 originalIssuePrice;         // price per share at issuance (18 decimals)
    uint256 effectiveDate;              // timestamp when these terms became effective
    string sourceAuthorityURI;          // pointer to charter provision, board resolution, or amendment

    // --- Liquidation Preference & Seniority ---
    uint256 liquidationPreferenceMultiple; // multiple of OIP (18 decimals; 1e18 = 1x)
    LiquidationPreferenceType liquidationPreferenceType;
    uint256 participationCap;           // if CappedParticipating, max multiple of OIP (18 decimals); 0 otherwise
    uint256 seniorityRank;              // lower = more senior; equal rank = pari passu

    // --- Dividends ---
    DividendType dividendType;
    uint256 dividendRate;               // annual rate (18 decimals, 8% = 8e16); 0 if None
    uint256 dividendAccrualStartDate;   // timestamp; relevant for cumulative dividends
    bool dividendCompounding;           // true = compound accrual; false = simple accrual
    bool dividendIncreasesLiquidationAmount; // whether accrued unpaid dividends add to liquidation preference

    // --- Conversion ---
    bool isConvertible;
    bytes32 targetConversionSeriesId;   // seriesId of the target class/series for conversion
    uint256 conversionPrice;            // current conversion price (18 decimals); ratio = OIP / conversionPrice
    AntiDilutionType antiDilutionType;
    bool allowsFractionalConversion;    // whether fractional shares may be issued on conversion
    bool hasMandatoryConversion;
    // NOTE: mandatoryConversionTriggers stored separately in _conversionTriggers mapping

    // --- Voting ---
    uint256 votesPerShare;              // default votes per share (18 decimals, 1e18 = 1 vote); 0 = non-voting
    uint8 designatedBoardSeats;         // board seats this series is entitled to elect
    bool hasClassVotingRights;          // whether this series participates in class-wide separate votes
    bool hasSeriesVotingRights;         // whether this series can vote separately as its own series
    // NOTE: specialVotingRights stored separately in _specialVotingRights mapping

    // --- Transfer Restrictions ---
    // NOTE: transferRestrictions stored separately in _transferRestrictions mapping

    // --- Redemption ---
    bool isRedeemable;
    RedemptionType redemptionType;
    uint256 redemptionPrice;            // redemption price per share (18 decimals)
    string redemptionSchedule;          // human-readable or URI to redemption schedule/terms
    string redemptionTriggerDescription; // for EventTriggered: description of the triggering event

    // --- NVCA Optional Fields ---
    bool hasPayToPlay;                  // whether pay-to-play provisions apply
    string payToPlayTermsURI;           // pointer to pay-to-play terms
    bool hasRegistrationRights;         // whether registration rights exist
    string registrationRightsURI;       // pointer to registration rights agreement
    bool hasProRataRights;              // whether pro-rata participation rights exist
    bool hasInformationRights;          // whether information rights exist
    bool hasDragAlongRights;            // whether drag-along rights exist
    string dragAlongTermsURI;           // pointer to drag-along terms
}

/// @notice Per-certificate metadata. References canonical SeriesTerms via seriesId.
/// Legends are stored in dedicated mappings, not in this struct, to allow individual add/remove.
struct CertificateData {
    bytes32 seriesId;               // pointer to canonical SeriesTerms
    uint256 certificateNumber;      // unique certificate number (may equal token ID but explicitly tracked)
    uint256 numberOfShares;         // number of shares represented by this certificate
    uint256 issueDate;              // timestamp of issuance
    bool isPartlyPaid;              // whether shares are partly paid (Bylaws section 8.5, DGCL section 156)
    uint256 amountPaid;             // if partly paid, amount actually paid (18 decimals)
    uint256 totalConsideration;     // if partly paid, total consideration to be paid (18 decimals)
    string sourceAuthorityURI;      // per-certificate pointer to board resolution, subscription agreement, etc.
    ShareRepresentationType representationType;  // form of share representation (DGCL §158)
    uint256 holdingPeriodStartDate;              // Rule 144(d) holding period start (may differ from issueDate due to tacking)
    bool holdingPeriodTackingApplied;            // whether tacking was applied to the holding period
}

// ══════════════════════════════════════════════════════════════════════════════
//  Contract
// ══════════════════════════════════════════════════════════════════════════════

contract ShareExtension is UUPSUpgradeable, ICertificateExtension, BorgAuthACL {

    // ──────────────────────────────────────────────────────────────
    //  Constants
    // ──────────────────────────────────────────────────────────────

    bytes32 public constant EXTENSION_TYPE = keccak256("SHARE");
    uint256 public constant PERCENTAGE_PRECISION = 10 ** 4;
    uint256 public constant PRICE_PRECISION = 10 ** 18;

    /// @notice Extensible share class identifiers (use arbitrary bytes32 for exotic classes)
    bytes32 public constant CLASS_COMMON = keccak256("COMMON");
    bytes32 public constant CLASS_PREFERRED = keccak256("PREFERRED");

    /// @notice Protective provision matter type constants (COI §3.3 categories)
    bytes32 public constant MATTER_CHARTER_AMENDMENT = keccak256("CHARTER_AMENDMENT");
    bytes32 public constant MATTER_MERGER_APPROVAL = keccak256("MERGER_APPROVAL");
    bytes32 public constant MATTER_ASSET_SALE = keccak256("ASSET_SALE");
    bytes32 public constant MATTER_NEW_SERIES_ISSUANCE = keccak256("NEW_SERIES_ISSUANCE");
    bytes32 public constant MATTER_DIVIDEND_DECLARATION = keccak256("DIVIDEND_DECLARATION");
    bytes32 public constant MATTER_LIQUIDATION = keccak256("LIQUIDATION");
    bytes32 public constant MATTER_DEBT_INCURRENCE = keccak256("DEBT_INCURRENCE");
    bytes32 public constant MATTER_RELATED_PARTY_TRANSACTION = keccak256("RELATED_PARTY_TRANSACTION");

    /// @notice Standard Securities Act restricted legend text (Rule 144 / §5 compliance)
    string public constant SECURITIES_ACT_LEGEND =
        "THE SECURITIES REPRESENTED HEREBY HAVE NOT BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, "
        "AS AMENDED (THE \"ACT\"), OR UNDER THE SECURITIES LAWS OF ANY STATE. THESE SECURITIES ARE "
        "SUBJECT TO RESTRICTIONS ON TRANSFERABILITY AND RESALE AND MAY NOT BE TRANSFERRED OR RESOLD "
        "EXCEPT AS PERMITTED UNDER THE ACT AND APPLICABLE STATE SECURITIES LAWS, PURSUANT TO "
        "REGISTRATION OR EXEMPTION THEREFROM.";

    // ──────────────────────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────────────────────

    event SeriesCreated(bytes32 indexed seriesId, bytes32 indexed shareClassKey, string seriesName);
    event SeriesTermsUpdated(bytes32 indexed seriesId, uint256 newVersion, bytes32 oldTermsHash);
    event ConversionPriceAdjusted(bytes32 indexed seriesId, uint256 oldPrice, uint256 newPrice);
    event AuthorizedSharesChanged(bytes32 indexed seriesId, uint256 oldAmount, uint256 newAmount);
    event StockSplitRecorded(
        bytes32 indexed seriesId, uint256 numerator, uint256 denominator,
        uint256 oldOIP, uint256 newOIP, uint256 oldParValue, uint256 newParValue
    );
    event ConversionTriggerAdded(bytes32 indexed seriesId, uint256 index);
    event ConversionTriggerRemoved(bytes32 indexed seriesId, uint256 index);
    event SpecialVotingRightAdded(bytes32 indexed seriesId, uint256 index, bytes32 matterType);
    event SpecialVotingRightRemoved(bytes32 indexed seriesId, uint256 index, bytes32 matterType);
    event TransferRestrictionAdded(bytes32 indexed seriesId, uint256 index);
    event TransferRestrictionRemoved(bytes32 indexed seriesId, uint256 index);
    event LegendAdded(uint256 indexed tokenId, uint256 legendIndex, bytes32 legendHash);
    event LegendRemoved(uint256 indexed tokenId, uint256 legendIndex, bytes32 legendHash);
    event LegendRemovalRequested(uint256 indexed tokenId, uint256 legendIndex, string justification);
    event IssuerNameUpdated(string oldName, string newName);
    event StateOfIncorporationUpdated(string oldState, string newState);

    // ──────────────────────────────────────────────────────────────
    //  State variables
    //  NOTE: These occupy the same storage slots as the former __gap[30].
    //  Slots used + reserved = 30 total (preserves layout).
    // ──────────────────────────────────────────────────────────────

    /// @notice Canonical series terms registry
    mapping(bytes32 => SeriesTerms) internal _seriesRegistry;           // slot 0
    /// @notice Ordered list of series IDs for enumeration
    bytes32[] public seriesIds;                                          // slot 1
    /// @notice O(1) existence check for series
    mapping(bytes32 => bool) public seriesExists;                       // slot 2
    /// @notice Per-certificate legend texts keyed by token ID
    mapping(uint256 => string[]) internal _certificateLegends;          // slot 3
    /// @notice Parallel array of legend hashes for efficient on-chain verification
    mapping(uint256 => bytes32[]) internal _certificateLegendHashes;    // slot 4
    /// @notice Issuer name — changeable by board/owner (covers name changes, mergers)
    string public issuerName;                                            // slot 5

    // --- Phase 1 new storage (slots 6-14) ---

    /// @notice Separated dynamic arrays: mandatory conversion triggers per series
    mapping(bytes32 => MandatoryConversionTrigger[]) internal _conversionTriggers;    // slot 6
    /// @notice Separated dynamic arrays: special voting rights per series
    mapping(bytes32 => SpecialVotingRight[]) internal _specialVotingRights;           // slot 7
    /// @notice Separated dynamic arrays: transfer restrictions per series
    mapping(bytes32 => TransferRestriction[]) internal _transferRestrictions;          // slot 8
    /// @notice Series terms version counter (incremented on each update)
    mapping(bytes32 => uint256) public seriesTermsVersion;                            // slot 9
    /// @notice Historical terms hashes: seriesId => version => keccak256 of old terms
    mapping(bytes32 => mapping(uint256 => bytes32)) public seriesTermsHistoryHashes;  // slot 10
    /// @notice Stock split history per series
    mapping(bytes32 => SplitRecord[]) internal _splitHistory;                         // slot 11
    /// @notice State of incorporation (DGCL §158 compliance)
    string public stateOfIncorporation;                                               // slot 12

    /// @dev Reserved storage for future upgrades
    uint256[17] private __gap;                                           // slots 13-29

    // ──────────────────────────────────────────────────────────────
    //  Initialization
    // ──────────────────────────────────────────────────────────────

    function initialize(address _auth) external initializer {
        __UUPSUpgradeable_init();
        __BorgAuthACL_init(_auth);
    }

    // ══════════════════════════════════════════════════════════════
    //  Series Management (onlyOwner / board-authorized)
    // ══════════════════════════════════════════════════════════════

    /// @notice Register a new series with canonical terms.
    /// Dynamic arrays (triggers, voting rights, restrictions) must be added via dedicated CRUD functions after creation.
    function createSeries(bytes32 seriesId, SeriesTerms memory terms) external onlyOwner {
        require(seriesId != bytes32(0), "ShareExtension: zero seriesId");
        require(!seriesExists[seriesId], "ShareExtension: series already exists");

        (bool valid, string memory err) = _validateSeriesTermsInternal(terms);
        require(valid, err);

        _seriesRegistry[seriesId] = terms;
        seriesIds.push(seriesId);
        seriesExists[seriesId] = true;
        seriesTermsVersion[seriesId] = 1;

        emit SeriesCreated(seriesId, terms.shareClassKey, terms.seriesName);
    }

    /// @notice Replace the full scalar terms for an existing series.
    /// Increments version, hashes old terms, emits versioned event.
    function updateSeriesTerms(bytes32 seriesId, SeriesTerms memory terms) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");

        (bool valid, string memory err) = _validateSeriesTermsInternal(terms);
        require(valid, err);

        // Version and hash the old terms before overwriting
        uint256 currentVersion = seriesTermsVersion[seriesId];
        bytes32 oldHash = keccak256(abi.encode(_seriesRegistry[seriesId]));
        seriesTermsHistoryHashes[seriesId][currentVersion] = oldHash;

        _seriesRegistry[seriesId] = terms;
        seriesTermsVersion[seriesId] = currentVersion + 1;

        emit SeriesTermsUpdated(seriesId, currentVersion + 1, oldHash);
    }

    /// @notice Update conversion price independently (e.g., anti-dilution adjustment)
    function updateConversionPrice(bytes32 seriesId, uint256 newPrice) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        SeriesTerms storage s = _seriesRegistry[seriesId];
        require(s.isConvertible, "ShareExtension: series is not convertible");
        require(newPrice > 0, "ShareExtension: conversionPrice must be > 0");

        uint256 oldPrice = s.conversionPrice;
        s.conversionPrice = newPrice;

        emit ConversionPriceAdjusted(seriesId, oldPrice, newPrice);
    }

    /// @notice Update authorized shares independently (e.g., charter amendment)
    function updateAuthorizedShares(bytes32 seriesId, uint256 newAmount) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        require(newAmount > 0, "ShareExtension: authorizedShares must be > 0");

        SeriesTerms storage s = _seriesRegistry[seriesId];
        uint256 oldAmount = s.authorizedShares;
        s.authorizedShares = newAmount;

        emit AuthorizedSharesChanged(seriesId, oldAmount, newAmount);
    }

    /// @notice Update series display name
    function updateSeriesName(bytes32 seriesId, string calldata newName) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        _seriesRegistry[seriesId].seriesName = newName;
    }

    // ══════════════════════════════════════════════════════════════
    //  Stock Split Management
    // ══════════════════════════════════════════════════════════════

    /// @notice Record a stock split and atomically adjust all price/share fields.
    /// @param seriesId The series to adjust
    /// @param splitNumerator The numerator of the split ratio (e.g., 10000 for 10,000:1)
    /// @param splitDenominator The denominator of the split ratio (e.g., 1)
    /// @param sourceAuthorityURI Pointer to the board resolution or charter amendment
    function recordStockSplit(
        bytes32 seriesId,
        uint256 splitNumerator,
        uint256 splitDenominator,
        string calldata sourceAuthorityURI
    ) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        require(splitNumerator > 0 && splitDenominator > 0, "ShareExtension: split ratio must be non-zero");
        require(splitNumerator != splitDenominator, "ShareExtension: split ratio must differ from 1:1");

        SeriesTerms storage s = _seriesRegistry[seriesId];

        uint256 oldOIP = s.originalIssuePrice;
        uint256 oldParValue = s.parValue;

        // Adjust price fields DOWN by numerator/denominator (more shares = lower per-share price)
        s.originalIssuePrice = (s.originalIssuePrice * splitDenominator) / splitNumerator;
        s.parValue = (s.parValue * splitDenominator) / splitNumerator;
        if (s.conversionPrice > 0) {
            s.conversionPrice = (s.conversionPrice * splitDenominator) / splitNumerator;
        }
        if (s.redemptionPrice > 0) {
            s.redemptionPrice = (s.redemptionPrice * splitDenominator) / splitNumerator;
        }

        // Adjust share count UP
        s.authorizedShares = (s.authorizedShares * splitNumerator) / splitDenominator;

        // Adjust conversion trigger thresholds — only price-denominated triggers scale with splits
        MandatoryConversionTrigger[] storage triggers = _conversionTriggers[seriesId];
        for (uint256 i = 0; i < triggers.length; i++) {
            if (triggers[i].triggerType == MandatoryConversionTriggerType.QualifiedIPO && triggers[i].primaryThreshold > 0) {
                triggers[i].primaryThreshold = (triggers[i].primaryThreshold * splitDenominator) / splitNumerator;
            }
            // secondaryThreshold (e.g., aggregate proceeds) is typically not per-share, so not adjusted
        }

        // Record history
        _splitHistory[seriesId].push(SplitRecord({
            numerator: splitNumerator,
            denominator: splitDenominator,
            timestamp: block.timestamp,
            sourceAuthorityURI: sourceAuthorityURI
        }));

        emit StockSplitRecorded(seriesId, splitNumerator, splitDenominator, oldOIP, s.originalIssuePrice, oldParValue, s.parValue);
    }

    /// @notice Record a stock split across multiple series (e.g., class-wide split)
    function recordStockSplitBatch(
        bytes32[] calldata _seriesIds,
        uint256 splitNumerator,
        uint256 splitDenominator,
        string calldata sourceAuthorityURI
    ) external onlyOwner {
        for (uint256 i = 0; i < _seriesIds.length; i++) {
            // Inline the logic to avoid external call overhead; reuse internal checks
            this.recordStockSplit(_seriesIds[i], splitNumerator, splitDenominator, sourceAuthorityURI);
        }
    }

    /// @notice Get split history for a series
    function getSplitHistory(bytes32 seriesId) external view returns (SplitRecord[] memory) {
        return _splitHistory[seriesId];
    }

    // ══════════════════════════════════════════════════════════════
    //  Dynamic Array CRUD — Conversion Triggers
    // ══════════════════════════════════════════════════════════════

    function addConversionTrigger(bytes32 seriesId, MandatoryConversionTrigger memory trigger) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        require(_seriesRegistry[seriesId].isConvertible, "ShareExtension: series is not convertible");
        _conversionTriggers[seriesId].push(trigger);
        emit ConversionTriggerAdded(seriesId, _conversionTriggers[seriesId].length - 1);
    }

    function removeConversionTrigger(bytes32 seriesId, uint256 index) external onlyOwner {
        MandatoryConversionTrigger[] storage triggers = _conversionTriggers[seriesId];
        require(index < triggers.length, "ShareExtension: trigger index out of bounds");
        uint256 lastIdx = triggers.length - 1;
        if (index != lastIdx) {
            triggers[index] = triggers[lastIdx];
        }
        triggers.pop();
        emit ConversionTriggerRemoved(seriesId, index);
    }

    function getConversionTriggers(bytes32 seriesId) external view returns (MandatoryConversionTrigger[] memory) {
        return _conversionTriggers[seriesId];
    }

    function getConversionTriggerCount(bytes32 seriesId) external view returns (uint256) {
        return _conversionTriggers[seriesId].length;
    }

    // ══════════════════════════════════════════════════════════════
    //  Dynamic Array CRUD — Special Voting Rights
    // ══════════════════════════════════════════════════════════════

    function addSpecialVotingRight(bytes32 seriesId, SpecialVotingRight memory right) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        _specialVotingRights[seriesId].push(right);
        emit SpecialVotingRightAdded(seriesId, _specialVotingRights[seriesId].length - 1, right.matterType);
    }

    function removeSpecialVotingRight(bytes32 seriesId, uint256 index) external onlyOwner {
        SpecialVotingRight[] storage rights = _specialVotingRights[seriesId];
        require(index < rights.length, "ShareExtension: voting right index out of bounds");
        bytes32 matterType = rights[index].matterType;
        uint256 lastIdx = rights.length - 1;
        if (index != lastIdx) {
            rights[index] = rights[lastIdx];
        }
        rights.pop();
        emit SpecialVotingRightRemoved(seriesId, index, matterType);
    }

    function getSpecialVotingRights(bytes32 seriesId) external view returns (SpecialVotingRight[] memory) {
        return _specialVotingRights[seriesId];
    }

    function getSpecialVotingRightCount(bytes32 seriesId) external view returns (uint256) {
        return _specialVotingRights[seriesId].length;
    }

    // ══════════════════════════════════════════════════════════════
    //  Dynamic Array CRUD — Transfer Restrictions
    // ══════════════════════════════════════════════════════════════

    function addTransferRestriction(bytes32 seriesId, TransferRestriction memory restriction) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        _transferRestrictions[seriesId].push();
        uint256 idx = _transferRestrictions[seriesId].length - 1;
        TransferRestriction storage stored = _transferRestrictions[seriesId][idx];
        stored.restrictionType = restriction.restrictionType;
        stored.restrictionText = restriction.restrictionText;
        stored.sourceAgreement = restriction.sourceAgreement;
        stored.isRemovable = restriction.isRemovable;
        for (uint256 i = 0; i < restriction.exceptions.length; i++) {
            stored.exceptions.push(restriction.exceptions[i]);
        }
        emit TransferRestrictionAdded(seriesId, idx);
    }

    function removeTransferRestriction(bytes32 seriesId, uint256 index) external onlyOwner {
        TransferRestriction[] storage restrictions = _transferRestrictions[seriesId];
        require(index < restrictions.length, "ShareExtension: restriction index out of bounds");
        uint256 lastIdx = restrictions.length - 1;
        if (index != lastIdx) {
            // Deep copy: swap last into removed slot
            TransferRestriction storage target = restrictions[index];
            TransferRestriction storage last = restrictions[lastIdx];
            target.restrictionType = last.restrictionType;
            target.restrictionText = last.restrictionText;
            target.sourceAgreement = last.sourceAgreement;
            target.isRemovable = last.isRemovable;
            // Clear and copy exceptions
            delete target.exceptions;
            for (uint256 i = 0; i < last.exceptions.length; i++) {
                target.exceptions.push(last.exceptions[i]);
            }
        }
        restrictions.pop();
        emit TransferRestrictionRemoved(seriesId, index);
    }

    function getTransferRestrictions(bytes32 seriesId) external view returns (TransferRestriction[] memory) {
        return _transferRestrictions[seriesId];
    }

    function getTransferRestrictionCount(bytes32 seriesId) external view returns (uint256) {
        return _transferRestrictions[seriesId].length;
    }

    // ══════════════════════════════════════════════════════════════
    //  Certificate Data (ICertificateExtension compatibility)
    // ══════════════════════════════════════════════════════════════

    /// @notice Encode certificate data into extension bytes
    function encodeCertificateData(CertificateData memory data) external pure returns (bytes memory) {
        return abi.encode(data);
    }

    /// @notice Decode certificate data from extension bytes
    function decodeCertificateData(bytes memory data) external pure returns (CertificateData memory) {
        return abi.decode(data, (CertificateData));
    }

    // ══════════════════════════════════════════════════════════════
    //  Legend Management (per-certificate)
    // ══════════════════════════════════════════════════════════════

    /// @notice Add a legend to a specific certificate
    function addLegend(uint256 tokenId, string calldata legendText) external onlyOwner {
        bytes32 h = keccak256(bytes(legendText));
        _certificateLegends[tokenId].push(legendText);
        _certificateLegendHashes[tokenId].push(h);

        emit LegendAdded(tokenId, _certificateLegends[tokenId].length - 1, h);
    }

    /// @notice Remove a legend from a specific certificate by index (swap-and-pop)
    function removeLegend(uint256 tokenId, uint256 legendIndex) external onlyOwner {
        string[] storage legends = _certificateLegends[tokenId];
        bytes32[] storage hashes = _certificateLegendHashes[tokenId];
        require(legendIndex < legends.length, "ShareExtension: legend index out of bounds");

        bytes32 removedHash = hashes[legendIndex];

        uint256 lastIdx = legends.length - 1;
        if (legendIndex != lastIdx) {
            legends[legendIndex] = legends[lastIdx];
            hashes[legendIndex] = hashes[lastIdx];
        }
        legends.pop();
        hashes.pop();

        emit LegendRemoved(tokenId, legendIndex, removedHash);
    }

    /// @notice Request legend removal (informational audit trail; actual removal requires removeLegend)
    function requestLegendRemoval(uint256 tokenId, uint256 legendIndex, string calldata justification) external {
        require(legendIndex < _certificateLegends[tokenId].length, "ShareExtension: legend index out of bounds");
        emit LegendRemovalRequested(tokenId, legendIndex, justification);
    }

    /// @notice Get all legends for a certificate
    function getLegends(uint256 tokenId) external view returns (string[] memory texts, bytes32[] memory hashes) {
        return (_certificateLegends[tokenId], _certificateLegendHashes[tokenId]);
    }

    /// @notice Initialize a certificate's legends from its series' default transfer restrictions
    /// @dev Should be called at mint time to populate initial restriction notices
    function initializeLegends(uint256 tokenId, bytes32 seriesId) external onlyOwner {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");

        TransferRestriction[] storage restrictions = _transferRestrictions[seriesId];
        for (uint256 i = 0; i < restrictions.length; i++) {
            if (bytes(restrictions[i].restrictionText).length > 0) {
                bytes32 h = keccak256(bytes(restrictions[i].restrictionText));
                _certificateLegends[tokenId].push(restrictions[i].restrictionText);
                _certificateLegendHashes[tokenId].push(h);
                emit LegendAdded(tokenId, _certificateLegends[tokenId].length - 1, h);
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    //  Issuer Identity
    // ══════════════════════════════════════════════════════════════

    /// @notice Set or update the issuer name
    function setIssuerName(string calldata _name) external onlyOwner {
        string memory oldName = issuerName;
        issuerName = _name;
        emit IssuerNameUpdated(oldName, _name);
    }

    /// @notice Set or update the state of incorporation (DGCL §158 compliance)
    function setStateOfIncorporation(string calldata _state) external onlyOwner {
        string memory oldState = stateOfIncorporation;
        stateOfIncorporation = _state;
        emit StateOfIncorporationUpdated(oldState, _state);
    }

    // ══════════════════════════════════════════════════════════════
    //  Read Helpers
    // ══════════════════════════════════════════════════════════════

    /// @notice Get full series terms for a given series ID
    function getSeriesTerms(bytes32 seriesId) external view returns (SeriesTerms memory) {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        return _seriesRegistry[seriesId];
    }

    /// @notice Get all registered series IDs
    function getAllSeriesIds() external view returns (bytes32[] memory) {
        return seriesIds;
    }

    /// @notice Get the number of registered series
    function getSeriesCount() external view returns (uint256) {
        return seriesIds.length;
    }

    /// @notice Paginated series ID retrieval
    function getSeriesIdsPaginated(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        uint256 total = seriesIds.length;
        if (offset >= total) {
            return new bytes32[](0);
        }
        uint256 end = offset + limit;
        if (end > total) end = total;
        bytes32[] memory page = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            page[i - offset] = seriesIds[i];
        }
        return page;
    }

    /// @notice Get full share info: series terms + decoded certificate data + legends + separated arrays
    function getFullShareInfo(bytes memory certExtensionData, uint256 tokenId)
        external
        view
        returns (SeriesTerms memory terms, CertificateData memory cert, string[] memory legends)
    {
        cert = abi.decode(certExtensionData, (CertificateData));
        require(seriesExists[cert.seriesId], "ShareExtension: series does not exist");
        terms = _seriesRegistry[cert.seriesId];
        legends = _certificateLegends[tokenId];
    }

    /// @notice Compute the conversion ratio for a convertible series: OIP / conversionPrice
    /// @return ratio The conversion ratio (18 decimals); 0 if not convertible or conversionPrice is 0
    function getConversionRatio(bytes32 seriesId) external view returns (uint256 ratio) {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        SeriesTerms storage s = _seriesRegistry[seriesId];
        if (!s.isConvertible || s.conversionPrice == 0) return 0;
        ratio = (s.originalIssuePrice * PRICE_PRECISION) / s.conversionPrice;
    }

    /// @notice Compute the payment percentage for a partly-paid certificate
    /// @return percentage The payment percentage (4 decimal basis, 10000 = 100%)
    function getPaymentPercentage(bytes memory certExtensionData) external pure returns (uint256 percentage) {
        CertificateData memory cert = abi.decode(certExtensionData, (CertificateData));
        if (!cert.isPartlyPaid || cert.totalConsideration == 0) return 10000; // fully paid
        percentage = (cert.amountPaid * 10000) / cert.totalConsideration;
    }

    /// @notice Compute accrued dividends for cumulative preferred shares
    /// @param seriesId The series to compute for
    /// @param asOfTimestamp The timestamp to compute accrual up to
    /// @param numberOfShares Number of shares to compute accrual for
    /// @return accrued The accrued dividend amount (18 decimals)
    function computeAccruedDividends(
        bytes32 seriesId,
        uint256 asOfTimestamp,
        uint256 numberOfShares
    ) external view returns (uint256 accrued) {
        require(seriesExists[seriesId], "ShareExtension: series does not exist");
        SeriesTerms storage s = _seriesRegistry[seriesId];
        if (s.dividendType != DividendType.Cumulative) return 0;
        if (asOfTimestamp <= s.dividendAccrualStartDate) return 0;

        uint256 elapsed = asOfTimestamp - s.dividendAccrualStartDate;
        // Simple accrual: rate * OIP * shares * elapsed / (365 days * 1e18)
        // Rate is already in 18 decimals as a fraction (8% = 8e16)
        accrued = (s.dividendRate * s.originalIssuePrice * numberOfShares * elapsed)
            / (365 days * PRICE_PRECISION);
    }

    // ══════════════════════════════════════════════════════════════
    //  Validation
    // ══════════════════════════════════════════════════════════════

    /// @notice Validate series terms without modifying state
    function validateSeriesTerms(SeriesTerms memory terms) external view returns (bool valid, string memory error) {
        return _validateSeriesTermsInternal(terms);
    }

    /// @notice Validate certificate data consistency
    function validateCertificateData(CertificateData memory data) external view returns (bool valid, string memory error) {
        return _validateCertificateDataInternal(data);
    }

    // ══════════════════════════════════════════════════════════════
    //  ICertificateExtension Overrides
    // ══════════════════════════════════════════════════════════════

    function supportsExtensionType(bytes32 extensionType) external pure override returns (bool) {
        return extensionType == EXTENSION_TYPE;
    }

    /// @notice Render extension data as a JSON fragment (intended for off-chain metadata consumption).
    /// @dev `view` because it reads seriesRegistry, legends, and issuerName.
    function getExtensionURI(bytes memory data) external view override returns (string memory) {
        if (data.length == 0) return "";

        CertificateData memory cert = abi.decode(data, (CertificateData));
        require(seriesExists[cert.seriesId], "ShareExtension: unknown seriesId in extension data");

        return _buildURI(cert);
    }

    // ══════════════════════════════════════════════════════════════
    //  Internal — Validation
    // ══════════════════════════════════════════════════════════════

    function _validateSeriesTermsInternal(SeriesTerms memory t) internal pure returns (bool, string memory) {
        if (t.authorizedShares == 0) return (false, "ShareExtension: authorizedShares must be > 0");
        if (t.parValue == 0) return (false, "ShareExtension: parValue must be > 0");

        if (!t.isConvertible) {
            if (t.conversionPrice != 0) return (false, "ShareExtension: conversionPrice must be 0 when not convertible");
            if (t.targetConversionSeriesId != bytes32(0)) return (false, "ShareExtension: targetConversionSeriesId must be zero when not convertible");
            if (t.hasMandatoryConversion) return (false, "ShareExtension: hasMandatoryConversion must be false when not convertible");
        }

        if (t.isConvertible) {
            if (t.conversionPrice == 0) return (false, "ShareExtension: conversionPrice must be > 0 when convertible");
            if (t.targetConversionSeriesId == bytes32(0)) return (false, "ShareExtension: targetConversionSeriesId must be non-zero when convertible");
        }

        if (t.dividendType == DividendType.None) {
            if (t.dividendRate != 0) return (false, "ShareExtension: dividendRate must be 0 when dividendType is None");
        }

        if (t.dividendType == DividendType.Cumulative) {
            if (t.dividendAccrualStartDate == 0) return (false, "ShareExtension: dividendAccrualStartDate should be non-zero for Cumulative dividends");
        }

        if (t.liquidationPreferenceType != LiquidationPreferenceType.CappedParticipating) {
            if (t.participationCap != 0) return (false, "ShareExtension: participationCap must be 0 when not CappedParticipating");
        }

        if (t.liquidationPreferenceType == LiquidationPreferenceType.CappedParticipating) {
            if (t.participationCap == 0) return (false, "ShareExtension: participationCap must be > 0 when CappedParticipating");
        }

        if (!t.isRedeemable) {
            if (t.redemptionPrice != 0) return (false, "ShareExtension: redemptionPrice must be 0 when not redeemable");
            if (t.redemptionType != RedemptionType.None) return (false, "ShareExtension: redemptionType must be None when not redeemable");
        }

        return (true, "");
    }

    function _validateCertificateDataInternal(CertificateData memory d) internal view returns (bool, string memory) {
        if (!seriesExists[d.seriesId]) return (false, "ShareExtension: seriesId does not reference an existing series");

        if (d.isPartlyPaid) {
            if (d.totalConsideration == 0) return (false, "ShareExtension: totalConsideration must be > 0 when partly paid");
            if (d.amountPaid >= d.totalConsideration) return (false, "ShareExtension: amountPaid must be < totalConsideration when partly paid");
        }

        if (!d.isPartlyPaid) {
            if (d.amountPaid != 0) return (false, "ShareExtension: amountPaid must be 0 when not partly paid");
            if (d.totalConsideration != 0) return (false, "ShareExtension: totalConsideration must be 0 when not partly paid");
        }

        return (true, "");
    }

    // ══════════════════════════════════════════════════════════════
    //  Internal — URI Builder
    // ══════════════════════════════════════════════════════════════

    function _buildURI(CertificateData memory cert) internal view returns (string memory) {
        SeriesTerms storage terms = _seriesRegistry[cert.seriesId];

        string memory p1 = _buildIdentity(terms);
        string memory p2 = _buildEconomics(terms);
        string memory p3 = _buildDividends(terms);
        string memory p4 = _buildConversion(terms, cert.seriesId);
        string memory p5 = _buildVoting(terms, cert.seriesId);
        string memory p6 = _buildRestrictionsRedemption(terms, cert.seriesId);
        string memory p7 = _buildCertificate(cert);
        string memory p8 = _buildIssuer();

        return string(abi.encodePacked(
            ', "shareDetails": {',
            p1, p2, p3, p4, p5, p6, p7, p8,
            "}"
        ));
    }

    function _buildIdentity(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"shareClassKey": "', _shareClassKeyToString(t.shareClassKey),
            '", "seriesName": "', t.seriesName,
            '", "parValue": "', _uint256ToString(t.parValue),
            '", "authorizedShares": "', _uint256ToString(t.authorizedShares),
            '", "originalIssuePrice": "', _uint256ToString(t.originalIssuePrice),
            '", "effectiveDate": "', _uint256ToString(t.effectiveDate),
            '", '
        ));
    }

    function _buildEconomics(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"liquidationPreferenceMultiple": "', _uint256ToString(t.liquidationPreferenceMultiple),
            '", "liquidationPreferenceType": "', _liquidationPrefTypeToString(t.liquidationPreferenceType),
            '", "participationCap": "', _uint256ToString(t.participationCap),
            '", "seniorityRank": "', _uint256ToString(t.seniorityRank),
            '", '
        ));
    }

    function _buildDividends(SeriesTerms storage t) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"dividendType": "', _dividendTypeToString(t.dividendType),
            '", "dividendRate": "', _uint256ToString(t.dividendRate),
            '", "dividendCompounding": "', _boolToString(t.dividendCompounding),
            '", "dividendIncreasesLiquidationAmount": "', _boolToString(t.dividendIncreasesLiquidationAmount),
            '", '
        ));
    }

    function _buildConversion(SeriesTerms storage t, bytes32 seriesId) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"isConvertible": "', _boolToString(t.isConvertible),
            '", "conversionPrice": "', _uint256ToString(t.conversionPrice),
            '", "antiDilutionType": "', _antiDilutionTypeToString(t.antiDilutionType),
            '", "allowsFractionalConversion": "', _boolToString(t.allowsFractionalConversion),
            '", "hasMandatoryConversion": "', _boolToString(t.hasMandatoryConversion),
            '", "mandatoryConversionTriggerCount": "', _uint256ToString(_conversionTriggers[seriesId].length),
            '", '
        ));
    }

    function _buildVoting(SeriesTerms storage t, bytes32 seriesId) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"votesPerShare": "', _uint256ToString(t.votesPerShare),
            '", "designatedBoardSeats": "', _uint256ToString(uint256(t.designatedBoardSeats)),
            '", "hasClassVotingRights": "', _boolToString(t.hasClassVotingRights),
            '", "hasSeriesVotingRights": "', _boolToString(t.hasSeriesVotingRights),
            '", "specialVotingRightsCount": "', _uint256ToString(_specialVotingRights[seriesId].length),
            '", '
        ));
    }

    function _buildRestrictionsRedemption(SeriesTerms storage t, bytes32 seriesId) internal view returns (string memory) {
        return string(abi.encodePacked(
            '"transferRestrictionCount": "', _uint256ToString(_transferRestrictions[seriesId].length),
            '", "isRedeemable": "', _boolToString(t.isRedeemable),
            '", "redemptionType": "', _redemptionTypeToString(t.redemptionType),
            '", "redemptionPrice": "', _uint256ToString(t.redemptionPrice),
            '", '
        ));
    }

    function _buildCertificate(CertificateData memory c) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '"certificateNumber": "', _uint256ToString(c.certificateNumber),
            '", "numberOfShares": "', _uint256ToString(c.numberOfShares),
            '", "issueDate": "', _uint256ToString(c.issueDate),
            '", "isPartlyPaid": "', _boolToString(c.isPartlyPaid),
            '", "amountPaid": "', _uint256ToString(c.amountPaid),
            '", "totalConsideration": "', _uint256ToString(c.totalConsideration),
            '", "representationType": "', _representationTypeToString(c.representationType),
            '", '
        ));
    }

    function _buildIssuer() internal view returns (string memory) {
        return string(abi.encodePacked(
            '"issuerName": "', issuerName,
            '", "stateOfIncorporation": "', stateOfIncorporation, '"'
        ));
    }

    // ══════════════════════════════════════════════════════════════
    //  Internal — String Helpers
    // ══════════════════════════════════════════════════════════════

    function _shareClassKeyToString(bytes32 key) internal pure returns (string memory) {
        if (key == CLASS_COMMON) return "Common";
        if (key == CLASS_PREFERRED) return "Preferred";
        return "Custom";
    }

    function _liquidationPrefTypeToString(LiquidationPreferenceType t) internal pure returns (string memory) {
        if (t == LiquidationPreferenceType.NonParticipating) return "NonParticipating";
        if (t == LiquidationPreferenceType.Participating) return "Participating";
        if (t == LiquidationPreferenceType.CappedParticipating) return "CappedParticipating";
        return "Unknown";
    }

    function _antiDilutionTypeToString(AntiDilutionType t) internal pure returns (string memory) {
        if (t == AntiDilutionType.None) return "None";
        if (t == AntiDilutionType.BroadBasedWeightedAverage) return "BroadBasedWeightedAverage";
        if (t == AntiDilutionType.NarrowBasedWeightedAverage) return "NarrowBasedWeightedAverage";
        if (t == AntiDilutionType.FullRatchet) return "FullRatchet";
        return "Unknown";
    }

    function _dividendTypeToString(DividendType t) internal pure returns (string memory) {
        if (t == DividendType.None) return "None";
        if (t == DividendType.NonCumulative) return "NonCumulative";
        if (t == DividendType.Cumulative) return "Cumulative";
        return "Unknown";
    }

    function _transferRestrictionTypeToString(TransferRestrictionType t) internal pure returns (string memory) {
        if (t == TransferRestrictionType.None) return "None";
        if (t == TransferRestrictionType.BoardConsentRequired) return "BoardConsentRequired";
        if (t == TransferRestrictionType.ROFRAndCoSale) return "ROFRAndCoSale";
        if (t == TransferRestrictionType.LockUp) return "LockUp";
        if (t == TransferRestrictionType.SecuritiesActRestriction) return "SecuritiesActRestriction";
        if (t == TransferRestrictionType.CustomRestriction) return "CustomRestriction";
        return "Unknown";
    }

    function _redemptionTypeToString(RedemptionType t) internal pure returns (string memory) {
        if (t == RedemptionType.None) return "None";
        if (t == RedemptionType.HolderOptional) return "HolderOptional";
        if (t == RedemptionType.CompanyOptional) return "CompanyOptional";
        if (t == RedemptionType.Mandatory) return "Mandatory";
        if (t == RedemptionType.EventTriggered) return "EventTriggered";
        return "Unknown";
    }

    function _representationTypeToString(ShareRepresentationType t) internal pure returns (string memory) {
        if (t == ShareRepresentationType.Certificated) return "Certificated";
        if (t == ShareRepresentationType.Uncertificated) return "Uncertificated";
        if (t == ShareRepresentationType.Tokenized) return "Tokenized";
        return "Unknown";
    }

    function _boolToString(bool b) internal pure returns (string memory) {
        return b ? "true" : "false";
    }

    function _uint256ToString(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = uint8(48 + (_i % 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    // ──────────────────────────────────────────────────────────────
    //  UUPS
    // ──────────────────────────────────────────────────────────────

    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}
}
