// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { kOFTAdapter } from "../src/kOFTAdapter.sol";
import { kToken } from "../src/kToken.sol";

import { DeploymentManager } from "./DeploymentManager.s.sol";
import { console2 } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

/// @title DeployHub
/// @notice Deploys kToken + kOFTAdapter for hub (mainnet) deployment
/// @dev Hub uses kOFTAdapter (lock/release) for total supply control and accounting guarantees.
/// The kToken on mainnet represents the canonical supply backed 1:1 by underlying assets via KAM.
///
/// Architecture:
/// - kToken: ERC20 with ERC7802 interface (crosschainMint/crosschainBurn available for bridges)
/// - kOFTAdapter: Locks kToken on send, releases on receive (total supply unchanged)
/// - Spokes use kOFT which mints/burns via ERC7802
///
/// Benefits of lock/release on hub:
/// - totalSupply on mainnet = actual backed amount (single source of truth)
/// - Easy auditing: locked amount shows cross-chain exposure
/// - Compromise on spoke limited to locked amount
contract DeployHub is DeploymentManager {
    kToken public token;
    kOFTAdapter public adapter;

    string public name;
    string public symbol;
    uint8 public decimals;

    function run() public {
        // Read network configuration
        NetworkConfig memory config = readNetworkConfig();
        validateConfig(config);
        logConfig(config);

        // Token configuration
        name = "kUSD Token";
        symbol = "kUSD";
        decimals = 6; // USDC decimals

        vm.startBroadcast();

        // Deploy proxy factory
        MinimalUUPSFactory proxyFactory = new MinimalUUPSFactory();

        // Check if we should use existing kToken or deploy new one
        if (config.existingKToken != address(0)) {
            // Use existing kToken (e.g., deployed via KAM's kRegistry)
            console2.log("=== Using Existing kToken (Hub) ===");
            token = kToken(config.existingKToken);
            console2.log("Using existing kToken at:", address(token));
        } else {
            // Deploy new kToken via proxy
            console2.log("=== Deploying kToken (Hub) ===");
            kToken tokenImplementation = new kToken();
            bytes memory tokenInitData = abi.encodeCall(
                kToken.initialize,
                (
                    config.roles.owner,
                    config.roles.admin,
                    config.roles.emergencyAdmin,
                    msg.sender, // temporary minter
                    name,
                    symbol,
                    decimals
                )
            );
            address tokenProxy = proxyFactory.deployAndCall(address(tokenImplementation), tokenInitData);
            token = kToken(tokenProxy);
            console2.log("kToken implementation:", address(tokenImplementation));
            console2.log("kToken proxy deployed at:", address(token));

            // Write kToken implementation address
            writeContractAddress("kTokenImplementation", address(tokenImplementation));
        }

        // Deploy kOFTAdapter (Hub uses lock/release for total supply control)
        console2.log("=== Deploying kOFTAdapter (Hub) ===");
        kOFTAdapter adapterImplementation = new kOFTAdapter(address(token), config.layerZero.lzEndpoint);
        bytes memory adapterData = abi.encodeCall(kOFTAdapter.initialize, (config.roles.delegate, config.roles.owner));
        address adapterProxy = proxyFactory.deployAndCall(address(adapterImplementation), adapterData);
        adapter = kOFTAdapter(adapterProxy);
        console2.log("kOFTAdapter implementation:", address(adapterImplementation));
        console2.log("kOFTAdapter proxy deployed at:", address(adapter));

        // Note: kOFTAdapter does NOT need MINTER_ROLE - it locks/releases, doesn't mint/burn
        // Users must approve kOFTAdapter to transfer their kTokens

        // Remove MINTER_ROLE from deployer for security (only if we deployed new kToken)
        if (config.existingKToken == address(0)) {
            try token.revokeMinterRole(msg.sender) {
                console2.log("Removed MINTER_ROLE from deployer");
            } catch {
                console2.log("Deployer did not have MINTER_ROLE or revocation failed");
            }
        }

        vm.stopBroadcast();

        // Write deployment addresses
        writeContractAddress("kToken", address(token));
        writeContractAddress("kOFTAdapter", address(adapter));
        writeContractAddress("kOFTAdapterImplementation", address(adapterImplementation));

        // Summary
        console2.log("=== Hub Deployment Summary ===");
        console2.log("Network: Hub (Mainnet)");
        if (config.existingKToken != address(0)) {
            console2.log("kToken: (existing)", address(token));
        } else {
            console2.log("kToken: (new)", address(token));
        }
        console2.log("kOFTAdapter:", address(adapter));
        console2.log("LayerZero Endpoint:", config.layerZero.lzEndpoint);
        console2.log("LayerZero EID:", config.layerZero.lzEid);
        console2.log("Delegate:", config.roles.delegate);
        console2.log("Owner:", config.roles.owner);
        console2.log("Architecture: Hub - kToken locked/released via kOFTAdapter (total supply preserved)");

        console2.log("");
        console2.log("=== Next Steps ===");
        console2.log("1. Deploy kToken + kOFT on spoke chains using DeploySpoke.s.sol");
        console2.log("2. Configure peers between kOFTAdapter (hub) and kOFT (spokes)");
        console2.log("3. Users must approve kOFTAdapter to spend their kTokens before bridging");
    }
}
