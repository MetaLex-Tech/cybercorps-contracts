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

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CyberCorp} from "../src/CyberCorp.sol";
import {CyberCorpSingleFactory} from "../src/CyberCorpSingleFactory.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {IssuanceManager} from "../src/IssuanceManager.sol";
import {IssuanceManagerFactory} from "../src/IssuanceManagerFactory.sol";
import {CyberCertPrinter} from "../src/CyberCertPrinter.sol";

contract UpgradeabilityTest is Test {
    // Assume existing deployment @ Sepolia on block 8262303
    bytes32 corpSalt = keccak256(abi.encodePacked(uint256(1)));
    address multisig = 0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C;
    BorgAuth auth = BorgAuth(0xbC1BC2e1D94b428078CbB2906848BAd0707861b8);
    CyberCorpSingleFactory cyberCorpSingleFactory = CyberCorpSingleFactory(0x1D5c94d681F3b583877c11B9DF9e809C93019D3f);
    DealManagerFactory dealManagerFactory = DealManagerFactory(0x5b00D8f28D7BE1BDb02d1cfE4abDe07b16B29fA1);
    IssuanceManagerFactory issuanceManagerFactory = IssuanceManagerFactory(0xF910d713657C2931910E8ab241606Cc048A3Af97);

    // Assume an existing cyberCorp at block mentioned above
    IssuanceManager issuanceManager = IssuanceManager(0x00cd771c4E11E2C985E255806482719De3AFe7C5);

    function setUp() public {
    }

    function testUpgradeBeaconImplementationCyberCorp() public {
        CyberCorp newCyberCorpImplementation = new CyberCorp();

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        cyberCorpSingleFactory.upgradeImplementation(address(newCyberCorpImplementation));

        // Owner should be able to upgrade it
        vm.prank(multisig);
        cyberCorpSingleFactory.upgradeImplementation(address(newCyberCorpImplementation));
        assertEq(cyberCorpSingleFactory.getBeaconImplementation(), address(newCyberCorpImplementation));
    }

    function testUpgradeBeaconImplementationDealManager() public {
        DealManager newDealManagerImplementation = new DealManager();

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        dealManagerFactory.upgradeImplementation(address(newDealManagerImplementation));

        // Owner should be able to upgrade it
        vm.prank(multisig);
        dealManagerFactory.upgradeImplementation(address(newDealManagerImplementation));
        assertEq(dealManagerFactory.getBeaconImplementation(), address(newDealManagerImplementation));
    }

    function testUpgradeBeaconImplementationIssuanceManager() public {
        IssuanceManager newIssuanceManagerImplementation = new IssuanceManager();

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        issuanceManagerFactory.upgradeImplementation(address(newIssuanceManagerImplementation));

        // Owner should be able to upgrade it
        vm.prank(multisig);
        issuanceManagerFactory.upgradeImplementation(address(newIssuanceManagerImplementation));
        assertEq(issuanceManagerFactory.getBeaconImplementation(), address(newIssuanceManagerImplementation));
    }

    function testUpgradeBeaconImplementationCyberCertPrinter() public {
        CyberCertPrinter newCyberCertPrinterImplementation = new CyberCertPrinter();

        // Only factory can call the Issuance Manager to upgrade its CyberCert Printer
        vm.expectRevert(abi.encodeWithSelector(IssuanceManager.NotUpgradeFactory.selector));
        issuanceManager.upgradeBeaconImplementation(address(newCyberCertPrinterImplementation));

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), address(this)));
        issuanceManagerFactory.upgradePrinterBeaconAt(address(issuanceManager), address(newCyberCertPrinterImplementation));

        // Owner should be able to upgrade it
        vm.prank(multisig);
        issuanceManagerFactory.upgradePrinterBeaconAt(address(issuanceManager), address(newCyberCertPrinterImplementation));
        assertEq(issuanceManager.getBeaconImplementation(), address(newCyberCertPrinterImplementation));
    }
}
