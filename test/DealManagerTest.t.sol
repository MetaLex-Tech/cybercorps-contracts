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
import {ERC20} from "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "../dependencies/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "../dependencies/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC1967Proxy} from "../dependencies/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DealManager} from "../src/DealManager.sol";
import {DealManagerFactory} from "../src/DealManagerFactory.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {CertificateDetails, Endorsement} from "../src/storage/CyberCertPrinterStorage.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract IssuanceManagerMock {
    function createCert(
        address certAddress,
        address to,
        CertificateDetails memory _details
    ) external returns (uint256) {
        return CyberCertPrinterMock(certAddress).mint(to);
    }
}

contract CyberCertPrinterMock is ERC721Enumerable {
    constructor() ERC721("Test Cert", "CERT") {}

    function mint(address to) public returns(uint256) {
        uint256 tokenId = totalSupply();
        _safeMint(to, tokenId);
        return tokenId;
    }

    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        // no-op
    }
}

contract CyberAgreementRegistryMock {
    mapping(bytes32 => bool) public isVoided;
    mapping(bytes32 => bool) public isFinalized;

    function createContract(
        bytes32 templateId,
        uint256 salt,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes32 secretHash,
        address finalizer,
        uint256 expiry
    ) external returns (bytes32) {
        return keccak256("DealManagerTest.Agreement");
    }

    function signContractFor(
        address signer,
        bytes32 contractId,
        string[] memory partyValues,
        bytes calldata signature,
        bool fillUnallocated, // to fill a 0 address or not
        string memory secret
    ) external {
        // No-op
    }

    function finalizeContract(
        bytes32 contractId
    ) public {
        // No-op
    }

    function hasSigned(
        bytes32 contractId,
        address signer
    ) external view returns (bool) {
        // Always signed
        return true;
    }

    function allPartiesSigned(bytes32 contractId) public view returns (bool) {
        // Always signed
        return true;
    }
}

contract CyberCorpMock {
    address public companyPayable;

    constructor(address _companyPayable) {
        companyPayable = _companyPayable;
    }
}

contract DealManagerTest is Test {

    bytes32 public salt = keccak256("DealManagerTest");

    uint256 public ownerPrivateKey = uint256(salt) + 0;
    address public owner = vm.addr(ownerPrivateKey);

    address public companyPayable = address(1000);
    address public companyOwner = address(1001);
    address public alice = address(1002);
    address public bob = address(1003);

    ERC20Mock public paymentToken = new ERC20Mock("Payment Token", "PAY");
    address[] public defaultParties;
    CertificateDetails[] public defaultCertDetails;
    address[] public defaultCertPrinters;

    BorgAuth public bootstrapAuth;

    CyberAgreementRegistryMock public registry;
    CyberCorpMock public corp;
    IssuanceManagerMock public im;

    DealManagerFactory public dmFactory;
    DealManager public dm;

    function setUp() public {
        defaultParties = new address[](2);
        defaultParties[0] = companyOwner;
        defaultParties[1] = alice;

        defaultCertDetails = new CertificateDetails[](1);
        defaultCertDetails[0];

        bootstrapAuth = new BorgAuth(owner);

        registry = new CyberAgreementRegistryMock{salt: salt}();
        corp = new CyberCorpMock{salt: salt}(companyPayable);
        im = new IssuanceManagerMock{salt: salt}();
        defaultCertPrinters = new address[](1);
        defaultCertPrinters[0] = address(new CyberCertPrinterMock{salt: salt}());

        dmFactory = new DealManagerFactory{salt: salt}(address(bootstrapAuth));
        dm = DealManager(
            address(
                new ERC1967Proxy{salt: salt}(
                    address(new DealManager{salt: salt}()),
                    abi.encodeWithSelector(
                        DealManager.initialize.selector,
                        address(bootstrapAuth),
                        address(corp),
                        address(registry),
                        address(im),
                        address(dmFactory)
                    )
                )
            )
        );

        // Prepare funds

        paymentToken.mint(address(alice), 100 ether);

        vm.prank(alice);
        paymentToken.approve(address(dm), 100 ether);
    }

    function test_NormalFlow() public {

        // Escrow configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        // Run through the typical deal flow

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        // Party 1 proposes the deal and sign
        vm.prank(owner);
        (bytes32 agreementId, uint256[] memory certIds) = dm.proposeAndSignDeal(
            defaultCertPrinters,
            address(paymentToken),
            10 ether, // paymentAmount
            0, // templateId
            salt,
            new string[](0), // globalValues
            defaultParties,
            defaultCertDetails,
            companyOwner, // proposer
            "corpOwnerSignature", // signature
            partyValues,
            new address[](0), // TODO conditions
            bytes32(0), // secretHash
            block.timestamp // expiry
        );

        // Party 2 signs the deal, pays and finalizes it
        vm.prank(alice);
        dm.signAndFinalizeDeal(
            alice, // signer
            agreementId,
            new string[](0), // partyValues
            "aliceSignature", // signature
            false, // TODO _fillUnallocated
            "Alice",
            ""
        );

        // Verify the assets are exchanged
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), alice, "Alice should receive Corp Certificate");
        assertEq(
            paymentToken.balanceOf(companyPayable),
            companyPaymentTokenBalancesBefore + 10 ether,
            "Company should receive payment tokens"
        );
    }
}
