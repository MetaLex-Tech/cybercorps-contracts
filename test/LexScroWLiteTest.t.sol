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
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {LexScroWLite} from "../src/libs/LexScroWLite.sol";

contract LexScroWLiteMock is LexScroWLite {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _corp, address _dealRegistry) public initializer {
        __LexScroWLite_init(_corp, _dealRegistry);
    }
}

contract CyberCorpMock {
    address public companyPayable;

    constructor(address _companyPayable) {
        companyPayable = _companyPayable;
    }
}

contract LexScroWLiteTest is Test {

    bytes32 public salt = keccak256("LexScroWLiteTest");

    uint256 ownerPrivateKey = uint256(salt) + 0;
    address owner = vm.addr(ownerPrivateKey);

    address companyPayable = address(1);

    CyberAgreementRegistry public registry;
    CyberCorpMock public corp;
    LexScroWLiteMock public lexScrow;

    function setUp() public {
        BorgAuth auth = new BorgAuth{salt: salt}(owner);

        registry = CyberAgreementRegistry(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new CyberAgreementRegistry{salt: salt}()),
                    abi.encodeWithSelector(
                        CyberAgreementRegistry.initialize.selector,
                        address(auth)
                    )
                )
            )
        );

        corp = new CyberCorpMock{salt: salt}(companyPayable);

        lexScrow = LexScroWLiteMock(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new LexScroWLiteMock{salt: salt}()),
                    abi.encodeWithSelector(
                        LexScroWLiteMock.initialize.selector,
                        address(corp),
                        address(registry)
                    )
                )
            )
        );
    }

    function test_NormalFlowMinimal() public {}

    function test_NormalFlowWithExpiry() public {}

    function test_NormalFlowWithCondition() public {}

    function test_AddCondition() public {}

    function test_RemoveCondition() public {}

    function test_VoidExpiredUnpaid() public {}

    function test_VoidExpiredPaid() public {}

    function test_VoidByPartyUnpaid() public {}

    function test_VoidByPartyPaid() public {}
}
