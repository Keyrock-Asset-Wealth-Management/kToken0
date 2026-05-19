// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { kOFT } from "../src/kOFT.sol";
import { kToken } from "../src/kToken.sol";

import { DeploymentManager } from "./DeploymentManager.s.sol";
import { console2 } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

/// @title DeployKOFTOnly
/// @notice Deploys kOFT for an existing kToken on spoke chains
/// @dev Use this when kToken is already deployed on a spoke chain and you need to add
/// crosschain capability. The kOFT will mint/burn via ERC7802 (crosschainMint/crosschainBurn).
///
/// Spoke Integration Flow:
/// 1. kToken already deployed on spoke (same contract as hub)
/// 2. Run this script to deploy kOFT for the existing kToken
/// 3. Admin grants MINTER_ROLE to kOFT: kToken.grantMinterRole(kOFTAddress)
/// 4. Configure peers with hub's kOFTAdapter
///
/// Note: kOFT REQUIRES MINTER_ROLE on kToken to call crosschainMint/crosschainBurn
contract DeployKOFTOnly is DeploymentManager {
    kToken public token;
    kOFT public koft;

    function run() public {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        validateConfig(config);
        logConfig(config);

        // Require existing kToken address
        require(config.existingKToken != address(0), "existingKToken address required in config");
        token = kToken(config.existingKToken);

        console2.log("=== Deploying kOFT for Existing kToken (Spoke) ===");
        console2.log("Existing kToken:", address(token));
        console2.log("kToken name:", token.name());
        console2.log("kToken symbol:", token.symbol());
        console2.log("kToken decimals:", token.decimals());

        vm.startBroadcast();

        // Deploy proxy factory
        MinimalUUPSFactory proxyFactory = new MinimalUUPSFactory();

        // Deploy kOFT
        console2.log("=== Deploying kOFT ===");
        kOFT oftImplementation = new kOFT(config.layerZero.lzEndpoint, token);
        bytes memory oftData = abi.encodeCall(kOFT.initialize, (config.roles.delegate, config.roles.owner));
        address oftProxy = proxyFactory.deployAndCall(address(oftImplementation), oftData);
        koft = kOFT(oftProxy);
        console2.log("kOFT implementation:", address(oftImplementation));
        console2.log("kOFT proxy deployed at:", address(koft));

        vm.stopBroadcast();

        // Write deployment addresses
        writeContractAddress("kToken", address(token));
        writeContractAddress("kOFT", address(koft));
        writeContractAddress("kOFTImplementation", address(oftImplementation));

        // Summary
        console2.log("=== Deployment Summary ===");
        console2.log("kToken (existing):", address(token));
        console2.log("kOFT (new):", address(koft));
        console2.log("LayerZero Endpoint:", config.layerZero.lzEndpoint);
        console2.log("LayerZero EID:", config.layerZero.lzEid);
        console2.log("Delegate:", config.roles.delegate);
        console2.log("Owner:", config.roles.owner);
        console2.log("Architecture: Spoke - kOFT mints/burns via ERC7802");

        console2.log("");
        console2.log("=== IMPORTANT: Manual Steps Required ===");
        console2.log("1. Grant MINTER_ROLE to kOFT on kToken:");
        console2.log("   kToken.grantMinterRole(", address(koft), ")");
        console2.log("2. Configure peers with hub's kOFTAdapter using ConfigurePeers.s.sol");
    }
}
