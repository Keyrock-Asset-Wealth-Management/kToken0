// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { kOFTAdapter } from "../src/kOFTAdapter.sol";
import { kToken } from "../src/kToken.sol";

import { DeploymentManager } from "./DeploymentManager.s.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { console2 } from "forge-std/Script.sol";

/// @title DeployOFTAdapterOnly
/// @notice Deploys kOFTAdapter for an existing kToken on hub (KAM integration)
/// @dev Use this when kToken is already deployed via KAM's kRegistry on mainnet and you need
/// to add crosschain capability. The adapter locks/releases kToken (preserves total supply).
///
/// KAM Integration Flow:
/// 1. KAM deploys kToken via kRegistry.registerAsset() on mainnet
/// 2. Run this script to deploy kOFTAdapter for the existing kToken
/// 3. Deploy kToken + kOFT on spoke chains using DeploySpoke.s.sol
/// 4. Configure peers between kOFTAdapter (hub) and kOFT (spokes)
///
/// Note: kOFTAdapter does NOT need MINTER_ROLE - it locks/releases, doesn't mint/burn
contract DeployOFTAdapterOnly is DeploymentManager {
    kToken public token;
    kOFTAdapter public adapter;

    function run() public {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        validateConfig(config);
        logConfig(config);

        // Require existing kToken address
        require(config.existingKToken != address(0), "existingKToken address required in config");
        token = kToken(config.existingKToken);

        console2.log("=== Deploying kOFTAdapter for Existing kToken (Hub) ===");
        console2.log("Existing kToken:", address(token));
        console2.log("kToken name:", token.name());
        console2.log("kToken symbol:", token.symbol());
        console2.log("kToken decimals:", token.decimals());

        vm.startBroadcast();

        // Deploy kOFTAdapter
        console2.log("=== Deploying kOFTAdapter ===");
        kOFTAdapter adapterImplementation = new kOFTAdapter(address(token), config.layerZero.lzEndpoint);
        bytes memory adapterData = abi.encodeCall(kOFTAdapter.initialize, (config.roles.delegate, config.roles.owner));
        ERC1967Proxy adapterProxy = new ERC1967Proxy(address(adapterImplementation), adapterData);
        adapter = kOFTAdapter(address(adapterProxy));
        console2.log("kOFTAdapter implementation:", address(adapterImplementation));
        console2.log("kOFTAdapter proxy deployed at:", address(adapter));

        vm.stopBroadcast();

        // Write deployment addresses
        writeContractAddress("kToken", address(token));
        writeContractAddress("kOFTAdapter", address(adapter));
        writeContractAddress("kOFTAdapterImplementation", address(adapterImplementation));

        // Summary
        console2.log("=== Deployment Summary ===");
        console2.log("kToken (existing):", address(token));
        console2.log("kOFTAdapter (new):", address(adapter));
        console2.log("LayerZero Endpoint:", config.layerZero.lzEndpoint);
        console2.log("LayerZero EID:", config.layerZero.lzEid);
        console2.log("Delegate:", config.roles.delegate);
        console2.log("Owner:", config.roles.owner);
        console2.log("Architecture: Hub - kToken locked/released (total supply preserved)");

        console2.log("");
        console2.log("=== Next Steps ===");
        console2.log("1. Deploy kToken + kOFT on spoke chains using DeploySpoke.s.sol");
        console2.log("2. Configure peers between kOFTAdapter (hub) and kOFT (spokes)");
        console2.log("3. Users must approve kOFTAdapter to spend their kTokens before bridging");
    }
}
