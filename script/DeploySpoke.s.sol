// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { kOFT } from "../src/kOFT.sol";
import { kToken } from "../src/kToken.sol";

import { DeploymentManager } from "./DeploymentManager.s.sol";
import { console2 } from "forge-std/Script.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

/// @title DeploySpoke
/// @notice Deploys kToken + kOFT for spoke chain deployment
/// @dev Spoke deployment is identical to hub - both use kOFT for burn/mint since kToken supports ERC7802.
/// The only difference is conceptual: hub is where the "canonical" version lives (e.g., mainnet with KAM).
///
/// Architecture:
/// - kToken: The ERC20 token with crosschain mint/burn capabilities (ERC7802)
/// - kOFT: LayerZero OFT that calls kToken.crosschainBurn on send and kToken.crosschainMint on receive
/// - kOFT receives MINTER_ROLE on kToken to perform crosschain operations
contract DeploySpoke is DeploymentManager {
    kToken public token;
    kOFT public koft;

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

        // Step 1: Deploy kToken via proxy with deployer as temporary minter
        console2.log("=== Deploying kToken (Spoke) ===");
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

        // Step 2: Deploy kOFT (Spoke uses kOFT for burning/minting)
        console2.log("=== Deploying kOFT (Spoke) ===");
        kOFT implementation = new kOFT(config.layerZero.lzEndpoint, token);
        bytes memory data = abi.encodeCall(kOFT.initialize, (config.roles.delegate, config.roles.owner));
        address proxy = proxyFactory.deployAndCall(address(implementation), data);
        koft = kOFT(proxy);
        console2.log("kOFT implementation:", address(implementation));
        console2.log("kOFT proxy deployed at:", address(koft));

        // Step 3: Grant kOFT the MINTER_ROLE on kToken
        console2.log("=== Granting MINTER_ROLE to kOFT ===");
        token.grantMinterRole(address(koft));
        console2.log("kOFT granted MINTER_ROLE on kToken");

        // Step 4: Remove MINTER_ROLE from deployer for security
        try token.revokeMinterRole(msg.sender) {
            console2.log("Removed MINTER_ROLE from deployer");
        } catch {
            console2.log("Deployer did not have MINTER_ROLE or revocation failed");
        }

        // Write all deployment addresses
        writeContractAddress("kToken", address(token));
        writeContractAddress("kTokenImplementation", address(tokenImplementation));
        writeContractAddress("kOFT", address(koft));
        writeContractAddress("kOFTImplementation", address(implementation));

        // Summary
        console2.log("=== Spoke Deployment Summary ===");
        console2.log("Network: Spoke Chain");
        console2.log("kToken:", address(token));
        console2.log("kOFT:", address(koft));
        console2.log("LayerZero Endpoint:", config.layerZero.lzEndpoint);
        console2.log("LayerZero EID:", config.layerZero.lzEid);
        console2.log("Delegate:", config.roles.delegate);
        console2.log("Owner:", config.roles.owner);
        console2.log("Admin:", config.roles.admin);
        console2.log("Emergency Admin:", config.roles.emergencyAdmin);
        console2.log("Architecture: Spoke - Tokens burned/minted via kOFT");

        vm.stopBroadcast();
    }
}
