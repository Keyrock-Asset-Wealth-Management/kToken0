// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import { Script } from "forge-std/Script.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";

/// @title DeploymentManager
/// @notice Utility for managing JSON-based deployment configurations and outputs for kToken project
/// @dev Handles reading network configs and writing deployment addresses for multichain deployments
///
/// Directory Structure:
/// deployments/
/// ├── config/
/// │   ├── mainnet.json     (hub config)
/// │   ├── arbitrum.json    (spoke config)
/// │   └── ...
/// └── output/
///     ├── mainnet/
///     │   └── addresses.json
///     ├── arbitrum/
///     │   └── addresses.json
///     └── ...
abstract contract DeploymentManager is Script {
    using stdJson for string;

    /* //////////////////////////////////////////////////////////////
                            CONFIG STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct NetworkConfig {
        string network;
        uint256 chainId;
        string deploymentType; // "hub" or "spoke"
        address existingKToken; // For deployments with existing kToken
        RoleAddresses roles;
        LayerZeroConfig layerZero;
    }

    struct RoleAddresses {
        address owner;
        address admin;
        address emergencyAdmin;
        address delegate;
    }

    struct LayerZeroConfig {
        address lzEndpoint;
        uint32 lzEid;
    }

    struct KTokenConfig {
        string name;
        string symbol;
        uint8 decimals;
    }

    /* //////////////////////////////////////////////////////////////
                            OUTPUT STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct DeploymentOutput {
        uint256 chainId;
        string network;
        string deploymentType;
        uint256 timestamp;
        ContractAddresses contracts;
        PeerAddresses peers;
    }

    struct ContractAddresses {
        address kToken;
        address kTokenImplementation;
        address kOFT;
        address kOFTImplementation;
        address kOFTAdapter;
        address kOFTAdapterImplementation;
    }

    struct PeerAddresses {
        address mainnet;
        address arbitrum;
        address optimism;
        address base;
        address polygon;
    }

    /* //////////////////////////////////////////////////////////////
                            NETWORK HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the current network name from foundry context
    function getCurrentNetwork() internal view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) return "mainnet";
        if (chainId == 11_155_111) return "sepolia";
        if (chainId == 421_614) return "arbitrum-sepolia";
        if (chainId == 11_155_420) return "optimism-sepolia";
        if (chainId == 31_337) return "localhost";
        if (chainId == 137) return "polygon";
        if (chainId == 42_161) return "arbitrum";
        if (chainId == 10) return "optimism";
        if (chainId == 8453) return "base";
        if (chainId == 56) return "bsc";
        if (chainId == 250) return "fantom";
        if (chainId == 43_114) return "avalanche";

        return "localhost";
    }

    function isProduction() internal view returns (bool) {
        return vm.envOr("PRODUCTION", false);
    }

    function isHub(NetworkConfig memory config) internal pure returns (bool) {
        return keccak256(bytes(config.deploymentType)) == keccak256(bytes("hub"));
    }

    /* //////////////////////////////////////////////////////////////
                            CONFIG READING
    //////////////////////////////////////////////////////////////*/

    /// @notice Reads network configuration from JSON file
    function readNetworkConfig() internal view returns (NetworkConfig memory config) {
        string memory network = getCurrentNetwork();
        string memory configPath = string.concat("deployments/config/", network, ".json");

        require(vm.exists(configPath), string.concat("Config file not found: ", configPath));

        string memory json = vm.readFile(configPath);

        config.network = json.readString(".network");
        config.chainId = json.readUint(".chainId");
        config.deploymentType = json.readString(".deploymentType");

        // Read existing kToken if specified
        if (json.keyExists(".existingKToken")) {
            config.existingKToken = json.readAddress(".existingKToken");
        }

        // Parse role addresses
        config.roles.owner = json.readAddress(".roles.owner");
        config.roles.admin = json.readAddress(".roles.admin");
        config.roles.emergencyAdmin = json.readAddress(".roles.emergencyAdmin");
        config.roles.delegate = json.readAddress(".roles.delegate");

        // Parse LayerZero config
        config.layerZero.lzEndpoint = json.readAddress(".layerZero.lzEndpoint");
        config.layerZero.lzEid = uint32(json.readUint(".layerZero.lzEid"));

        return config;
    }

    /// @notice Reads kToken configuration for a specific token (e.g., "kUSD", "kBTC")
    function readKTokenConfig(string memory tokenKey) internal view returns (KTokenConfig memory config) {
        string memory network = getCurrentNetwork();
        string memory configPath = string.concat("deployments/config/", network, ".json");
        string memory json = vm.readFile(configPath);

        string memory basePath = string.concat(".kTokens.", tokenKey);

        config.name = json.readString(string.concat(basePath, ".name"));
        config.symbol = json.readString(string.concat(basePath, ".symbol"));
        config.decimals = uint8(json.readUint(string.concat(basePath, ".decimals")));

        return config;
    }

    /* //////////////////////////////////////////////////////////////
                            OUTPUT READING
    //////////////////////////////////////////////////////////////*/

    /// @notice Reads existing deployment addresses from output JSON
    function readDeploymentOutput() internal view returns (DeploymentOutput memory output) {
        string memory network = getCurrentNetwork();
        string memory outputPath = string.concat("deployments/output/", network, "/addresses.json");

        if (!vm.exists(outputPath)) {
            output.network = network;
            output.chainId = block.chainid;
            return output;
        }

        string memory json = vm.readFile(outputPath);

        output.chainId = json.readUint(".chainId");
        output.network = json.readString(".network");
        output.timestamp = json.readUint(".timestamp");

        if (json.keyExists(".deploymentType")) {
            output.deploymentType = json.readString(".deploymentType");
        }

        // Parse contract addresses
        if (json.keyExists(".contracts.kToken")) {
            output.contracts.kToken = json.readAddress(".contracts.kToken");
        }
        if (json.keyExists(".contracts.kTokenImplementation")) {
            output.contracts.kTokenImplementation = json.readAddress(".contracts.kTokenImplementation");
        }
        if (json.keyExists(".contracts.kOFT")) {
            output.contracts.kOFT = json.readAddress(".contracts.kOFT");
        }
        if (json.keyExists(".contracts.kOFTImplementation")) {
            output.contracts.kOFTImplementation = json.readAddress(".contracts.kOFTImplementation");
        }
        if (json.keyExists(".contracts.kOFTAdapter")) {
            output.contracts.kOFTAdapter = json.readAddress(".contracts.kOFTAdapter");
        }
        if (json.keyExists(".contracts.kOFTAdapterImplementation")) {
            output.contracts.kOFTAdapterImplementation = json.readAddress(".contracts.kOFTAdapterImplementation");
        }

        // Parse peer addresses
        if (json.keyExists(".peers.mainnet")) {
            output.peers.mainnet = json.readAddress(".peers.mainnet");
        }
        if (json.keyExists(".peers.arbitrum")) {
            output.peers.arbitrum = json.readAddress(".peers.arbitrum");
        }
        if (json.keyExists(".peers.optimism")) {
            output.peers.optimism = json.readAddress(".peers.optimism");
        }
        if (json.keyExists(".peers.base")) {
            output.peers.base = json.readAddress(".peers.base");
        }
        if (json.keyExists(".peers.polygon")) {
            output.peers.polygon = json.readAddress(".peers.polygon");
        }

        return output;
    }

    /// @notice Reads deployment output from a specific network
    function readDeploymentOutputForNetwork(string memory network)
        internal
        view
        returns (DeploymentOutput memory output)
    {
        string memory outputPath = string.concat("deployments/output/", network, "/addresses.json");

        if (!vm.exists(outputPath)) {
            output.network = network;
            return output;
        }

        string memory json = vm.readFile(outputPath);

        output.chainId = json.readUint(".chainId");
        output.network = json.readString(".network");

        if (json.keyExists(".contracts.kOFT")) {
            output.contracts.kOFT = json.readAddress(".contracts.kOFT");
        }
        if (json.keyExists(".contracts.kOFTAdapter")) {
            output.contracts.kOFTAdapter = json.readAddress(".contracts.kOFTAdapter");
        }

        return output;
    }

    /* //////////////////////////////////////////////////////////////
                            OUTPUT WRITING
    //////////////////////////////////////////////////////////////*/

    /// @notice Writes a single contract address to deployment output
    function writeContractAddress(string memory contractName, address contractAddress) internal {
        string memory network = getCurrentNetwork();
        string memory outputPath = string.concat("deployments/output/", network, "/addresses.json");

        DeploymentOutput memory output = readDeploymentOutput();
        output.chainId = block.chainid;
        output.network = network;
        output.timestamp = block.timestamp;

        // Read deployment type from config
        NetworkConfig memory config = readNetworkConfig();
        output.deploymentType = config.deploymentType;

        // Update the specific contract address
        if (keccak256(bytes(contractName)) == keccak256(bytes("kToken"))) {
            output.contracts.kToken = contractAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("kTokenImplementation"))) {
            output.contracts.kTokenImplementation = contractAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("kOFT"))) {
            output.contracts.kOFT = contractAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("kOFTImplementation"))) {
            output.contracts.kOFTImplementation = contractAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("kOFTAdapter"))) {
            output.contracts.kOFTAdapter = contractAddress;
        } else if (keccak256(bytes(contractName)) == keccak256(bytes("kOFTAdapterImplementation"))) {
            output.contracts.kOFTAdapterImplementation = contractAddress;
        }

        string memory json = _serializeDeploymentOutput(output);
        vm.writeFile(outputPath, json);

        console.log(string.concat(contractName, " address written to: "), outputPath);
    }

    /// @notice Writes a peer address to deployment output
    function writePeerAddress(string memory peerNetwork, address peerAddress) internal {
        string memory network = getCurrentNetwork();
        string memory outputPath = string.concat("deployments/output/", network, "/addresses.json");

        DeploymentOutput memory output = readDeploymentOutput();
        output.chainId = block.chainid;
        output.network = network;
        output.timestamp = block.timestamp;

        if (keccak256(bytes(peerNetwork)) == keccak256(bytes("mainnet"))) {
            output.peers.mainnet = peerAddress;
        } else if (keccak256(bytes(peerNetwork)) == keccak256(bytes("arbitrum"))) {
            output.peers.arbitrum = peerAddress;
        } else if (keccak256(bytes(peerNetwork)) == keccak256(bytes("optimism"))) {
            output.peers.optimism = peerAddress;
        } else if (keccak256(bytes(peerNetwork)) == keccak256(bytes("base"))) {
            output.peers.base = peerAddress;
        } else if (keccak256(bytes(peerNetwork)) == keccak256(bytes("polygon"))) {
            output.peers.polygon = peerAddress;
        }

        string memory json = _serializeDeploymentOutput(output);
        vm.writeFile(outputPath, json);

        console.log(string.concat("Peer ", peerNetwork, " written to: "), outputPath);
    }

    /* //////////////////////////////////////////////////////////////
                            SERIALIZATION
    //////////////////////////////////////////////////////////////*/

    function _serializeDeploymentOutput(DeploymentOutput memory output) private pure returns (string memory) {
        string memory json = "{\n";
        json = string.concat(json, '  "chainId": ', vm.toString(output.chainId), ",\n");
        json = string.concat(json, '  "network": "', output.network, '",\n');
        json = string.concat(json, '  "deploymentType": "', output.deploymentType, '",\n');
        json = string.concat(json, '  "timestamp": ', vm.toString(output.timestamp), ",\n");

        // Contracts
        json = string.concat(json, '  "contracts": {\n');
        json = string.concat(json, '    "kToken": "', vm.toString(output.contracts.kToken), '",\n');
        json = string.concat(
            json, '    "kTokenImplementation": "', vm.toString(output.contracts.kTokenImplementation), '",\n'
        );
        json = string.concat(json, '    "kOFT": "', vm.toString(output.contracts.kOFT), '",\n');
        json = string.concat(
            json, '    "kOFTImplementation": "', vm.toString(output.contracts.kOFTImplementation), '",\n'
        );
        json = string.concat(json, '    "kOFTAdapter": "', vm.toString(output.contracts.kOFTAdapter), '",\n');
        json = string.concat(
            json, '    "kOFTAdapterImplementation": "', vm.toString(output.contracts.kOFTAdapterImplementation), '"\n'
        );
        json = string.concat(json, "  },\n");

        // Peers
        json = string.concat(json, '  "peers": {\n');
        json = string.concat(json, '    "mainnet": "', vm.toString(output.peers.mainnet), '",\n');
        json = string.concat(json, '    "arbitrum": "', vm.toString(output.peers.arbitrum), '",\n');
        json = string.concat(json, '    "optimism": "', vm.toString(output.peers.optimism), '",\n');
        json = string.concat(json, '    "base": "', vm.toString(output.peers.base), '",\n');
        json = string.concat(json, '    "polygon": "', vm.toString(output.peers.polygon), '"\n');
        json = string.concat(json, "  }\n");

        json = string.concat(json, "}");

        return json;
    }

    /* //////////////////////////////////////////////////////////////
                            VALIDATION
    //////////////////////////////////////////////////////////////*/

    function validateConfig(NetworkConfig memory config) internal pure {
        require(config.roles.owner != address(0), "Missing owner address");
        require(config.roles.admin != address(0), "Missing admin address");
        require(config.roles.emergencyAdmin != address(0), "Missing emergencyAdmin address");
        require(config.roles.delegate != address(0), "Missing delegate address");
        require(config.layerZero.lzEndpoint != address(0), "Missing LayerZero endpoint address");
        require(config.layerZero.lzEid != 0, "Missing LayerZero EID");
    }

    function validateKTokenDeployment(DeploymentOutput memory existing) internal pure {
        require(existing.contracts.kToken != address(0), "kToken not deployed");
    }

    function validateKOFTDeployment(DeploymentOutput memory existing) internal pure {
        require(existing.contracts.kOFT != address(0), "kOFT not deployed");
    }

    function validateOFTAdapterDeployment(DeploymentOutput memory existing) internal pure {
        require(existing.contracts.kOFTAdapter != address(0), "kOFTAdapter not deployed");
    }

    /* //////////////////////////////////////////////////////////////
                            LOGGING
    //////////////////////////////////////////////////////////////*/

    function logConfig(NetworkConfig memory config) internal pure {
        console.log("=== DEPLOYMENT CONFIGURATION ===");
        console.log("Network:", config.network);
        console.log("Chain ID:", config.chainId);
        console.log("Deployment Type:", config.deploymentType);
        console.log("Owner:", config.roles.owner);
        console.log("Admin:", config.roles.admin);
        console.log("Emergency Admin:", config.roles.emergencyAdmin);
        console.log("Delegate:", config.roles.delegate);
        console.log("LayerZero Endpoint:", config.layerZero.lzEndpoint);
        console.log("LayerZero EID:", config.layerZero.lzEid);
        if (config.existingKToken != address(0)) {
            console.log("Existing kToken:", config.existingKToken);
        }
        console.log("================================");
    }

    function logDeployment(DeploymentOutput memory output) internal pure {
        console.log("=== DEPLOYMENT OUTPUT ===");
        console.log("Network:", output.network);
        console.log("Chain ID:", output.chainId);
        console.log("Type:", output.deploymentType);
        console.log("Timestamp:", output.timestamp);
        console.log("--- Contracts ---");
        console.log("kToken:", output.contracts.kToken);
        console.log("kToken Impl:", output.contracts.kTokenImplementation);
        console.log("kOFT:", output.contracts.kOFT);
        console.log("kOFT Impl:", output.contracts.kOFTImplementation);
        console.log("kOFTAdapter:", output.contracts.kOFTAdapter);
        console.log("kOFTAdapter Impl:", output.contracts.kOFTAdapterImplementation);
        console.log("--- Peers ---");
        console.log("Mainnet:", output.peers.mainnet);
        console.log("Arbitrum:", output.peers.arbitrum);
        console.log("Optimism:", output.peers.optimism);
        console.log("Base:", output.peers.base);
        console.log("Polygon:", output.peers.polygon);
        console.log("=========================");
    }
}
