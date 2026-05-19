// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

/// @dev kToken0 Protocol Error Codes
/// Error codes use contract-specific prefixes for easier debugging:
///      - F*: kTokenFactory errors
///      - T*: kToken errors

// kToken Errors
string constant KTOKEN_IS_PAUSED = "T1";
string constant KTOKEN_TRANSFER_FAILED = "T2";
string constant KTOKEN_ZERO_ADDRESS = "T3";
string constant KTOKEN_ZERO_AMOUNT = "T4";
string constant KTOKEN_WRONG_ROLE = "T5";
string constant KTOKEN_ACCOUNT_FROZEN = "T6";
string constant KTOKEN_CANNOT_FREEZE_OWNER = "T7";

// kTokenFactory Errors
string constant KTOKENFACTORY_ZERO_ADDRESS = "F1";
string constant KTOKENFACTORY_DEPLOYMENT_FAILED = "F2";
string constant KTOKENFACTORY_WRONG_ROLE = "F3";
