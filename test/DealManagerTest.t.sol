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
import {IERC1967} from "../dependencies/openzeppelin-contracts/contracts/interfaces/IERC1967.sol";
import {CyberAgreementRegistry} from "../src/CyberAgreementRegistry.sol";
import {DealManager, LexScrowStorage} from "../src/DealManager.sol";
import {EscrowStatus} from "../src/storage/LexScrowStorage.sol";
import {IDealManager} from "../src/interfaces/IDealManager.sol";
import {IDealManagerStorage} from "../src/interfaces/IDealManagerStorage.sol";
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

    function voidCertificate(address certAddress, uint256 tokenId) external {
        CyberCertPrinterMock(certAddress).burn(tokenId);
    }
}

contract CyberCertPrinterMock is ERC721Enumerable {
    mapping(uint256 => Endorsement[]) endorsements;

    constructor() ERC721("Test Cert", "CERT") {}

    function mint(address to) public returns(uint256) {
        uint256 tokenId = totalSupply();
        _safeMint(to, tokenId);
        return tokenId;
    }

    function addEndorsement(uint256 tokenId, Endorsement memory newEndorsement) public {
        endorsements[tokenId].push(newEndorsement);
    }

    function getEndorsementHistory(uint256 tokenId, uint256 index) external view returns (Endorsement memory) {
        return endorsements[tokenId][index];
    }

    function burn(uint256 tokenId) external {
        _burn(tokenId);
    }

    // DealManager now voids the seller cert directly on the printer (was routed via IssuanceManager).
    function voidCert(uint256 tokenId) external {
        _burn(tokenId);
    }
}

contract CyberAgreementRegistryMock {
    mapping(bytes32 => bool) public isVoided;
    mapping(bytes32 => bool) public isFinalized;

    mapping(bytes => bool) private _isValidSignatures;
    mapping(address => bool) private _hasSigned;
    mapping(bytes32 => bool) private _isReadyToVoid;

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
        if (!_isValidSignatures[signature]) {
            revert CyberAgreementRegistry.SignatureVerificationFailed();
        }
        _hasSigned[signer] = true;
    }

    function finalizeContract(
        bytes32 contractId
    ) public {
        // No-op
    }

    function voidContractFor(
        bytes32 contractId,
        address party,
        bytes calldata signature
    ) public {
        if (isVoided[contractId]) {
            revert CyberAgreementRegistry.ContractAlreadyVoided();
        }
        if (_isReadyToVoid[contractId]) {
            isVoided[contractId] = true;
        }
    }

    function hasSigned(
        bytes32 contractId,
        address signer
    ) external view returns (bool) {
        // Applies to any contract
        return _hasSigned[signer];
    }

    function getSignerValues(
        bytes32,
        address
    ) external pure returns (string[] memory) {
        return new string[](0);
    }

    function allPartiesSigned(bytes32 contractId) public view returns (bool) {
        // Always signed
        return true;
    }

    function mockValidSignatures(
        bytes calldata signature,
        bool isValid
    ) external {
        _isValidSignatures[signature] = isValid;
    }

    function mockIsVoided(
        bytes32 contractId,
        bool _isVoided
    ) external {
        isVoided[contractId] = _isVoided;
    }

    function mockIsReadyToVoid(
        bytes32 contractId,
        bool __isReadyToVoid
    ) external {
        _isReadyToVoid[contractId] = __isReadyToVoid;
    }
}

contract CyberCorpMock {
    address public companyPayable;

    constructor(address _companyPayable) {
        companyPayable = _companyPayable;
    }
}

contract MockDealManagerVTest is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "test";

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override {}
}

contract DealManagerTest is Test {

    bytes public constant GOOD_SIGNATURE = "good signature";
    bytes public constant BAD_SIGNATURE = "bad signature";

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

        // Configure mock signatures

        registry.mockValidSignatures(GOOD_SIGNATURE, true);

        // Prepare funds

        paymentToken.mint(address(alice), 100 ether);

        vm.prank(alice);
        paymentToken.approve(address(dm), 100 ether);
    }

    function test_NormalFlow() public {

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        // Run through the typical deal flow

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        // Party 1 proposes the deal and sign
        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDeal();

        // Party 2 signs the deal, pays and finalizes it
        vm.prank(alice);
        dm.signAndFinalizeDeal(
            alice, // signer
            agreementId,
            new string[](0), // partyValues
            GOOD_SIGNATURE, // signature
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

    function testPOC_SignAndFinalizeDeal_BypassesSignatureWhenRegistryAlreadySigned() public {
        (bytes32 agreementId, ) = _proposeSignedDeal();

        // Alice signs directly in the registry first (out-of-band from DealManager).
        registry.signContractFor(
            alice,
            agreementId,
            new string[](0),
            GOOD_SIGNATURE,
            false,
            ""
        );

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        // Bob can now finalize on behalf of Alice with a bad signature because
        // DealManager skips signature verification when registry.hasSigned == true.
        vm.prank(bob);
        dm.signAndFinalizeDeal(
            alice, // signer
            agreementId,
            new string[](0), // partyValues
            BAD_SIGNATURE, // ignored on hasSigned branch
            false,
            "Bob as Alice",
            ""
        );

        assertEq(
            paymentToken.balanceOf(companyPayable),
            companyPaymentTokenBalancesBefore + 10 ether,
            "Bob triggers Alice payment/finalization with invalid signature"
        );
    }

    function test_PaymentFlow_ProposeDeal() public {
        // proposeDeal() is one of the two methods that'll pull certificates from the issuing company (first party)
        // Unlike the more generic LexScrowStorage, DealManager assumes the company's assets are certificates-only
        // After the transaction, the company's certificates should be in escrow.

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        // Party 1 proposes the deal and sign
        vm.prank(owner);
        (bytes32 agreementId, uint256[] memory certIds) = dm.proposeDeal(
            defaultCertPrinters,
            address(paymentToken),
            10 ether, // paymentAmount
            0, // templateId
            salt,
            new string[](0), // globalValues
            defaultParties,
            defaultCertDetails,
            partyValues,
            new address[](0), // TODO conditions
            bytes32(0), // secretHash
            block.timestamp // expiry
        );

        // Verify the certificates are in escrow
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), address(dm), "Corp Certificate should be in escrow");
    }

    function test_PaymentFlow_ProposeAndSignDeal() public {
        // proposeAndSignDeal() is one of the two methods that'll pull certificates from the issuing company (first party)
        // Unlike the more generic LexScrowStorage, DealManager assumes the company's assets are certificates-only
        // The signature must be valid.
        // After the transaction, the company's certificates should be in escrow.

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        // Party 1 proposes the deal and sign
        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDeal();

        // Verify the certificates are in escrow
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), address(dm), "Corp Certificate should be in escrow");
    }

    function test_RevertIf_PaymentFlow_ProposeAndSignDealBadSignature() public {
        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        // Party 1 proposes the deal and sign
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector));
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
            BAD_SIGNATURE, // signature
            partyValues,
            new address[](0), // TODO conditions
            bytes32(0), // secretHash
            block.timestamp // expiry
        );
    }

    function test_PaymentFlow_SignDealAndPay() public {
        // signDealAndPay() is one of the two methods that'll pull funds from the counterparty.
        // The deal must be available, and the signature must be valid.
        // After the transaction, the counterparty's fund should be in escrow

        uint256 escrowPaymentTokenBalanceBefore = paymentToken.balanceOf(address(dm));

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        // Verify the payment are in escrow
        assertEq(
            paymentToken.balanceOf(address(dm)),
            escrowPaymentTokenBalanceBefore + 10 ether,
            "Payment tokens should be in escrow"
        );

        // Verify the endorsement
        assertEq(
            CyberCertPrinterMock(
                dm.getEscrowDetails(agreementId).corpAssets[0].tokenAddress
            ).getEndorsementHistory(0, 0).endorsee,
            alice,
            "Alice should get the endorsement"
        );
    }

    function test_PaymentFlow_SignDealAndPayOnBehalf() public {
        // signDealAndPay() is one of the two methods that'll pull funds from the counterparty.
        // The deal must be available, and the signature must be valid.
        // After the transaction, the counterparty's fund should be in escrow

        uint256 escrowPaymentTokenBalanceBefore = paymentToken.balanceOf(address(dm));

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            bob // on Alice's behalf
        );

        // Verify the payment are in escrow
        assertEq(
            paymentToken.balanceOf(address(dm)),
            escrowPaymentTokenBalanceBefore + 10 ether,
            "Payment tokens should be in escrow"
        );

        // Verify the endorsement
        assertEq(
            CyberCertPrinterMock(
                dm.getEscrowDetails(agreementId).corpAssets[0].tokenAddress
            ).getEndorsementHistory(0, 0).endorsee,
            alice,
            "Alice should get the endorsement"
        );
    }

    function test_RevertIf_PaymentFlow_SignDealAndPayBadSignature() public {
        (bytes32 agreementId, ) = _proposeSignedDeal();

        // Party 2 sign and pay
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector));
        dm.signDealAndPay(
            alice, // signer
            agreementId,
            BAD_SIGNATURE, // signature
            new string[](0), // partyValues
            false, // TODO _fillUnallocated
            "Alice",
            ""
        );
    }

    function test_PaymentFlow_finalizeDeal() public {
        // finalizeDeal() should settle the deal and exchange the assets
        // The deal must be available, and the signature must be valid.
        // After the transaction the whole escrow and exchange should be complete and finalized

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        vm.expectEmit(true, true, true, true);
        emit IDealManagerStorage.DealFinalized(
            agreementId,
            alice,
            address(corp),
            address(registry),
            false
        );
        vm.prank(alice);
        dm.finalizeDeal(agreementId);

        // Verify the assets are exchanged
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), alice, "Alice should receive Corp Certificate");
        assertEq(
            paymentToken.balanceOf(companyPayable),
            companyPaymentTokenBalancesBefore + 10 ether,
            "Company should receive payment tokens"
        );
    }

    function test_PaymentFlow_finalizeDealOnBehalf() public {
        // finalizeDeal() should settle the deal and exchange the assets
        // Anyone can finalize the deal as long as the deal is ready.
        // After the transaction the whole escrow and exchange should be complete and finalized

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        vm.expectEmit(true, true, true, true);
        emit IDealManagerStorage.DealFinalized(
            agreementId,
            bob,
            address(corp),
            address(registry),
            false
        );
        vm.prank(bob); // by a non-party
        dm.finalizeDeal(agreementId);

        // Verify the assets are exchanged
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), alice, "Alice should receive Corp Certificate");
        assertEq(
            paymentToken.balanceOf(companyPayable),
            companyPaymentTokenBalancesBefore + 10 ether,
            "Company should receive payment tokens"
        );
    }

    function test_PaymentFlow_SignAndFinalizeDeal() public {
        // signAndFinalizeDeal() is the other one of the two methods that'll pull funds from the counterparty
        // The deal must be available, and the signature must be valid.
        // After the transaction the whole escrow and exchange should be complete and finalized

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        // Party 1 proposes the deal and sign
        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDeal();

        // Party 2 signs the deal, pays and finalizes it
        vm.prank(alice);
        dm.signAndFinalizeDeal(
            alice, // signer
            agreementId,
            new string[](0), // partyValues
            GOOD_SIGNATURE, // signature
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

    function test_PaymentFlow_SignAndFinalizeDealOnBehalf() public {
        // signAndFinalizeDeal() is the other one of the two methods that'll pull funds from the counterparty
        // The deal must be available, and the signature must be valid.
        // After the transaction the whole escrow and exchange should be complete and finalized

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        // Party 1 proposes the deal and sign
        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDeal();

        // Party 2 signs the deal, pays and finalizes it
        vm.prank(bob); // On Alice's behalf
        dm.signAndFinalizeDeal(
            alice, // signer
            agreementId,
            new string[](0), // partyValues
            GOOD_SIGNATURE, // signature
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

    function test_RevertIf_PaymentFlow_SignAndFinalizeDealBadSignature() public {
        // signAndFinalizeDeal() is the other one of the two methods that'll pull funds from the counterparty
        // The deal must be available, and the signature must be valid.
        // After the transaction the whole escrow and exchange should be complete and finalized

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        uint256 companyPaymentTokenBalancesBefore = paymentToken.balanceOf(companyPayable);

        // Party 1 proposes the deal and sign
        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDeal();

        // Party 2 signs the deal, pays and finalizes it
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector));
        dm.signAndFinalizeDeal(
            alice, // signer
            agreementId,
            new string[](0), // partyValues
            BAD_SIGNATURE, // signature
            false, // TODO _fillUnallocated
            "Alice",
            ""
        );
    }

    function test_PaymentFlow_SignToVoid() public {
        // signToVoid() should submit the signature for voiding an agreement.address.
        // When the conditions are met and the agreement is voided, it should also refund the payment token

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        uint256 alicePaymentTokenBalancesBefore = paymentToken.balanceOf(alice);

        // Simulate Alice sign to void
        vm.prank(alice);
        dm.signToVoid(agreementId, alice, GOOD_SIGNATURE);

        // The agreement wasn't successfully voided yet, so no refund issued
        assertEq(paymentToken.balanceOf(alice), alicePaymentTokenBalancesBefore, "Alice should not receive the refund yet");
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), address(dm), "Cert should still be escrowed");

        // Simulate company sign to void
        registry.mockIsReadyToVoid(agreementId, true);
        vm.prank(companyOwner);
        dm.signToVoid(agreementId, companyOwner, GOOD_SIGNATURE);

        assertEq(paymentToken.balanceOf(alice), alicePaymentTokenBalancesBefore + 10 ether, "Alice should receive the refund");
        _assertCertVoided(certIds[0]);
    }

    function test_SignToVoid_MutualVoidVoidsCertWithoutVoidExpiredDeal() public {
        // A mutual void locks out voidExpiredDeal (every party is already in voidRequestedBy), so
        // signToVoid must tear the escrowed certs down itself or they stay live forever.

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        vm.prank(alice);
        dm.signToVoid(agreementId, alice, GOOD_SIGNATURE);

        registry.mockIsReadyToVoid(agreementId, true);
        vm.prank(companyOwner);
        dm.signToVoid(agreementId, companyOwner, GOOD_SIGNATURE);

        _assertCertVoided(certIds[0]);

        // The registry teardown path stays closed — cleanup must not depend on it
        vm.warp(block.timestamp + 365 days);
        vm.prank(companyOwner);
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyVoided.selector);
        dm.voidExpiredDeal(agreementId, companyOwner, GOOD_SIGNATURE);
    }

    function test_SignToVoid_PendingDealVoidsEscrowAndCert() public {
        // Same teardown for a deal voided before payment: the escrow is re-synced to VOIDED and the
        // certs are voided, matching voidExpiredDeal's PENDING branch.

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDeal();

        registry.mockIsReadyToVoid(agreementId, true);
        vm.prank(companyOwner);
        dm.signToVoid(agreementId, companyOwner, GOOD_SIGNATURE);

        assertEq(uint8(dm.getEscrowDetails(agreementId).status), uint8(EscrowStatus.VOIDED), "Escrow should be voided");
        _assertCertVoided(certIds[0]);
    }

    function test_PaymentFlow_RefundVoidedDeal() public {
        // If the agreement is voided through the registry instead of Deal Manager,
        // DealManager should still be able to refund through other means

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        uint256 alicePaymentTokenBalancesBefore = paymentToken.balanceOf(alice);

        // Simulate the agreement being voided externally so it is out of sync with Deal Manager's state.
        // In such case, calling `dm.signToVoid()` would fail because Deal Manager would try to void the contract again
        registry.mockIsVoided(agreementId, true);
        vm.prank(companyOwner);
        vm.expectRevert(CyberAgreementRegistry.ContractAlreadyVoided.selector);
        dm.signToVoid(agreementId, companyOwner, GOOD_SIGNATURE);

        // Should call `refundVoidedDeal()` instead so Deal Manager would re-sync and refund
        dm.refundVoidedDeal(agreementId);

        assertEq(paymentToken.balanceOf(alice), alicePaymentTokenBalancesBefore + 10 ether, "Alice should receive the refund");
        _assertCertVoided(certIds[0]);
    }

    function test_RevertIf_PaymentFlow_RefundVoidedDealNotVoided() public {
        // Deal Manager must check the agreement being voided before refund

        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        (bytes32 agreementId, uint256[] memory certIds) = _proposeSignedDealAndPay(
            alice,
            GOOD_SIGNATURE,
            alice
        );

        // Refund should fail because the deal is not voided
        vm.expectRevert(LexScrowStorage.DealNotVoided.selector);
        dm.refundVoidedDeal(agreementId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Id-space validation: primary entrypoints require a primary escrow. An id with no primary escrow
    // (an unknown id, or a secondary-trade settlement — which never creates a LexScrow escrow) reverts
    // DealDoesNotExist. The guard runs first, so caller/state checks are not reached.
    // ─────────────────────────────────────────────────────────────────────────

    function test_RevertIf_FinalizeDeal_UnknownDeal() public {
        vm.expectRevert(LexScrowStorage.DealDoesNotExist.selector);
        dm.finalizeDeal(keccak256("unknown-deal"));
    }

    function test_RevertIf_VoidExpiredDeal_UnknownDeal() public {
        vm.expectRevert(LexScrowStorage.DealDoesNotExist.selector);
        dm.voidExpiredDeal(keccak256("unknown-deal"), alice, "");
    }

    function test_VoidExpiredDeal_VoidsCert() public {
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        uint256 expiry = block.timestamp + 1 days;

        vm.prank(owner);
        (bytes32 agreementId, uint256[] memory certIds) = dm.proposeAndSignDeal(
            defaultCertPrinters,
            address(paymentToken),
            10 ether, // paymentAmount
            0, // templateId
            uint256(keccak256("DealManagerTest.Deal")),
            new string[](0), // globalValues
            defaultParties,
            defaultCertDetails,
            companyOwner, // proposer
            GOOD_SIGNATURE, // signature
            partyValues,
            new address[](0), // TODO conditions
            bytes32(0), // secretHash
            expiry
        );

        // Cert is now in escrow (owned by DealManager)
        assertEq(CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]), address(dm));

        vm.warp(expiry + 1);

        // signer must be a party to the agreement (companyOwner); DealManager is the finalizer so no void sig is needed
        dm.voidExpiredDeal(agreementId, companyOwner, "");

        // Cert should be burned (voided) via IssuanceManager.voidCertificate
        vm.expectRevert();
        CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certIds[0]); // burned token should revert on ownerOf
    }

    function test_RevertIf_RevokeDeal_UnknownDeal() public {
        vm.prank(alice);
        vm.expectRevert(LexScrowStorage.DealDoesNotExist.selector);
        dm.revokeDeal(keccak256("unknown-deal"), alice, "");
    }

    function test_RevertIf_SignToVoid_UnknownDeal() public {
        vm.prank(alice);
        vm.expectRevert(LexScrowStorage.DealDoesNotExist.selector);
        dm.signToVoid(keccak256("unknown-deal"), alice, "");
    }

    function test_RevertIf_RefundVoidedDeal_UnknownDeal() public {
        vm.expectRevert(LexScrowStorage.DealDoesNotExist.selector);
        dm.refundVoidedDeal(keccak256("unknown-deal"));
    }

    function test_UpgradeNextDealManager() public {
        vm.startPrank(owner);
        DealManagerFactory(dmFactory).setRefImplementation(address(new MockDealManagerVTest()));
        vm.stopPrank();
        assertEq(DealManager(DealManagerFactory(dmFactory).getRefImplementation()).DEPLOY_VERSION(), "test", "reference impl version should have changed");

        bytes32 salt = keccak256("test_UpgradeNextDealerManager");
        // Next deployment should emit events with version so indexer could be informed
        vm.expectEmit(true, true, true, true);
        emit DealManagerFactory.DealManagerDeployed(
            DealManagerFactory(dmFactory).computeDealManagerAddress(salt),
            "test"
        );
        DealManager nextRm = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(salt)
        );
        assertEq(nextRm.DEPLOY_VERSION(), "test", "next deployment version should have changed");
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
        DealManagerFactory(dmFactory).setRefImplementation(address(new MockDealManagerVTest()));
        vm.stopPrank();

        // Corp2 owner decided to accept the upgrade

        vm.startPrank(companyOwner);
        vm.expectEmit(true, true, true, true);
        emit IERC1967.Upgraded(DealManagerFactory(dmFactory).getRefImplementation());
        dm2.upgradeToAndCall(DealManagerFactory(dmFactory).getRefImplementation(), "");
        vm.stopPrank();

        assertEq(dm2.DEPLOY_VERSION(), "test", "Target DealManager should be upgraded");
        assertNotEq(dm1.DEPLOY_VERSION(), "test", "Other DealManager should not be upgraded");
    }

    function test_RevertIf_UpgradeNonFactoryOwner() public {
        // Non-MetaLeX admin should not be able to set new reference implementation

        address newImplementation = address(new MockDealManagerVTest());
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, bootstrapAuth.OWNER_ROLE(), companyOwner));
        vm.prank(companyOwner);
        DealManagerFactory(dmFactory).setRefImplementation(newImplementation);
    }

    function test_RevertIf_UpgradeExistingDealManagerNotRefImplementation() public {
        BorgAuth corpAuth = new BorgAuth{salt: keccak256("testUpgradeExistingDealManager")}(companyOwner);
        address placeHolderAddr = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;

        // Deploy existing DealManagers

        DealManager dm = DealManager(
            DealManagerFactory(dmFactory).deployDealManager(keccak256("testUpgradeExistingDealManager2"))
        );
        dm.initialize(
            address(corpAuth),
            placeHolderAddr,
            placeHolderAddr,
            placeHolderAddr,
            address(dmFactory)
        );

        // Corp owner can't upgrade to v2 without MetaLeX releasing it first

        vm.startPrank(companyOwner);
        address nonOfficialDealManager = address(new MockDealManagerVTest());
        vm.expectRevert(
            abi.encodeWithSelector(DealManager.NotRefImplementation.selector)
        );
        dm.upgradeToAndCall(nonOfficialDealManager, "");
        vm.stopPrank();
    }

    function _proposeSignedDeal() internal returns (bytes32 agreementId, uint256[] memory certIds) {
        // Deal configs

        uint256 salt = uint256(keccak256("DealManagerTest.Deal"));

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](0);
        partyValues[1] = new string[](0);

        // Party 1 proposes the deal and sign
        vm.prank(owner);
        (agreementId, certIds) = dm.proposeAndSignDeal(
            defaultCertPrinters,
            address(paymentToken),
            10 ether, // paymentAmount
            0, // templateId
            salt,
            new string[](0), // globalValues
            defaultParties,
            defaultCertDetails,
            companyOwner, // proposer
            GOOD_SIGNATURE, // signature
            partyValues,
            new address[](0), // TODO conditions
            bytes32(0), // secretHash
            block.timestamp // expiry
        );
    }

    /// @dev The mock printer burns on voidCert, so a voided cert no longer resolves an owner.
    function _assertCertVoided(uint256 certId) internal {
        vm.expectRevert();
        CyberCertPrinterMock(defaultCertPrinters[0]).ownerOf(certId);
    }

    function _proposeSignedDealAndPay(
        address counterparty,
        bytes memory counterpartySignature,
        address counterpartyOnBehalf
    ) internal returns (bytes32 agreementId, uint256[] memory certIds) {
        // Party 1 proposes the deal and sign
        (agreementId, certIds) = _proposeSignedDeal();

        // Party 2 sign and pay
        vm.prank(counterpartyOnBehalf);
        dm.signDealAndPay(
            counterparty, // signer
            agreementId,
            counterpartySignature, // signature
            new string[](0), // partyValues
            false, // TODO _fillUnallocated
            "Alice",
            ""
        );

        return (agreementId, certIds);
    }
}

contract DealManagerForkTest is Test {
    function setUp() public {
        vm.createSelectFork("sepolia");
    }

    function test_forkedSepoliaDealManager() public {
        address sepDmFactoryAddr = 0x3982b078f2ac306219c9540Ebc908360a960C251;
        address sepDmAddr = 0xeAb084914b434059C340fb8C3ebEAe9b04A14929;

        DealManager sepDm = DealManager(sepDmAddr);

        vm.startPrank(0x341Da9fb8F9bD9a775f6bD641091b24Dd9aA459B);
        DealManagerFactory(sepDmFactoryAddr).setRefImplementation(address(new MockDealManagerVTest()));
        address toUpgrade = DealManagerFactory(sepDmFactoryAddr).getRefImplementation();
        sepDm.upgradeToAndCall(toUpgrade, "");
        vm.stopPrank();

        assertEq(sepDm.DEPLOY_VERSION(), "test", "Target DealManager should be upgraded");
    }
}
