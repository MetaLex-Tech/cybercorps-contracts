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
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract MockDealManagerV2 is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "2";

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override {}
}

contract DealManagerFactoryTest is Test {

    bytes32 public salt = keccak256("DealManagerFactoryTest");

    uint256 public ownerPrivateKey = uint256(salt) + 0;
    address public owner = vm.addr(ownerPrivateKey);

    address public companyPayable = address(1000);
    address public companyOwner = address(1001);

    BorgAuth public bootstrapAuth;

    DealManagerFactory public dmFactory;

    function setUp() public {
        bootstrapAuth = new BorgAuth(owner);

        dmFactory = DealManagerFactory(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new DealManagerFactory{salt: salt}()),
                    abi.encodeWithSelector(
                        DealManagerFactory.initialize.selector,
                        address(bootstrapAuth),
                        address(new DealManager())
                    )
                )
            )
        );
    }

    function test_UpgradeFactory() public {
        // Upgrading DealManagerFactory should not impact existing deployments,
        // i.e. existing DealManager should still be able to find and upgrade to future releases

        // Deploy existing DealManagers

        BorgAuth corpAuth = new BorgAuth{salt: keccak256("test_UpgradeFactory")}(companyOwner);
        address placeHolderAddr = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

        DealManager dm = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(keccak256("test_UpgradeFactory"))
        );
        dm.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            address(dmFactory)
        );

        // Upgrade the factory

        vm.startPrank(owner);
        dmFactory.upgradeToAndCall(address(new DealManagerFactory()), "");
        vm.stopPrank();

        // Existing DealManager should still be able to upgrade to future releases

        // MetaLeX to release new DealManager v2
        vm.startPrank(owner);
        DealManagerFactory(dmFactory).setRefImplementation(DealManager(address(new MockDealManagerV2())));
        vm.stopPrank();

        // Corp owner decided to accept the upgrade
        vm.startPrank(companyOwner);
        dm.upgradeToAndCall(address(DealManagerFactory(dmFactory).refImplementation()), "");
        vm.stopPrank();
        assertEq(dm.DEPLOY_VERSION(), "2", "DealManager should be upgraded");
    }

    function test_RevertIf_UpgradeFactoryNonOwner() public {
        address newFactoryImpl = address(new DealManagerFactory());
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, bootstrapAuth.OWNER_ROLE(), companyOwner));
        vm.prank(companyOwner);
        dmFactory.upgradeToAndCall(newFactoryImpl, "");
    }
}
