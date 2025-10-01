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

import {Test, console} from "forge-std/Test.sol";
import {UUPSUpgradeable} from "../dependencies/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "../dependencies/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "../dependencies/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManager, LexScroWLite} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails, Endorsement} from "../src/storage/CyberCertPrinterStorage.sol";

contract MockDealManagerV2 is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "2";

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override {}
}

contract DealManagerTest is Test {

    bytes32 public salt = keccak256("DealManagerTest");

    uint256 public ownerPrivateKey = uint256(salt) + 0;
    address public owner = vm.addr(ownerPrivateKey);

    address public companyPayable = address(1000);
    address public companyOwner = address(1001);

    BorgAuth public bootstrapAuth;
    DealManagerFactory public dmFactory;

    function setUp() public {
        bootstrapAuth = new BorgAuth(owner);
        dmFactory = new DealManagerFactory{salt: salt}(address(bootstrapAuth));
    }

    function test_UpgradeNextDealManager() public {
        assertEq(DealManagerFactory(dmFactory).refImplementation().DEPLOY_VERSION(), "1", "reference impl version should not be changed yet");

        vm.startPrank(owner);
        DealManagerFactory(dmFactory).setRefImplementation(DealManager(address(new MockDealManagerV2())));
        vm.stopPrank();
        assertEq(DealManagerFactory(dmFactory).refImplementation().DEPLOY_VERSION(), "2", "reference impl version should have changed");

        bytes32 salt = keccak256("test_UpgradeNextDealerManager");
        // Next deployment should emit events with version so indexer could be informed
        vm.expectEmit(true, true, true, true);
        emit DealManagerFactory.DealManagerDeployed(
            DealManagerFactory(dmFactory).computeDealManagerAddress(salt),
            "2"
        );
        DealManager nextRm = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(salt)
        );
        assertEq(nextRm.DEPLOY_VERSION(), "2", "next deployment version should have changed");
    }
    
    function test_UpgradeExistingDealManager() public {
        BorgAuth corpAuth = new BorgAuth{salt: keccak256("testUpgradeExistingDealManager")}(companyOwner);
        address placeHolderAddr = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

        // Deploy existing DealManagers

        DealManager dm1 = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(keccak256("testUpgradeExistingDealManager1"))
        );
        dm1.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            address(dmFactory)
        );

        DealManager dm2 = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(keccak256("testUpgradeExistingDealManager2"))
        );
        dm2.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            address(dmFactory)
        );

        // MetaLeX to release new DealManager v2

        vm.startPrank(owner);
        DealManagerFactory(dmFactory).setRefImplementation(DealManager(address(new MockDealManagerV2())));
        vm.stopPrank();

        // Corp2 owner decided to accept the upgrade

        vm.startPrank(companyOwner);
        dm2.upgradeToAndCall(address(DealManagerFactory(dmFactory).refImplementation()), "");
        vm.stopPrank();

        assertEq(dm2.DEPLOY_VERSION(), "2", "Target DealManager should be upgraded");
        assertEq(dm1.DEPLOY_VERSION(), "1", "Other DealManager should not be upgraded");
    }

    function test_RevertIf_UpgradeNonFactoryOwner() public {
        // Non-MetaLeX admin should not be able to set new reference implementation

        DealManager newImplementation = DealManager(address(new MockDealManagerV2()));
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, bootstrapAuth.OWNER_ROLE(), companyOwner));
        vm.prank(companyOwner);
        DealManagerFactory(dmFactory).setRefImplementation(newImplementation);
    }

    function test_RevertIf_UpgradeExistingDealManagerNotRefImplementation() public {
        BorgAuth corpAuth = new BorgAuth{salt: keccak256("testUpgradeExistingDealManager")}(companyOwner);
        address placeHolderAddr = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

        // Deploy existing DealManagers

        DealManager rm = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(keccak256("testUpgradeExistingDealManager2"))
        );
        rm.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            address(dmFactory)
        );

        // Corp owner can't upgrade to v2 without MetaLeX releasing it first

        vm.startPrank(companyOwner);
        address nonOfficialDealManager = address(new MockDealManagerV2());
        vm.expectRevert(
            abi.encodeWithSelector(DealManager.NotRefImplementation.selector)
        );
        rm.upgradeToAndCall(nonOfficialDealManager, "");
        vm.stopPrank();
    }
}
