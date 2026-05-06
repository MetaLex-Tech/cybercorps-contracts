// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";

contract AddSpaPlusTemplatesScript is Script {
    address internal constant REGISTRY =
        0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        vm.startBroadcast(deployerPrivateKey);

        string[] memory globalFieldsSafe = _globalFieldsSafe();
        string[] memory globalFieldsSafeTokenWarrant = _globalFieldsSafeTokenWarrant();
        string[] memory globalFieldsSafte = _globalFieldsSafte();
        string[] memory globalFieldsSaft = _globalFieldsSaft();
        string[] memory partyFields = _partyFields();

        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_safe_reg_d_v1_3")),
            "mlx_safe_reg_d_v1_3",
            "IPFS://bafybeih7l2kxncjuwrfgv5gnmpcik43dnn4pxpe4it4u7ti2hgfgrlot2a",
            globalFieldsSafe,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_safe_reg_s_v1_3")),
            "mlx_safe_reg_s_v1_3",
            "IPFS://bafybeieh7jn553jmrjmwee3dsvwf5hkedomey2vhubc3mumlewfpumvlae",
            globalFieldsSafe,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_safe_tw_reg_d_v1_3")),
            "mlx_safe_tw_reg_d_v1_3",
            "IPFS://bafybeiaw3pwov3ahg4bk2hte2hu4pwv34nndoguxyk3umq6f5su3kod6ay",
            globalFieldsSafeTokenWarrant,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_safe_tw_reg_s_v1_3")),
            "mlx_safe_tw_reg_s_v1_3",
            "IPFS://bafybeicto2raupsj5ad7snxvhmmll2plwyploqho4fg2cibnn2fuhlm2d4",
            globalFieldsSafeTokenWarrant,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_safte_reg_d_v1_3")),
            "mlx_safte_reg_d_v1_3",
            "IPFS://bafybeiag7xatsusb24evnpyj6ztf62kix36dgbsp3kbazfyvr273ph56ay",
            globalFieldsSafte,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_safte_reg_s_v1_3")),
            "mlx_safte_reg_s_v1_3",
            "IPFS://bafybeia43r7e566s2jlq4gtaasmtybutujy7fuizhw3fycxtwnstfbkeia",
            globalFieldsSafte,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_saft_reg_d_v1_3")),
            "mlx_saft_reg_d_v1_3",
            "IPFS://bafybeieoljri2rwuv35rymjd654sr3u46kbcao7mymseqobfo7x6lxgdcy",
            globalFieldsSaft,
            partyFields
        );
        CyberAgreementRegistry(REGISTRY).createTemplate(
            bytes32(bytes("mlx_saft_reg_s_v1_3")),
            "mlx_saft_reg_s_v1_3",
            "IPFS://bafybeibwrz3rttteguo5ccoh5x7ndwdu6hyhy7i3iraii5c5ml4pfv73t4",
            globalFieldsSaft,
            partyFields
        );

        vm.stopBroadcast();
    }

    function _globalFieldsSafe() internal pure returns (string[] memory fields) {
        fields = new string[](5);
        fields[0] = "purchaseAmount";
        fields[1] = "postMoneyValuationCap";
        fields[2] = "expirationTime";
        fields[3] = "governingJurisdiction";
        fields[4] = "disputeResolution";
    }

    function _globalFieldsSafeTokenWarrant()
        internal
        pure
        returns (string[] memory fields)
    {
        fields = new string[](17);
        fields[0] = "purchaseAmount";
        fields[1] = "postMoneyValuationCap";
        fields[2] = "expirationTime";
        fields[3] = "governingJurisdiction";
        fields[4] = "disputeResolution";
        fields[5] = "exercisePriceMethod";
        fields[6] = "exercisePrice";
        fields[7] = "unlockStartTimeType";
        fields[8] = "unlockStartTime";
        fields[9] = "unlockingPeriod";
        fields[10] = "latestExpirationTime";
        fields[11] = "unlockingCliffPeriod";
        fields[12] = "unlockingCliffPercentage";
        fields[13] = "unlockingIntervalType";
        fields[14] = "tokenCalculationMethod";
        fields[15] = "minCompanyReserve";
        fields[16] = "tokenPremiumMultiplier";
    }

    function _globalFieldsSafte() internal pure returns (string[] memory fields) {
        fields = new string[](15);
        fields[0] = "purchaseAmount";
        fields[1] = "postMoneyValuationCap";
        fields[2] = "protocolUSDValuationAtTimeofInvestment";
        fields[3] = "expirationTime";
        fields[4] = "governingJurisdiction";
        fields[5] = "disputeResolution";
        fields[6] = "unlockStartTimeType";
        fields[7] = "unlockStartTime";
        fields[8] = "unlockingPeriod";
        fields[9] = "unlockingCliffPeriod";
        fields[10] = "unlockingCliffPercentage";
        fields[11] = "unlockingIntervalType";
        fields[12] = "tokenCalculationMethod";
        fields[13] = "minCompanyReserve";
        fields[14] = "tokenPremiumMultiplier";
    }

    function _globalFieldsSaft() internal pure returns (string[] memory fields) {
        fields = new string[](10);
        fields[0] = "purchaseAmount";
        fields[1] = "protocolValuationCap";
        fields[2] = "governingJurisdiction";
        fields[3] = "disputeResolution";
        fields[4] = "unlockStartTimeType";
        fields[5] = "unlockStartTime";
        fields[6] = "unlockingPeriod";
        fields[7] = "unlockingCliffPeriod";
        fields[8] = "unlockingCliffPercentage";
        fields[9] = "unlockingIntervalType";
    }

    function _partyFields() internal pure returns (string[] memory fields) {
        fields = new string[](5);
        fields[0] = "name";
        fields[1] = "evmAddress";
        fields[2] = "contactDetails";
        fields[3] = "investorType";
        fields[4] = "investorJurisdiction";
    }
}
