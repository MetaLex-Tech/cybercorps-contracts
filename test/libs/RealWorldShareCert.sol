// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {
    AntiDilutionType,
    CertificateData,
    DividendType,
    LiquidationPreferenceType,
    MandatoryConversionTrigger,
    MandatoryConversionTriggerType,
    RedemptionType,
    SHARE_LAYER_TAG,
    SeriesTerms,
    ShareCertData,
    ShareLayer,
    ShareRepresentationType,
    SpecialVotingRight,
    SplitRecord,
    TransferRestriction,
    TransferRestrictionException,
    TransferRestrictionType,
    VotingScope
} from "../../src/storage/extensions/ShareExtension.sol";

// IPFS URI used in certData.uri and template (66 chars, matches real certData[0].uri)
string constant REAL_WORLD_IPFS_URI = "ipfs://bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";

/// @notice Series Seed 2 preferred-stock cert payload copied from a real mainnet issuance: the six
///         restricted-securities legends the printer carries, plus the ~13 KB ShareCertData extension blob
///         a cert stores. Shared by the primary-round and secondary-trade gas guards so both measure the
///         same real-world payload size.
library RealWorldShareCert {
    // Pinata gateway URI used in all ShareCertData URI fields (113 chars, matches real extensionData)
    string constant PINATA_URI =
        "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";

    // ── Six restricted-securities legends (real cert printer content) ─────────
    string constant L0 = "RESTRICTED SECURITIES LEGEND. THE STOCK LEDGER ENTRY TOKEN, THE TOKENIZED SHARES "
        "REPRESENTED HEREBY, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO "
        "(INCLUDING UPON CONVERSION) ARE \"RESTRICTED SECURITIES\" AS DEFINED IN SEC RULE 144.";

    string constant L1 = "SECURITIES ACT LEGEND. THE STOCK LEDGER ENTRY TOKEN, THE TOKENIZED SHARES "
        "REPRESENTED HEREBY, AND ANY SECURITIES ISSUABLE PURSUANT HERETO OR THERETO HAVE NOT "
        "BEEN REGISTERED UNDER THE SECURITIES ACT OF 1933, AS AMENDED (THE \"SECURITIES ACT\"), "
        "OR UNDER THE SECURITIES LAWS OF CERTAIN STATES. THESE SECURITIES MAY NOT BE OFFERED, "
        "SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED IN THIS "
        "AGREEMENT, THE COI, THE BYLAWS AND THE TRANSACTION AGREEMENTS, AND UNDER THE SECURITIES "
        "ACT AND APPLICABLE STATE SECURITIES LAWS PURSUANT TO AN EFFECTIVE REGISTRATION STATEMENT "
        "OR AN EXEMPTION THEREFROM.";

    string constant L2 = "BOARD CONSENT TRANSFER RESTRICTION LEGEND. THE TOKENIZED SHARES REPRESENTED HEREBY AND "
        "THE STOCK LEDGER ENTRY TOKEN MAY NOT BE TRANSFERRED, PLEDGED OR HYPOTHECATED WITHOUT THE "
        "PRIOR WRITTEN CONSENT OF THE BOARD OF DIRECTORS OF THE CORPORATION AS REQUIRED BY THE "
        "BYLAWS, EXCEPT IN CIRCUMSTANCES EXPRESSLY PERMITTED BY THE BYLAWS WITHOUT SUCH CONSENT.";

    string constant L3 = "STOCKHOLDER AGREEMENTS LEGEND. THE TOKENIZED SHARES REPRESENTED HEREBY AND THE STOCK "
        "LEDGER ENTRY TOKEN ARE SUBJECT TO, AND ANY TRANSFER OR OTHER DISPOSITION HEREOF OR "
        "THEREOF IS RESTRICTED BY AND SUBJECT TO, THE TERMS AND CONDITIONS OF THE TRANSACTION "
        "AGREEMENTS, INCLUDING THE INVESTORS' RIGHTS AGREEMENT, THE VOTING AGREEMENT, AND THE "
        "RIGHT OF FIRST REFUSAL AND CO-SALE AGREEMENT, EACH AS IN EFFECT FROM TIME TO TIME. "
        "COPIES OF THE TRANSACTION AGREEMENTS ARE AVAILABLE FROM THE CORPORATION UPON REQUEST AT NO CHARGE.";

    string constant L4 = "TOKENIZED STOCK LEDGER LEGEND. THIS STOCK LEDGER ENTRY TOKEN CONSTITUTES, AND IS THE "
        "CORPORATION'S OFFICIAL RECORD OF, AN ENTRY IN THE CORPORATION'S OFFICIAL STOCK LEDGER "
        "MAINTAINED IN THE TOKENIZED STOCK LEDGER SYSTEM IN ACCORDANCE WITH SECTIONS 219 AND 224 "
        "OF THE DGCL, ARTICLE FOURTEENTH OF THE COI AND ARTICLE 8 OF THE BYLAWS. THE TOKENIZED "
        "SHARES REPRESENTED HEREBY ARE UNCERTIFICATED SHARES; NO PAPER STOCK CERTIFICATE WILL BE "
        "ISSUED UNLESS AND UNTIL THE BOARD OF DIRECTORS SO DETERMINES IN ACCORDANCE WITH THE BYLAWS.";

    string constant L5 = "MATERIAL ADVERSE EXCEPTION EVENT LEGEND. UPON THE OCCURRENCE OR REASONABLY EXPECTED "
        "OCCURRENCE OF A MATERIAL ADVERSE EXCEPTION EVENT (AS SUCH TERM IS DEFINED IN THE BYLAWS), "
        "THE CORPORATION MAY, IN ITS SOLE AND ABSOLUTE DISCRETION AND IN ACCORDANCE WITH THE BYLAWS, "
        "SUSPEND THE REGISTRATION OF TRANSFERS OF THIS STOCK LEDGER ENTRY TOKEN AND THE TOKENIZED "
        "SHARES REPRESENTED HEREBY, DETERMINE THE AUTHORITATIVE CHAIN, VERSION OR STATE OF THE "
        "DESIGNATED BLOCKCHAIN SYSTEM, AND TREAT AS VOID OR VOIDABLE ANY PURPORTED TRANSFER OF THIS "
        "STOCK LEDGER ENTRY TOKEN OR THE TOKENIZED SHARES REPRESENTED HEREBY EFFECTED OR ATTEMPTED "
        "TO BE EFFECTED IN CONNECTION WITH OR AS A RESULT OF SUCH MATERIAL ADVERSE EXCEPTION EVENT, "
        "NOTWITHSTANDING SECTION 8-303 OF THE UCC. NO COPY OF THIS STOCK LEDGER ENTRY TOKEN MAY BE "
        "OFFERED, SOLD OR OTHERWISE TRANSFERRED, PLEDGED OR HYPOTHECATED EXCEPT AS PERMITTED BY THE "
        "BYLAWS, AND ONLY THE COPY ON THE CHAIN, VERSION OR STATE OF THE DESIGNATED BLOCKCHAIN SYSTEM "
        "DETERMINED BY THE CORPORATION TO BE AUTHORITATIVE MAY BE SO OFFERED, SOLD OR TRANSFERRED.";

    string constant L6_LOCKUP = "180 day market stand-off re: IPO in Investors Rights Agreement Sec. 2.11\n\n"
        "this is a summary only and is non-binding; for actual binding terms, see "
        "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne";

    /// @notice The six legends a printer carries as its default legend block.
    function legends() internal pure returns (string[] memory legend) {
        legend = new string[](6);
        legend[0] = L0;
        legend[1] = L1;
        legend[2] = L2;
        legend[3] = L3;
        legend[4] = L4;
        legend[5] = L5;
    }

    /// @notice abi-encoded ShareCertData (~13 KB) as stored in CertificateDetails.extensionData.
    function encodedShareCertData() internal pure returns (bytes memory) {
        return abi.encode(shareCertData());
    }

    /// @notice The same payload as one whole struct, before it is split into layers.
    function shareCertData() internal pure returns (ShareCertData memory) {
        return ShareCertData({
            terms: seriesTerms(),
            certificateData: certificateData(),
            mandatoryConversionTriggers: conversionTriggers(),
            specialVotingRights: votingRights(),
            transferRestrictions: transferRestrictions(),
            splitHistory: splitHistory()
        });
    }

    /// @notice The five series-wide sections of the payload, as the printer's `seriesData`.
    function encodedSeriesLayer() internal pure returns (bytes memory) {
        ShareLayer memory layer;
        layer.terms = abi.encode(seriesTerms());
        layer.conversionTriggers = abi.encode(conversionTriggers());
        layer.votingRights = abi.encode(votingRights());
        layer.transferRestrictions = abi.encode(transferRestrictions());
        layer.splitHistory = abi.encode(splitHistory());
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    /// @notice What is left of the payload once the series sections move to the printer, as a cert's
    ///         `extensionData`. Every other section is empty, so the cert inherits it from the series.
    function encodedCertLayer() internal pure returns (bytes memory) {
        ShareLayer memory layer;
        layer.certificateData = abi.encode(certificateData());
        return abi.encode(SHARE_LAYER_TAG, layer);
    }

    function certificateData() internal pure returns (CertificateData memory) {
        return CertificateData({
            isPartlyPaid: false,
            amountPaid: 0,
            totalConsideration: 0,
            sourceAuthorityURI: PINATA_URI,
            representationType: ShareRepresentationType.Tokenized,
            holdingPeriodTackingApplied: true
        });
    }

    function splitHistory() internal pure returns (SplitRecord[] memory splits) {
        splits = new SplitRecord[](1);
        splits[0] =
            SplitRecord({numerator: 1, denominator: 1, timestamp: 1_780_075_297, sourceAuthorityURI: PINATA_URI});
    }

    function seriesTerms() internal pure returns (SeriesTerms memory) {
        return SeriesTerms({
            seriesName: "Series Seed 2",
            parValue: 10_000_000_000_000,
            authorizedShares: 67_600_000_000_000_000_000_000,
            originalIssuePrice: 26_213_301_000_000_000_000,
            effectiveDate: 1_780_075_297,
            sourceAuthorityURI: PINATA_URI,
            liquidationPreferenceMultiple: 1e18,
            liquidationPreferenceType: LiquidationPreferenceType.NonParticipating,
            participationCap: 0,
            seniorityRank: 1,
            dividendType: DividendType.None,
            dividendRate: 0,
            dividendAccrualStartDate: 0,
            dividendCompounding: false,
            dividendIncreasesLiquidationAmount: false,
            isConvertible: true,
            targetConversionSeriesId: "",
            conversionPrice: 26_213_301_000_000_000_000,
            antiDilutionType: AntiDilutionType.BroadBasedWeightedAverage,
            allowsFractionalConversion: false,
            hasMandatoryConversion: true,
            votesPerShare: 1e18,
            designatedBoardSeats: 1,
            hasClassVotingRights: true,
            hasSeriesVotingRights: true,
            isRedeemable: false,
            redemptionType: RedemptionType.None,
            redemptionPrice: 0,
            redemptionSchedule: "",
            redemptionTriggerDescription: "",
            hasPayToPlay: false,
            payToPlayTermsURI: "",
            hasRegistrationRights: true,
            registrationRightsURI: PINATA_URI,
            hasProRataRights: true,
            proRataRightsURI: PINATA_URI,
            hasInformationRights: true,
            informationRightsURI: PINATA_URI,
            hasDragAlongRights: true,
            dragAlongTermsURI: PINATA_URI
        });
    }

    function conversionTriggers() internal pure returns (MandatoryConversionTrigger[] memory triggers) {
        triggers = new MandatoryConversionTrigger[](2);
        triggers[0] = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.ClassVote,
            primaryThreshold: 0,
            secondaryThreshold: 50_000_000e18,
            additionalConditions: "",
            description: "**Primary threshold: $50.00 per share**\n"
            "- Closing of sale of Common Stock to the public at a price of at least $50.00 per share\n"
            "- Subject to anti-dilution adjustment for splits/dividends/combinations\n\n"
            "**Secondary threshold: $5,000,000**\n" "- Gross proceeds to the Corporation\n\n"
            "**Structural conditions (no numeric threshold):**\n"
            "- Form: firm-commitment underwritten public offering\n"
            "- Registration: effective registration statement under Securities Act of 1933\n"
            "- Listing: Nasdaq National Market, NYSE, or Board-approved exchange/marketplace\n\n"
            "this is a summary only and is non-binding; for actual binding terms, see "
            "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
        triggers[1] = MandatoryConversionTrigger({
            triggerType: MandatoryConversionTriggerType.ClassVote,
            primaryThreshold: 1,
            secondaryThreshold: 50_100_000_000_000_000_000,
            additionalConditions: "**Primary threshold: 50.1%**\n"
            "- Vote or written consent of the Requisite Preferred Holders\n"
            "- Requisite Preferred Holders = holders of at least 50.1% of then-outstanding "
            "shares of Preferred Stock (Series Seed + Series Seed 2 combined)\n"
            "- Voting together as a single class on an as-converted to Common Stock basis\n\n"
            "**Secondary threshold: N/A (0)**\n"
            "- ClassVote has no secondary numeric threshold; 50.1% is the sole voting requirement\n"
            "- Specifies a date/time/event to trigger conversion\n\n"
            "this is a summary only and is non-binding; for actual binding terms, see "
            "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne",
            description: "**Primary threshold: 50.1%**\n"
            "- Vote or written consent of the Requisite Preferred Holders\n\n"
            "this is a summary only and is non-binding; for actual binding terms, see "
            "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
    }

    function votingRights() internal pure returns (SpecialVotingRight[] memory rights) {
        rights = new SpecialVotingRight[](2);
        rights[0] = SpecialVotingRight({
            matterType: "Series Seed 2 Protective Provisions",
            votesPerShare: 1e18,
            threshold: 5_010,
            isVetoRight: true,
            scope: VotingScope.SeriesSpecific,
            description: "Series Seed 2-specific protective provisions. Acts affecting Series Seed 2 in these "
            "matters are void without written consent or affirmative vote of at least 50.1% of "
            "Series Seed 2 holders.\n\n" "This is a summary only and is non-binding; for actual binding terms, see "
            "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
        rights[1] = SpecialVotingRight({
            matterType: "Joint Preferred Protective Provisions",
            votesPerShare: 1e18,
            threshold: 5_010,
            isVetoRight: true,
            scope: VotingScope.ClassWide,
            description: "Joint preferred protective provisions requiring written consent or affirmative vote "
            "of holders of at least 50.1% of the then-outstanding shares of Preferred Stock "
            "(Series Seed + Series Seed 2 combined), voting together as a single class on an "
            "as-converted to Common Stock basis. Listed matters cannot be undertaken without " "such consent:\n"
            "- Liquidation, dissolution, or Deemed Liquidation Event\n"
            "- Creation or authorization of new preferred classes\n"
            "- Redemption, dividend declarations, or capital structure changes\n" "- Debt or liens exceeding $500,000\n"
            "- Board size changes\n\n" "This is a summary only and is non-binding; for actual binding terms, see "
            "https://example-pinata-gw-testnet.mypinata.cloud/ipfs/bafybeidk7knzf43nsj6q2jhouieifyssknohn4uvizlxtnbwvxgjkqgbne"
        });
    }

    function transferRestrictions() internal pure returns (TransferRestriction[] memory restrictions) {
        TransferRestrictionException[] memory noExc = new TransferRestrictionException[](0);
        restrictions = new TransferRestriction[](7);

        // L2: Board Consent
        restrictions[0] = TransferRestriction({
            restrictionType: TransferRestrictionType.BoardConsentRequired,
            restrictionText: L2,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L1: Securities Act
        restrictions[1] = TransferRestriction({
            restrictionType: TransferRestrictionType.SecuritiesActRestriction,
            restrictionText: L1,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L0: Restricted Securities
        restrictions[2] = TransferRestriction({
            restrictionType: TransferRestrictionType.SecuritiesActRestriction,
            restrictionText: L0,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L3: Stockholder Agreements
        restrictions[3] = TransferRestriction({
            restrictionType: TransferRestrictionType.ROFRAndCoSale,
            restrictionText: L3,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
        // L4: Tokenized Stock Ledger
        restrictions[4] = TransferRestriction({
            restrictionType: TransferRestrictionType.CustomRestriction,
            restrictionText: L4,
            sourceAgreement: PINATA_URI,
            isRemovable: false,
            exceptions: noExc
        });
        // L5: Material Adverse Exception
        restrictions[5] = TransferRestriction({
            restrictionType: TransferRestrictionType.CustomRestriction,
            restrictionText: L5,
            sourceAgreement: PINATA_URI,
            isRemovable: false,
            exceptions: noExc
        });
        // 180-day lockup
        restrictions[6] = TransferRestriction({
            restrictionType: TransferRestrictionType.LockUp,
            restrictionText: L6_LOCKUP,
            sourceAgreement: PINATA_URI,
            isRemovable: true,
            exceptions: noExc
        });
    }
}
