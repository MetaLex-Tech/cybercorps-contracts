// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {CertificateUriBuilder} from "../src/CertificateUriBuilder.sol";
import {CertificateSVGParams, SecurityClass, SecuritySeries} from "../src/CyberCorpConstants.sol";
import {ICertificateImageBuilder} from "../src/interfaces/ICertificateImageBuilder.sol";
import {BorgAuth} from "../src/libs/auth.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

contract StaticCertificateImageBuilder is ICertificateImageBuilder {
    function buildCertificateSVG(CertificateSVGParams calldata, uint256) external pure returns (string memory) {
        return "<svg/>";
    }
}

contract CertificateContextMock {
    function unitsReserved(uint256) external pure returns (uint256) {
        return 0;
    }

    function issuanceManager() external view returns (address) {
        return address(this);
    }

    function CORP() external pure returns (address) {
        return address(0);
    }

    function getSeriesInfo()
        external
        pure
        returns (address extension, bytes memory data)
    {
        return (address(0), "");
    }
}

contract CertificateUriBuilderJsonEscapingTest is Test {
    CertificateUriBuilder private builder;
    CertificateContextMock private certificateContext;

    function setUp() public {
        BorgAuth auth = new BorgAuth(address(this));
        builder = CertificateUriBuilder(
            address(
                new ERC1967Proxy(
                    address(new CertificateUriBuilder()),
                    abi.encodeCall(CertificateUriBuilder.initialize, (address(auth)))
                )
            )
        );
        builder.setImageBuilder(address(new StaticCertificateImageBuilder()));
        certificateContext = new CertificateContextMock();
    }

    function test_LegalDetailsCannotInjectForgedUnitsRepresented() public view {
        string memory maliciousLegalDetails = 'ok", "unitsRepresented": "999999999';
        CertificateUriBuilder.CertificateDetails memory details = _details(maliciousLegalDetails);

        string memory json = _build(details, _owner("Alice"), _endorsements(""));

        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".unitsRepresented"), "1000.00");
        assertEq(vm.parseJsonString(json, ".legalDetails"), maliciousLegalDetails);
        assertEq(vm.parseJsonString(json, ".cyberCORPName"), 'Corp", "forged": "true');
        assertEq(vm.parseJsonString(json, ".restrictiveLegends[0].text"), 'Legend", "forged": "true');
    }

    function test_UserControlledNamesRemainDataAndJsonStaysValid() public view {
        string memory maliciousName = 'Alice", "unitsRepresented": "999999999';
        CertificateUriBuilder.Endorsement[] memory endorsements = _endorsements(maliciousName);

        string memory json = _build(_details("ok"), _owner(maliciousName), endorsements);

        vm.parseJson(json);
        assertEq(vm.parseJsonString(json, ".currentOwner.name"), maliciousName);
        assertEq(vm.parseJsonString(json, ".endorsementHistory[0].investorName"), maliciousName);
        assertEq(vm.parseJsonString(json, ".unitsRepresented"), "1000.00");
    }

    function _build(
        CertificateUriBuilder.CertificateDetails memory details,
        CertificateUriBuilder.OwnerDetails memory owner,
        CertificateUriBuilder.Endorsement[] memory endorsements
    ) private view returns (string memory) {
        string[] memory legends = new string[](1);
        legends[0] = 'Legend", "forged": "true';

        return builder.buildCertificateUriNotEncoded(
            'Corp", "forged": "true',
            "C-Corp",
            "DE",
            "contact@example.com",
            SecurityClass.CommonStock,
            SecuritySeries.SeriesA,
            "ipfs://certificate",
            legends,
            details,
            endorsements,
            owner,
            address(0),
            bytes32(0),
            1,
            address(certificateContext),
            address(0)
        );
    }

    function _details(string memory legalDetails)
        private
        pure
        returns (CertificateUriBuilder.CertificateDetails memory)
    {
        return CertificateUriBuilder.CertificateDetails({
            signingOfficerName: 'Officer "Name"',
            signingOfficerTitle: "President",
            investmentAmountUSD: 1000 ether,
            issuerUSDValuationAtTimeOfInvestment: 1_000_000 ether,
            unitsRepresented: 1000 ether,
            legalDetails: legalDetails,
            extensionData: ""
        });
    }

    function _owner(string memory name) private pure returns (CertificateUriBuilder.OwnerDetails memory) {
        return CertificateUriBuilder.OwnerDetails({name: name, ownerAddress: address(0xA11CE)});
    }

    function _endorsements(string memory name)
        private
        pure
        returns (CertificateUriBuilder.Endorsement[] memory endorsements)
    {
        if (bytes(name).length == 0) {
            return new CertificateUriBuilder.Endorsement[](0);
        }

        endorsements = new CertificateUriBuilder.Endorsement[](1);
        endorsements[0] = CertificateUriBuilder.Endorsement({
            endorser: address(0xB0B),
            timestamp: 1,
            signatureHash: "",
            registry: address(0),
            agreementId: bytes32(0),
            endorsee: address(0xA11CE),
            endorseeName: name
        });
    }
}
