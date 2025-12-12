// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

struct GnosisTransaction {
    address to;
    uint256 value;
    bytes data;
}
