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
import {DealManagerFactory, DealManagerFactoryStorage} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract MockDealManagerVTest is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "test";

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

    uint256 ownerRole;

    function setUp() public {
        bootstrapAuth = new BorgAuth(owner);
        ownerRole = bootstrapAuth.OWNER_ROLE();

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

    function test_initialize() public {
        DealManager refImplementation = new DealManager();
        DealManagerFactory factoryImpl = new DealManagerFactory();

        // Should emit first reference implementation upon initialization
        vm.expectEmit(true, true, true, true);
        emit DealManagerFactory.RefImplementationSet(address(refImplementation), refImplementation.DEPLOY_VERSION());
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeWithSelector(
                DealManagerFactory.initialize.selector,
                address(bootstrapAuth),
                address(refImplementation)
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
        DealManagerFactory(dmFactory).setRefImplementation(address(new MockDealManagerVTest()));
        vm.stopPrank();

        // Corp owner decided to accept the upgrade
        vm.startPrank(companyOwner);
        dm.upgradeToAndCall(address(DealManagerFactory(dmFactory).getRefImplementation()), "");
        vm.stopPrank();
        assertEq(dm.DEPLOY_VERSION(), "test", "DealManager should be upgraded");
    }

    function test_RevertIf_UpgradeFactoryNonOwner() public {
        address newFactoryImpl = address(new DealManagerFactory());
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, bootstrapAuth.OWNER_ROLE(), companyOwner));
        vm.prank(companyOwner);
        dmFactory.upgradeToAndCall(newFactoryImpl, "");
    }

    function test_SetRefImplementation() public  {
        address newImplementation = address(new MockDealManagerVTest());
        assertNotEq(dmFactory.getRefImplementation(), newImplementation, "Unexpected refImplementation before set");

        vm.expectEmit(true, true, true, true);
        emit DealManagerFactory.RefImplementationSet(newImplementation, "test");
        vm.prank(owner);
        dmFactory.setRefImplementation(newImplementation);
        assertEq(dmFactory.getRefImplementation(), newImplementation, "Unexpected refImplementation after set");
    }

    function test_RevertIf_SetRefImplementationNonOwner() public {
        vm.prank(companyOwner);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, companyOwner));
        dmFactory.setRefImplementation(address(0x123));
    }

    function test_SetPlatformPayable() public  {
        address newValue = address(0x123);
        assertNotEq(dmFactory.getPlatformPayable(), newValue, "Unexpected platformPayable before set");

        vm.prank(owner);
        dmFactory.setPlatformPayable(newValue);
        assertEq(dmFactory.getPlatformPayable(), newValue, "Unexpected platformPayable after set");
    }

    function test_RevertIf_SetPlatformPayableNonOwner() public {
        vm.prank(companyOwner);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, companyOwner));
        dmFactory.setPlatformPayable(address(0x123));
    }

    function test_SetDefaultFeeRatio() public  {
        uint256 newValue = 123;
        assertNotEq(dmFactory.getDefaultFeeRatio(), newValue, "Unexpected defaultFeeRatio before set");

        vm.prank(owner);
        dmFactory.setDefaultFeeRatio(newValue);
        assertEq(dmFactory.getDefaultFeeRatio(), newValue, "Unexpected defaultFeeRatio after set");
    }

    function test_RevertIf_SetDefaultFeeRatioNonOwner() public {
        vm.prank(companyOwner);
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, ownerRole, companyOwner));
        dmFactory.setDefaultFeeRatio(123);
    }

    function test_RevertIf_SetDefaultFeeRatioInvalid() public {
        vm.prank(owner);
        vm.expectRevert(DealManagerFactory.InvalidFeeRatio.selector);
        dmFactory.setDefaultFeeRatio(DealManagerFactoryStorage.BASIS_POINTS + 1);
    }
}
