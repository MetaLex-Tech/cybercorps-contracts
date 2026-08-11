// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CompanyOfficer, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {CyberCorpFactory} from "../src/CyberCorpFactory.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {RoundManagerFactory} from "../src/RoundManagerFactory.sol";
import {RoundManager} from "../src/RoundManager.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LedgerEntryToken} from "../src/LedgerEntryToken.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {ILegacyFactory} from "../script/interfaces/ILegacyFactory.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;
}

contract AddTestWhitelistScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAIN");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
           bytes32 salt = bytes32(
            keccak256("MetaLexCyberCorp.PublicRounds.UpgradeV3.0.2")
        );

        // Required existing addresses
        address cyberCorpFactoryProxyAddr = 0x51413048f3Dfc4516e95BC8e249341B1D53B6cB2;
        address registry = 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134;
        address deployedLexChexAddrAuth = 0xeAdeaD5C4A6747D4959489742c143bCDb95a01c2;

       //RoundManagerFactory(0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34).setWhitelistedToken(0xdfbD1a4AD9C6D752231f83d390471d8029843dFF, true);
       //RoundManagerFactory(0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34).setDefaultFeeRatio(30);
       RoundManagerFactory(0x9E2A3a07711Ce4b5A2F4D62a5c8f8B5307Af9C34).setPlatformPayable(deployer);
    }


}
