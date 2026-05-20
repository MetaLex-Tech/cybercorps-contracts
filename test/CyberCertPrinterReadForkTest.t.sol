// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ICyberCertPrinter} from "../src/interfaces/ICyberCertPrinter.sol";
import {CertificateDetails} from "../src/storage/CyberCertPrinterStorage.sol";

contract CyberCertPrinterReadForkTest is Test {
    address internal constant PRINTER = 0xf77f10816D376E2D1f4a3FAF548E0E9142aB11D9;

    function setUp() public {
        vm.createSelectFork("base_sepolia");
    }

    function test_ReadPrinterUriAndCertificateDetails() public {
        ICyberCertPrinter printer = ICyberCertPrinter(PRINTER);

        console2.log("printer", PRINTER);
        console2.log("name", printer.name());
        console2.log("symbol", printer.symbol());
        console2.log("certificateUri", printer.certificateUri());

        uint256 supply = printer.totalSupply();
        console2.log("totalSupply", supply);

        if (supply == 0) {
            console2.log("No certificates minted on this printer yet.");
            return;
        }

        uint256 tokenId = printer.tokenByIndex(0);
        console2.log("tokenId", tokenId);

        try printer.tokenURI(tokenId) returns (string memory uri) {
            console2.log("tokenURI", uri);
        } catch {
            console2.log("tokenURI read reverted");
        }

        try printer.getCertificateDetails(tokenId) returns (CertificateDetails memory details) {
            console2.log("signingOfficerName", details.signingOfficerName);
            console2.log("signingOfficerTitle", details.signingOfficerTitle);
            console2.log("investmentAmountUSD", details.investmentAmountUSD);
            console2.log("issuerUSDValuationAtTimeOfInvestment", details.issuerUSDValuationAtTimeOfInvestment);
            console2.log("unitsRepresented", details.unitsRepresented);
            console2.log("legalDetails", details.legalDetails);
            console2.logBytes(details.extensionData);
        } catch {
            console2.log("certificate details read reverted");
        }
    }
}
