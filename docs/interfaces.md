# kOFT Interfaces Documentation

## Overview

This document provides comprehensive interface documentation for all contracts in the kOFT cross-chain token system. It covers both user-facing functions and internal/admin operations, with detailed parameter descriptions, return values, access control requirements, and usage examples.

---

## Table of Contents

1. [kToken (Mainnet)](#1-ktoken-mainnet)
2. [kOFTAdapter (Mainnet)](#2-koftadapter-mainnet)
3. [kToken (Satellite Chains)](#3-ktoken0-satellite-chains)
4. [kOFT (Satellite Chains)](#4-koft-satellite-chains)
5. [IERC7802 Interface](#5-ierc7802-interface)

---

## 1. kToken (Mainnet)

The original ERC-20 token on mainnet. Users interact with standard ERC-20 functions plus KAM protocol extensions.

### Standard ERC-20 Functions

#### `name()`
```solidity
function name() external view returns (string memory)
```
Returns the name of the token.

**Returns:**
- `string`: Token name (e.g., "KAM USDC")

---

#### `symbol()`
```solidity
function symbol() external view returns (string memory)
```
Returns the token symbol.

**Returns:**
- `string`: Token symbol (e.g., "kUSDC")

---

#### `decimals()`
```solidity
function decimals() external view returns (uint8)
```
Returns the number of decimals.

**Returns:**
- `uint8`: Decimal places (typically 6 or 18)

---

#### `totalSupply()`
```solidity
function totalSupply() external view returns (uint256)
```
Returns the total token supply on mainnet (canonical supply).

**Returns:**
- `uint256`: Total supply in base units

---

#### `balanceOf(address account)`
```solidity
function balanceOf(address account) external view returns (uint256)
```
Returns the token balance of an account.

**Parameters:**
- `account`: Address to query

**Returns:**
- `uint256`: Balance in base units

---

#### `transfer(address to, uint256 amount)`
```solidity
function transfer(address to, uint256 amount) external returns (bool)
```
Transfers tokens to another address.

**Parameters:**
- `to`: Recipient address
- `amount`: Amount to transfer

**Returns:**
- `bool`: Success status

**Emits:**
- `Transfer(address indexed from, address indexed to, uint256 value)`

---

#### `approve(address spender, uint256 amount)`
```solidity
function approve(address spender, uint256 amount) external returns (bool)
```
Approves spender to transfer tokens on behalf of caller.

**Parameters:**
- `spender`: Address authorized to spend (e.g., kOFTAdapter)
- `amount`: Maximum amount to approve

**Returns:**
- `bool`: Success status

**Emits:**
- `Approval(address indexed owner, address indexed spender, uint256 value)`

**Usage Example:**
```solidity
// Before sending tokens cross-chain, approve kOFTAdapter
kToken.approve(kOFTAdapterAddress, 1000e6); // Approve 1000 USDC
```

---

#### `transferFrom(address from, address to, uint256 amount)`
```solidity
function transferFrom(address from, address to, uint256 amount) external returns (bool)
```
Transfers tokens from one address to another using allowance.

**Parameters:**
- `from`: Source address
- `to`: Destination address
- `amount`: Amount to transfer

**Returns:**
- `bool`: Success status

**Emits:**
- `Transfer(address indexed from, address indexed to, uint256 value)`

---

#### `allowance(address owner, address spender)`
```solidity
function allowance(address owner, address spender) external view returns (uint256)
```
Returns the remaining allowance.

**Parameters:**
- `owner`: Token owner address
- `spender`: Spender address

**Returns:**
- `uint256`: Remaining allowance

---

### KAM Protocol Functions

#### `mint(address to, uint256 amount)`
```solidity
function mint(address to, uint256 amount) external nonReentrant onlyRoles(MINTER_ROLE)
```
Mints new tokens (protocol operation).

**Access Control:** `MINTER_ROLE` only

**Parameters:**
- `to`: Recipient address
- `amount`: Amount to mint

**Emits:**
- `Minted(address indexed to, uint256 amount)`

---

#### `burn(address from, uint256 amount)`
```solidity
function burn(address from, uint256 amount) external nonReentrant onlyRoles(MINTER_ROLE)
```
Burns tokens (protocol operation).

**Access Control:** `MINTER_ROLE` only

**Parameters:**
- `from`: Address to burn from
- `amount`: Amount to burn

**Emits:**
- `Burned(address indexed from, uint256 amount)`

---

#### `isPaused()`
```solidity
function isPaused() external view returns (bool)
```
Returns whether the contract is paused.

**Returns:**
- `bool`: Pause state

---

### Admin Functions

#### `grantMinterRole(address minter)`
```solidity
function grantMinterRole(address minter) external onlyRoles(ADMIN_ROLE)
```
Grants minter role to an address.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `minter`: Address to grant role

---

#### `revokeMinterRole(address minter)`
```solidity
function revokeMinterRole(address minter) external onlyRoles(ADMIN_ROLE)
```
Revokes minter role from an address.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `minter`: Address to revoke role from

---

#### `setPaused(bool isPaused)`
```solidity
function setPaused(bool isPaused) external onlyRoles(EMERGENCY_ADMIN_ROLE)
```
Sets the pause state (emergency use).

**Access Control:** `EMERGENCY_ADMIN_ROLE` only

**Parameters:**
- `isPaused`: New pause state

**Emits:**
- `PauseState(bool isPaused)`

---

### Freeze/Blacklist Functions

#### `freeze(address account)`
```solidity
function freeze(address account) external onlyRoles(BLACKLIST_ADMIN_ROLE)
```
Freezes an account, blocking all transfers to and from it (USDC-style compliance).

**Access Control:** `BLACKLIST_ADMIN_ROLE` only

**Parameters:**
- `account`: Address to freeze

**Emits:**
- `AccountFrozen(address indexed account, address indexed by)`

**Restrictions:**
- Cannot freeze the owner address
- Cannot freeze `address(0)`

---

#### `unfreeze(address account)`
```solidity
function unfreeze(address account) external onlyRoles(BLACKLIST_ADMIN_ROLE)
```
Unfreezes an account, restoring transfer capability.

**Access Control:** `BLACKLIST_ADMIN_ROLE` only

**Parameters:**
- `account`: Address to unfreeze

**Emits:**
- `AccountUnfrozen(address indexed account, address indexed by)`

---

#### `isFrozen(address account)`
```solidity
function isFrozen(address account) external view returns (bool)
```
Checks if an account is frozen.

**Parameters:**
- `account`: Address to check

**Returns:**
- `bool`: True if the account is frozen

---

#### `grantBlacklistAdminRole(address admin)`
```solidity
function grantBlacklistAdminRole(address admin) external onlyRoles(ADMIN_ROLE)
```
Grants blacklist admin role to an address.

**Access Control:** `ADMIN_ROLE` only

---

#### `revokeBlacklistAdminRole(address admin)`
```solidity
function revokeBlacklistAdminRole(address admin) external onlyRoles(ADMIN_ROLE)
```
Revokes blacklist admin role from an address.

**Access Control:** `ADMIN_ROLE` only

---

## 2. kOFTAdapter (Mainnet)

LayerZero adapter for locking mainnet kTokens and enabling cross-chain transfers.

### Core User Functions

#### `send(SendParam calldata sendParam, MessagingFee calldata fee, address refundAddress)`
```solidity
function send(
    SendParam calldata sendParam,
    MessagingFee calldata fee,
    address refundAddress
) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
```
Sends tokens cross-chain from mainnet to a satellite chain.

**Parameters:**
- `sendParam`: Send parameters struct
  - `uint32 dstEid`: Destination endpoint ID (chain ID)
  - `bytes32 to`: Recipient address (bytes32 format)
  - `uint256 amountLD`: Amount to send (local decimals)
  - `uint256 minAmountLD`: Minimum amount to receive
  - `bytes extraOptions`: Additional options (gas settings)
  - `bytes composeMsg`: Compose message (usually empty)
  - `bytes oftCmd`: OFT command (usually empty)
- `fee`: Messaging fee struct
  - `uint256 nativeFee`: Native gas fee for cross-chain message
  - `uint256 lzTokenFee`: LZ token fee (usually 0)
- `refundAddress`: Address to receive excess gas refund

**Returns:**
- `msgReceipt`: Messaging receipt with guid and nonce
- `oftReceipt`: OFT receipt with amount sent and received

**Emits:**
- `OFTSent(bytes32 indexed guid, uint32 dstEid, address indexed from, uint256 amountSentLD, uint256 amountReceivedLD)`

**Usage Example:**
```solidity
// 1. Approve kOFTAdapter to spend kToken
kToken.approve(address(kOFTAdapter), 1000e6);

// 2. Prepare send parameters
SendParam memory sendParam = SendParam({
    dstEid: 42161, // Arbitrum
    to: bytes32(uint256(uint160(recipientAddress))),
    amountLD: 1000e6,
    minAmountLD: 995e6, // Allow 0.5% slippage
    extraOptions: "", // Use default gas settings
    composeMsg: "",
    oftCmd: ""
});

// 3. Get quote for cross-chain fee
MessagingFee memory fee = kOFTAdapter.quoteSend(sendParam, false);

// 4. Send tokens
kOFTAdapter.send{value: fee.nativeFee}(sendParam, fee, msg.sender);
```

---

#### `quoteSend(SendParam calldata sendParam, bool payInLzToken)`
```solidity
function quoteSend(
    SendParam calldata sendParam,
    bool payInLzToken
) external view returns (MessagingFee memory fee)
```
Quotes the fee for a cross-chain send operation.

**Parameters:**
- `sendParam`: Send parameters (same structure as `send()`)
- `payInLzToken`: Whether to pay fee in LZ token (usually false)

**Returns:**
- `fee`: Estimated fees
  - `uint256 nativeFee`: Native gas fee required
  - `uint256 lzTokenFee`: LZ token fee (if applicable)

**Usage Example:**
```solidity
SendParam memory sendParam = SendParam({
    dstEid: 10, // Optimism
    to: bytes32(uint256(uint160(recipient))),
    amountLD: 500e18,
    minAmountLD: 495e18,
    extraOptions: "",
    composeMsg: "",
    oftCmd: ""
});

MessagingFee memory fee = kOFTAdapter.quoteSend(sendParam, false);
// fee.nativeFee contains required ETH for cross-chain message
```

---

### View Functions

#### `token()`
```solidity
function token() external view returns (address)
```
Returns the address of the underlying kToken.

**Returns:**
- `address`: kToken contract address

---

#### `approvalRequired()`
```solidity
function approvalRequired() external view returns (bool)
```
Returns whether approval is required before sending (always true for adapter).

**Returns:**
- `bool`: `true` (adapter requires approval)

---

#### `balanceOf(address account)`
```solidity
function balanceOf(address account) external view returns (uint256)
```
Returns the balance of locked tokens in the adapter (not individual user balances).

**Parameters:**
- `account`: Address to query (usually the adapter itself)

**Returns:**
- `uint256`: Locked token balance

---

### Configuration Functions

#### `setPeer(uint32 eid, bytes32 peer)`
```solidity
function setPeer(uint32 eid, bytes32 peer) external onlyOwner
```
Sets a trusted peer OFT on another chain.

**Access Control:** Owner only

**Parameters:**
- `eid`: Endpoint ID of the remote chain
- `peer`: Address of the remote kOFT (bytes32 format)

**Usage Example:**
```solidity
// Set Arbitrum kOFT as trusted peer
bytes32 arbitrumKOFT = bytes32(uint256(uint160(arbitrumKOFTAddress)));
kOFTAdapter.setPeer(42161, arbitrumKOFT);
```

---

#### `setEnforcedOptions(EnforcedOptionParam[] calldata params)`
```solidity
function setEnforcedOptions(EnforcedOptionParam[] calldata params) external onlyOwner
```
Sets enforced options for specific routes.

**Access Control:** Owner only

**Parameters:**
- `params`: Array of enforced option parameters
  - `uint32 eid`: Endpoint ID
  - `uint16 msgType`: Message type
  - `bytes options`: Enforced options

---

## 3. kToken (Satellite Chains)

Cross-chain enabled ERC-20 token with native mint/burn capabilities on satellite chains.

### Standard ERC-20 Functions

#### `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf()`, `transfer()`, `approve()`, `transferFrom()`, `allowance()`

See [kToken Standard ERC-20 Functions](#standard-erc-20-functions) - kToken implements the same interface.

---

### ERC-7802 Cross-Chain Functions

#### `crosschainMint(address to, uint256 amount)`
```solidity
function crosschainMint(address to, uint256 amount) external nonReentrant onlyRoles(MINTER_ROLE)
```
Mints tokens as part of a cross-chain transfer (called by kOFT only).

**Access Control:** `MINTER_ROLE` only (kOFT contract)

**Parameters:**
- `to`: Recipient address
- `amount`: Amount to mint

**Emits:**
- `Minted(address indexed to, uint256 amount)`
- `CrosschainMint(address indexed to, uint256 amount, address indexed sender)`

**Note:** Users never call this directly. kOFT calls it when receiving cross-chain transfers.

---

#### `crosschainBurn(address from, uint256 amount)`
```solidity
function crosschainBurn(address from, uint256 amount) external nonReentrant onlyRoles(MINTER_ROLE)
```
Burns tokens as part of a cross-chain transfer (called by kOFT only).

**Access Control:** `MINTER_ROLE` only (kOFT contract)

**Parameters:**
- `from`: Address to burn from
- `amount`: Amount to burn

**Emits:**
- `Burned(address indexed from, uint256 amount)`
- `CrosschainBurn(address indexed from, uint256 amount, address indexed sender)`

**Note:** Users never call this directly. kOFT calls it when sending cross-chain transfers.

---

### View Functions

#### `supportsInterface(bytes4 interfaceId)`
```solidity
function supportsInterface(bytes4 interfaceId) external pure returns (bool)
```
Checks if contract supports an interface (ERC-165).

**Parameters:**
- `interfaceId`: Interface identifier

**Returns:**
- `bool`: True if interface is supported

**Supported Interfaces:**
- `type(IERC7802).interfaceId`: 0x7b24b3a3
- `type(IERC165).interfaceId`: 0x01ffc9a7

---

#### `isPaused()`
```solidity
function isPaused() external view returns (bool)
```
Returns whether the contract is paused.

**Returns:**
- `bool`: Pause state

---

### Admin Functions

#### `grantMinterRole(address minter)`
```solidity
function grantMinterRole(address minter) external onlyRoles(ADMIN_ROLE)
```
Grants minter role (typically to kOFT contract).

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `minter`: Address to grant role (should be kOFT address)

**Usage Example:**
```solidity
// After deploying kOFT, grant it minter role
kToken.grantMinterRole(address(kOFT));
```

---

#### `revokeMinterRole(address minter)`
```solidity
function revokeMinterRole(address minter) external onlyRoles(ADMIN_ROLE)
```
Revokes minter role from an address.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `minter`: Address to revoke role from

---

#### `grantAdminRole(address admin)`
```solidity
function grantAdminRole(address admin) external onlyOwner
```
Grants admin role to an address.

**Access Control:** Owner only

**Parameters:**
- `admin`: Address to grant admin role

---

#### `revokeAdminRole(address admin)`
```solidity
function revokeAdminRole(address admin) external onlyOwner
```
Revokes admin role from an address.

**Access Control:** Owner only

**Parameters:**
- `admin`: Address to revoke admin role from

---

#### `grantEmergencyRole(address emergency)`
```solidity
function grantEmergencyRole(address emergency) external onlyRoles(ADMIN_ROLE)
```
Grants emergency admin role.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `emergency`: Address to grant emergency role

---

#### `revokeEmergencyRole(address emergency)`
```solidity
function revokeEmergencyRole(address emergency) external onlyRoles(ADMIN_ROLE)
```
Revokes emergency admin role.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `emergency`: Address to revoke emergency role from

---

#### `setPaused(bool isPaused)`
```solidity
function setPaused(bool isPaused) external onlyRoles(EMERGENCY_ADMIN_ROLE)
```
Sets the pause state (emergency use).

**Access Control:** `EMERGENCY_ADMIN_ROLE` only

**Parameters:**
- `isPaused`: New pause state

**Emits:**
- `PauseState(bool isPaused)`

---

#### `emergencyWithdraw(address token, address to, uint256 amount)`
```solidity
function emergencyWithdraw(address token, address to, uint256 amount) external onlyRoles(EMERGENCY_ADMIN_ROLE)
```
Emergency recovery of accidentally sent tokens.

**Access Control:** `EMERGENCY_ADMIN_ROLE` only

**Parameters:**
- `token`: Token address (address(0) for ETH)
- `to`: Recipient address
- `amount`: Amount to recover

**Emits:**
- `EmergencyWithdrawal(address indexed token, address indexed to, uint256 amount, address indexed admin)`
- `RescuedAssets(address indexed asset, address indexed to, uint256 amount)` OR
- `RescuedETH(address indexed asset, uint256 amount)`

---

### Freeze/Blacklist Functions

#### `freeze(address account)`
```solidity
function freeze(address account) external onlyRoles(BLACKLIST_ADMIN_ROLE)
```
Freezes an account, blocking all transfers to and from it.

**Access Control:** `BLACKLIST_ADMIN_ROLE` only

**Parameters:**
- `account`: Address to freeze (cannot be `address(0)` or owner)

**Emits:**
- `AccountFrozen(address indexed account, address indexed by)`

**Restrictions:**
- Cannot freeze the owner address
- Cannot freeze `address(0)`

**Usage Example:**
```solidity
// Freeze a suspicious account
kToken.freeze(suspiciousAddress);
```

---

#### `unfreeze(address account)`
```solidity
function unfreeze(address account) external onlyRoles(BLACKLIST_ADMIN_ROLE)
```
Unfreezes an account, restoring transfer capability.

**Access Control:** `BLACKLIST_ADMIN_ROLE` only

**Parameters:**
- `account`: Address to unfreeze

**Emits:**
- `AccountUnfrozen(address indexed account, address indexed by)`

**Usage Example:**
```solidity
// Unfreeze an account after resolution
kToken.unfreeze(resolvedAddress);
```

---

#### `isFrozen(address account)`
```solidity
function isFrozen(address account) external view returns (bool)
```
Checks if an account is frozen.

**Parameters:**
- `account`: Address to check

**Returns:**
- `bool`: True if the account is frozen, false otherwise

**Usage Example:**
```solidity
if (kToken.isFrozen(userAddress)) {
    // Handle frozen account case
}
```

---

#### `grantBlacklistAdminRole(address admin)`
```solidity
function grantBlacklistAdminRole(address admin) external onlyRoles(ADMIN_ROLE)
```
Grants blacklist admin role to an address.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `admin`: Address to grant blacklist admin role

**Usage Example:**
```solidity
// Grant blacklist admin role to compliance team
kToken.grantBlacklistAdminRole(complianceTeamAddress);
```

---

#### `revokeBlacklistAdminRole(address admin)`
```solidity
function revokeBlacklistAdminRole(address admin) external onlyRoles(ADMIN_ROLE)
```
Revokes blacklist admin role from an address.

**Access Control:** `ADMIN_ROLE` only

**Parameters:**
- `admin`: Address to revoke blacklist admin role from

---

## 4. kOFT (Satellite Chains)

LayerZero OFT implementation for burn-and-mint cross-chain transfers on satellite chains.

### Core User Functions

#### `send(SendParam calldata sendParam, MessagingFee calldata fee, address refundAddress)`
```solidity
function send(
    SendParam calldata sendParam,
    MessagingFee calldata fee,
    address refundAddress
) external payable returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt)
```
Sends tokens cross-chain from satellite to another chain (satellite or mainnet).

**Parameters:**
- `sendParam`: Send parameters struct
  - `uint32 dstEid`: Destination endpoint ID
  - `bytes32 to`: Recipient address (bytes32 format)
  - `uint256 amountLD`: Amount to send (local decimals)
  - `uint256 minAmountLD`: Minimum amount to receive
  - `bytes extraOptions`: Additional options
  - `bytes composeMsg`: Compose message (usually empty)
  - `bytes oftCmd`: OFT command (usually empty)
- `fee`: Messaging fee struct
  - `uint256 nativeFee`: Native gas fee
  - `uint256 lzTokenFee`: LZ token fee
- `refundAddress`: Address for gas refund

**Returns:**
- `msgReceipt`: Messaging receipt
- `oftReceipt`: OFT receipt

**Emits:**
- `OFTSent(bytes32 indexed guid, uint32 dstEid, address indexed from, uint256 amountSentLD, uint256 amountReceivedLD)`

**Usage Example:**
```solidity
// Send from Arbitrum to Optimism (no approval needed)
SendParam memory sendParam = SendParam({
    dstEid: 10, // Optimism
    to: bytes32(uint256(uint160(recipientAddress))),
    amountLD: 1000e6,
    minAmountLD: 995e6,
    extraOptions: "",
    composeMsg: "",
    oftCmd: ""
});

MessagingFee memory fee = kOFT.quoteSend(sendParam, false);
kOFT.send{value: fee.nativeFee}(sendParam, fee, msg.sender);
```

---

#### `quoteSend(SendParam calldata sendParam, bool payInLzToken)`
```solidity
function quoteSend(
    SendParam calldata sendParam,
    bool payInLzToken
) external view returns (MessagingFee memory fee)
```
Quotes the fee for a cross-chain send operation.

**Parameters:**
- `sendParam`: Send parameters
- `payInLzToken`: Whether to pay in LZ token

**Returns:**
- `fee`: Estimated fees

---

### View Functions

#### `token()`
```solidity
function token() external view returns (address)
```
Returns the address of kToken.

**Returns:**
- `address`: kToken contract address

---

#### `approvalRequired()`
```solidity
function approvalRequired() external pure returns (bool)
```
Returns whether approval is required (always false for kOFT).

**Returns:**
- `bool`: `false` (kOFT has MINTER_ROLE, no approval needed)

---

#### `buildMsgAndOptions(SendParam calldata sendParam, uint256 amountToCreditLD)`
```solidity
function buildMsgAndOptions(
    SendParam calldata sendParam,
    uint256 amountToCreditLD
) external view returns (bytes memory message, bytes memory options)
```
Helper function to build LayerZero message and options.

**Parameters:**
- `sendParam`: Send parameters
- `amountToCreditLD`: Amount to credit on destination

**Returns:**
- `message`: Encoded message bytes
- `options`: Encoded options bytes

**Usage:** Useful for off-chain simulation or advanced integrations.

---

### Configuration Functions

#### `setPeer(uint32 eid, bytes32 peer)`
```solidity
function setPeer(uint32 eid, bytes32 peer) external onlyOwner
```
Sets a trusted peer OFT/Adapter on another chain.

**Access Control:** Owner only

**Parameters:**
- `eid`: Endpoint ID of the remote chain
- `peer`: Address of the remote kOFT or kOFTAdapter

**Usage Example:**
```solidity
// On Arbitrum kOFT, set Optimism kOFT as peer
bytes32 optimismKOFT = bytes32(uint256(uint160(optimismKOFTAddress)));
kOFT.setPeer(10, optimismKOFT);

// Also set mainnet kOFTAdapter as peer
bytes32 mainnetAdapter = bytes32(uint256(uint160(mainnetAdapterAddress)));
kOFT.setPeer(1, mainnetAdapter);
```

---

#### `setEnforcedOptions(EnforcedOptionParam[] calldata params)`
```solidity
function setEnforcedOptions(EnforcedOptionParam[] calldata params) external onlyOwner
```
Sets enforced options for specific routes.

**Access Control:** Owner only

**Parameters:**
- `params`: Array of enforced option parameters

---

## 5. IERC7802 Interface

Standard interface for cross-chain token operations implemented by kToken.

### Functions

#### `crosschainMint(address to, uint256 amount)`
```solidity
function crosschainMint(address to, uint256 amount) external
```
Mints tokens through a cross-chain transfer.

**Parameters:**
- `to`: Address to mint tokens to
- `amount`: Amount to mint

**Emits:**
- `CrosschainMint(address indexed to, uint256 amount, address indexed sender)`

---

#### `crosschainBurn(address from, uint256 amount)`
```solidity
function crosschainBurn(address from, uint256 amount) external
```
Burns tokens through a cross-chain transfer.

**Parameters:**
- `from`: Address to burn tokens from
- `amount`: Amount to burn

**Emits:**
- `CrosschainBurn(address indexed from, uint256 amount, address indexed sender)`

---

### Events

#### `CrosschainMint`
```solidity
event CrosschainMint(address indexed to, uint256 amount, address indexed sender)
```
Emitted when tokens are minted via cross-chain transfer.

**Parameters:**
- `to`: Recipient of minted tokens
- `amount`: Amount minted
- `sender`: Address that called crosschainMint (kOFT address)

---

#### `CrosschainBurn`
```solidity
event CrosschainBurn(address indexed from, uint256 amount, address indexed sender)
```
Emitted when tokens are burned via cross-chain transfer.

**Parameters:**
- `from`: Address tokens were burned from
- `amount`: Amount burned
- `sender`: Address that called crosschainBurn (kOFT address)