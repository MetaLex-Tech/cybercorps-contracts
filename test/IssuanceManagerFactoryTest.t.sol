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
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";
import {CyberScrip} from "../src/CyberScrip.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory, IssuanceManagerFactoryStorage} from "../src/IssuanceManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";

contract IssuanceManagerFactoryTest is Test {

    bytes32 public salt = keccak256("IssuanceManagerFactoryTest");

    uint256 public ownerPrivateKey = uint256(salt) + 0;
    address public owner = vm.addr(ownerPrivateKey);

    BorgAuth public bootstrapAuth;

    function setUp() public {
        bootstrapAuth = new BorgAuth(owner);
    }

    function test_initialize() public {
        IssuanceManager refImplementation = new IssuanceManager();
        CyberCertPrinter cyberCertPrinterRefImplementation = new CyberCertPrinter();
        CyberScrip cyberScripRefImplementation = new CyberScrip();
        IssuanceManagerFactory factoryImpl = new IssuanceManagerFactory();

        // Should emit first reference implementation upon initialization
        vm.expectEmit(true, true, true, true);
        emit IssuanceManagerFactory.RefImplementationSet(address(refImplementation), refImplementation.DEPLOY_VERSION());
        emit IssuanceManagerFactory.CyberCertPrinterRefImplementationSet(address(cyberCertPrinterRefImplementation), cyberCertPrinterRefImplementation.DEPLOY_VERSION());
        emit IssuanceManagerFactory.CyberScripRefImplementationSet(address(cyberScripRefImplementation), cyberScripRefImplementation.DEPLOY_VERSION());
        new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeWithSelector(
                IssuanceManagerFactory.initialize.selector,
                address(bootstrapAuth),
                address(refImplementation),
                address(cyberCertPrinterRefImplementation),
                address(cyberScripRefImplementation)
            )
        );
    }
}
