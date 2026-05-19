# Audit Scope - kOFT Cross-Chain System

## Overview

This document defines the scope for the security audit of the kOFT cross-chain token system. The audit focuses on three contracts that enable LayerZero-based cross-chain transfers for the KAM protocol's kToken.

**Solidity Version:** 0.8.30  
**Framework:** LayerZero V2 OFT Standard

---

## In-Scope Contracts

### 1. kToken.sol

- **Lines of Code:** 35
- **Purpose:** Cross-chain enabled ERC-20 token for satellite chains
- **Inheritance:** `kToken`, `IERC7802`, `IERC165`
- **File Location:** `contracts/kToken.sol`

### 2. kOFT.sol

- **Lines of Code:** 63
- **Purpose:** LayerZero OFT implementation for satellite chains (burn-and-mint)
- **Inheritance:** `OFTCoreUpgradeable`
- **File Location:** `contracts/kOFT.sol`

### 3. kOFTAdapter.sol

- **Lines of Code:** 11
- **Purpose:** LayerZero OFT adapter for mainnet (lock-and-release)
- **Inheritance:** `OFTAdapterUpgradeable`
- **File Location:** `contracts/kOFTAdapter.sol`

**Total In-Scope Lines of Code:** 109 (excluding interfaces and comments)

---

## Out-of-Scope Contracts

### kToken.sol

- **Status:** Will be audited on the KAM repo.
- **Reason for Exclusion:** Base token contract already security reviewed
- **Note:** kToken inherits from kToken, but only the new cross-chain functionality in kToken is in scope

### LayerZero Dependencies

The following LayerZero contracts are **OUT OF SCOPE** (assumed secure):

- `OFTCoreUpgradeable.sol`
- `OFTAdapterUpgradeable.sol`
- `OAppUpgradeable.sol`
- `MessagingFee.sol`
- `SendParam.sol`
- LayerZero endpoint contracts
- LayerZero messaging libraries

**Rationale:** These are battle-tested LayerZero V2 contracts with independent audits.

### Solady Dependencies

The following Solady library contracts are **OUT OF SCOPE**:

- `OptimizedOwnableRoles.sol`
- `ERC20.sol`
- `Multicallable.sol`
- `ReentrancyGuard.sol`
- `SafeTransferLib.sol`

**Rationale:** Well-audited, production-grade libraries from Solady.

---

## Architecture Context

### System Design

The kOFT system uses a **hybrid architecture**:

1. **Mainnet (Ethereum):**
   - Original `kToken` (ERC-20) - **OUT OF SCOPE**
   - `kOFTAdapter` locks/releases tokens - **IN SCOPE**
   - Pattern: Lock-and-release

2. **Satellite Chains (Arbitrum, Optimism, etc.):**
   - `kToken` with native cross-chain functions - **IN SCOPE**
   - `kOFT` handles burn-and-mint operations - **IN SCOPE**
   - Pattern: Burn-and-mint

### Key Flows to Audit

```
1. Mainnet → Satellite:
   User → kToken.approve() → kOFTAdapter.send() 
   → Lock tokens → LayerZero → kOFT.lzReceive() 
   → kToken.crosschainMint()

2. Satellite → Mainnet:
   User → kOFT.send() → kToken.crosschainBurn() 
   → LayerZero → kOFTAdapter.lzReceive() 
   → Release locked tokens

3. Satellite ↔ Satellite:
   User → kOFT_A.send() → kToken_A.crosschainBurn() 
   → LayerZero → kOFT_B.lzReceive() 
   → kToken_B.crosschainMint()
```

## Specific Functions to Audit

### kToken.sol

#### Critical Functions

```solidity
✓ crosschainMint(address _to, uint256 _amount)
✓ crosschainBurn(address _from, uint256 _amount)
✓ constructor(...)
✓ supportsInterface(bytes4 interfaceId)
```

**Focus Areas:**

- Access control on mint/burn
- Reentrancy protection
- Event emissions
- Integration with inherited kToken functions

### kOFT.sol

#### Critical Functions

```solidity
✓ constructor(address lzEndpoint_, kToken token0_)
✓ initialize(address delegate_)
✓ _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
✓ _credit(address _to, uint256 _amountLD, uint32 _srcEid)
```

#### Important Functions

```solidity
○ approvalRequired()
○ token()
○ buildMsgAndOptions(SendParam calldata _sendParam, uint256 _amountToCreditLD)
```

**Focus Areas:**

- Burn before send in `_debit()`
- Mint on receive in `_credit()`
- Zero address handling in `_credit()`
- Amount calculations (sent vs received)
- Integration with kToken's crosschain functions

---

### kOFTAdapter.sol

#### Critical Functions

```solidity
✓ constructor(address _token, address _lzEndpoint)
✓ initialize(address _delegate)
```

**Focus Areas:**

- Initialization safety
- Token custody (locked balance)
- Integration with kToken (standard ERC-20)
- Inherited functions from `OFTAdapterUpgradeable` (use of transferFrom/transfer)

**Note:** Most functionality is in the parent `OFTAdapterUpgradeable`, which is out of scope. Focus on the initialization and deployment configuration.

## Reference Materials

### Documentation

- [architecture.md](./architecture.md) - System architecture and design
- [interfaces.md](./interfaces.md) - Complete interface documentation
- Previous kToken audit report - [Link if available]

### External References

- [LayerZero V2 Docs](https://docs.layerzero.network/)
- [OFT Standard](https://docs.layerzero.network/v2/developers/evm/oft/quickstart)
- [ERC-7802 Specification](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-7802.md)
- [Solady Repository](https://github.com/Vectorized/solady)

---

## Conclusion

This audit focuses on three critical contracts that enable cross-chain functionality for kToken:

1. **kToken** - Cross-chain enabled token on satellites
2. **kOFT** - Burn-and-mint OFT implementation
3. **kOFTAdapter** - Lock-and-release adapter for mainnet

The primary security concerns are:

- ✓ Supply invariant conservation
- ✓ Access control enforcement (MINTER_ROLE)
- ✓ Reentrancy protection
- ✓ LayerZero integration correctness
- ✓ Initialization and upgrade safety

**Total Lines of Code:** 109 LOC (excluding interfaces and comments)  

We look forward to working with the audit team to ensure the highest security standards for this cross-chain system. LFG!!