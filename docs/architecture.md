# kOFT Architecture Documentation

## Overview

The kOFT (kToken Omnichain Fungible Token) system is a LayerZero-based cross-chain token infrastructure that enables the KAM protocol's kTokens to operate seamlessly across multiple blockchain networks. This implementation uses a **hybrid lock-and-mint + burn-and-mint architecture** where the mainnet acts as the canonical source of truth with locked tokens, while satellite chains use a burn-and-mint model for inter-chain transfers.

## System Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                  MAINNET (Canonical Chain)                  │
│                                                             │
│  ┌──────────────┐      ┌──────────────────┐                 │
│  │   kToken     │◄─────│  kOFTAdapter     │                 │
│  │ (Original    │      │  (Lock & Release)│                 │
│  │  ERC-20)     │      │                  │                 │
│  └──────────────┘      └────────-┬────────┘                 │
│                                  │                          │
└──────────────────────────────────┼──────────────────────────┘
                                   │
                       ┌───────────▼───────────┐
                       │  LayerZero Network    │
                       └───────────┬───────────┘
                ┌──────────────────┴──────────────────┐
                │                                     │
┌───────────────▼─────────────────┐  ┌───────────────▼─────────────────┐
│      Chain B (Satellite)        │  │      Chain C (Satellite)        │
│                                 │  │                                 │
│  ┌──────────────┐  ┌─────────┐  │  │  ┌──────────────┐  ┌─────────┐  │
│  │   kToken0    │◄─│  kOFT   │◄-┼──┼─►│   kToken0    │◄─│  kOFT   │  │
│  │ (ERC-20 +    │  │ (Burn & │  │  │  │ (ERC-20 +    │  │ (Burn & │  │
│  │  ERC-7802)   │  │  Mint)  │  │  │  │  ERC-7802)   │  │  Mint)  │  │
│  └──────────────┘  └─────────┘  │  │  └──────────────┘  └─────────┘  │
│                                 │  │                                 │
└─────────────────────────────────┘  └─────────────────────────────────┘
```

### Architecture Principles

1. **Mainnet as Source of Truth**: The original kToken on mainnet holds the canonical total supply
2. **Lock-and-Mint Pattern**: Tokens transferred from mainnet are locked in kOFTAdapter, synthetic tokens minted on destination
3. **Burn-and-Mint Pattern**: Transfers between satellite chains burn tokens on source and mint on destination
4. **Supply Conservation**: Global supply = Mainnet supply = Locked in adapter + Sum of all satellite chain supplies

## Core Components

### 1. kToken (Mainnet Only)

**Purpose**: Original ERC-20 token on mainnet representing 1:1 backed assets in the KAM protocol

**Key Features**:

- Standard ERC-20 implementation with KAM protocol extensions
- Role-based access control (ADMIN, EMERGENCY_ADMIN, MINTER roles)
- Emergency pause mechanism
- **Cannot be modified** to add cross-chain functions (hence the adapter pattern)

**Characteristics**:

- Immutable or upgrade-restricted contract
- Holds the canonical total supply
- Only exists on mainnet
- Interacts with kOFTAdapter via standard ERC-20 `transferFrom`/`transfer`

### 2. kOFTAdapter (Mainnet Only)

**Purpose**: LayerZero adapter that locks mainnet kTokens and coordinates cross-chain transfers

**Inheritance**: `OFTAdapterUpgradeable` (LayerZero upgradeable adapter)

**Architecture Pattern**: **Lock-and-Release**

- **Outbound (Mainnet → Satellite)**: Locks kToken in adapter, mints kToken0 on destination
- **Inbound (Satellite → Mainnet)**: Burns kToken0 on source, releases locked kToken on mainnet

**Key Components**:

#### Constructor

```solidity
constructor(address _token, address _lzEndpoint)
```

- `_token`: Address of the mainnet kToken contract
- `_lzEndpoint`: LayerZero endpoint on mainnet
- Disables initializers for upgrade safety

#### Initialization

```solidity
function initialize(address _delegate, address _owner) external initializer
```

- `_delegate`: LayerZero delegate — configures send/receive libraries, DVNs,
  executor options, enforced options, and trusted peers. Can be rotated later
  via `setDelegate` (owner-gated).
- `_owner`: Contract owner — holds UUPS upgrade authority and `setDelegate`
  authority. Separating delegate from owner lets LayerZero infrastructure
  management and contract upgrades be held by distinct keys.
- Both addresses must be non-zero; reverts with `ZeroAddress()` otherwise.
- One-time initialization after deployment.

#### Internal Mechanics

**Token Custody**:

- Users approve kOFTAdapter to spend their kTokens
- Adapter uses `transferFrom` to lock tokens during outbound transfers
- Locked tokens remain in adapter contract
- Adapter uses `transfer` to release tokens during inbound transfers

**LayerZero Integration**:

- Inherits all OFT messaging from `OFTAdapterUpgradeable`
- Handles message encoding/decoding
- Manages cross-chain fee calculations
- Coordinates with endpoint for security

### 3. kToken0 (Satellite Chains Only)

**Purpose**: Cross-chain enabled ERC-20 token with native burn/mint capabilities

**Key Features**:

- **ERC-20 Standard**: Full compliance with ERC-20 token standard
- **ERC-7802 Interface**: Native `crosschainMint` and `crosschainBurn` functions
- **Role-Based Access Control**: Four-tier role system
  - `ADMIN_ROLE`: Manages minters, emergency admins, and blacklist admins
  - `EMERGENCY_ADMIN_ROLE`: Handles pause/emergency operations
  - `MINTER_ROLE`: Authorized to mint/burn tokens (kOFT contract has this role)
  - `BLACKLIST_ADMIN_ROLE`: Authorized to freeze/unfreeze accounts
- **Purpose-Built**: Designed from the ground up for cross-chain operations
- **Reentrancy Protection**: All critical functions protected

**Cross-Chain Functions**:

```solidity
function crosschainMint(address _to, uint256 _amount) external nonReentrant onlyRoles(MINTER_ROLE)
function crosschainBurn(address _from, uint256 _amount) external nonReentrant onlyRoles(MINTER_ROLE)
```

**Freeze/Blacklist Functions** (USDC-style compliance):

```solidity
function freezeAccount(address _account) external onlyRoles(BLACKLIST_ADMIN_ROLE)
function unfreezeAccount(address _account) external onlyRoles(BLACKLIST_ADMIN_ROLE)
function isFrozen(address _account) external view returns (bool)
```

The freeze mechanism blocks all token movements (transfers, mints, burns) for frozen addresses. This enables compliance with regulatory requirements and security incident response.

**Why Different from Mainnet kToken?**

- Built with cross-chain functionality from inception
- Can be called by kOFT without requiring approval
- Implements ERC-7802 standard for cross-chain semantics
- Lightweight for efficient satellite chain deployment

### 4. kOFT (Satellite Chains Only)

**Purpose**: LayerZero OFT implementation enabling burn-and-mint transfers between satellite chains

**Inheritance**: `OFTCoreUpgradeable` (LayerZero upgradeable OFT core)

**Architecture Pattern**: **Burn-and-Mint**

- **Outbound**: Burns kToken0 on source satellite chain
- **Inbound**: Mints kToken0 on destination satellite chain
- **Can also communicate with mainnet** via kOFTAdapter (burns kToken0, adapter releases locked kToken)

**Key Components**:

#### Constructor

```solidity
constructor(address lzEndpoint_, kToken0 kToken0_)
```

- Stores immutable reference to kToken0
- Sets up LayerZero endpoint connection
- Inherits token decimals from kToken0
- Disables initializers for upgrade safety

#### Initialization

```solidity
function initialize(address _delegate, address _owner) external initializer
```

- `_delegate`: LayerZero delegate — configures send/receive libraries, DVNs,
  executor options, enforced options, and trusted peers. Can be rotated later
  via `setDelegate` (owner-gated).
- `_owner`: Contract owner — holds UUPS upgrade authority and `setDelegate`
  authority. Separating delegate from owner lets LayerZero infrastructure
  management and contract upgrades be held by distinct keys.
- Both addresses must be non-zero; reverts with `ZeroAddress()` otherwise.
- One-time initialization after deployment.

#### Core Internal Functions

**`_debit` (Source Chain)**:

```solidity
function _debit(
    address _from,
    uint256 _amountLD,
    uint256 _minAmountLD,
    uint32 _dstEid
) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD)
```

- Called when tokens leave the source satellite chain
- Burns tokens via `token0.crosschainBurn(_from, amountSentLD)`
- Returns amounts for LayerZero message construction
- Handles potential fee calculations (amountSent vs amountReceived)

**`_credit` (Destination Chain)**:

```solidity
function _credit(
    address _to,
    uint256 _amountLD,
    uint32 _srcEid
) internal virtual override returns (uint256 amountReceivedLD)
```

- Called when tokens arrive on destination satellite chain
- Handles zero-address edge case (redirects to burn address)
- Mints tokens via `token0.crosschainMint(_to, _amountLD)`
- Can receive from other satellites OR from mainnet adapter

#### View Functions

**`token()`**: Returns kToken0 address (OFT standard compliance)

**`approvalRequired()`**: Returns `false` (no approval needed, kOFT has MINTER_ROLE)

**`buildMsgAndOptions()`**: Helper for constructing LayerZero messages

## Cross-Chain Transfer Flows

### Flow 1: Mainnet → Satellite Chain (Lock-and-Mint)

```
User (Mainnet)
    │
    ├─► 1. Approves kOFTAdapter to spend kToken
    │
    ├─► 2. Calls kOFTAdapter.send() with destination details
    │
    ▼
kOFTAdapter (Mainnet)
    │
    ├─► 3. Calls kToken.transferFrom(user, adapter, amount)
    │
    ▼
kToken (Mainnet)
    │
    ├─► 4. Transfers tokens to adapter (LOCKED)
    │
    ▼
kOFTAdapter (Mainnet)
    │
    ├─► 5. Encodes LayerZero message with recipient & amount
    │
    ▼
LayerZero Network
    │
    ├─► 6. Cross-chain message transmission
    │
    ▼
kOFT (Satellite Chain)
    │
    ├─► 7. Receives message, calls _credit()
    │
    ├─► 8. Calls token0.crosschainMint(recipient, amount)
    │
    ▼
kToken0 (Satellite Chain)
    │
    └─► 9. Mints tokens to recipient (NEW SUPPLY on satellite)
```

**Supply Impact**: 

- Mainnet: Tokens locked in adapter (supply unchanged, but circulating supply decreased)
- Satellite: New tokens minted (supply increased)
- Global: Total supply conserved (locked + satellite supplies = mainnet supply)

### Flow 2: Satellite Chain → Mainnet (Burn-and-Release)

```
User (Satellite Chain)
    │
    ├─► 1. Calls kOFT.send() with mainnet destination
    │
    ▼
kOFT (Satellite Chain)
    │
    ├─► 2. Calls _debit()
    │
    ├─► 3. Calls token0.crosschainBurn(user, amount)
    │
    ▼
kToken0 (Satellite Chain)
    │
    ├─► 4. Burns tokens from user (DESTROYED on satellite)
    │
    ▼
kOFT (Satellite Chain)
    │
    ├─► 5. Encodes LayerZero message
    │
    ▼
LayerZero Network
    │
    ├─► 6. Cross-chain message transmission
    │
    ▼
kOFTAdapter (Mainnet)
    │
    ├─► 7. Receives message, processes _credit()
    │
    ├─► 8. Calls kToken.transfer(recipient, amount)
    │
    ▼
kToken (Mainnet)
    │
    └─► 9. Releases locked tokens to recipient
```

**Supply Impact**:

- Satellite: Tokens burned (supply decreased)
- Mainnet: Tokens released from adapter (circulating supply increased, total unchanged)
- Global: Total supply conserved

### Flow 3: Satellite Chain A → Satellite Chain B (Burn-and-Mint)

```
User (Chain A)
    │
    ├─► 1. Calls kOFT_A.send() with Chain B destination
    │
    ▼
kOFT (Chain A)
    │
    ├─► 2. Calls _debit()
    │
    ├─► 3. Calls token0.crosschainBurn(user, amount)
    │
    ▼
kToken0 (Chain A)
    │
    ├─► 4. Burns tokens from user (DESTROYED)
    │
    ▼
LayerZero Network
    │
    ├─► 5. Cross-chain message transmission
    │
    ▼
kOFT (Chain B)
    │
    ├─► 6. Receives message, calls _credit()
    │
    ├─► 7. Calls token0.crosschainMint(recipient, amount)
    │
    ▼
kToken0 (Chain B)
    │
    └─► 8. Mints tokens to recipient (CREATED)
```

**Supply Impact**:

- Chain A: Tokens burned (supply decreased)
- Chain B: Tokens minted (supply increased)
- Global: Total supply conserved (sum across all chains constant)

## Security Architecture

### Access Control Model

#### Mainnet:

```
Owner (UUPS upgrade + setDelegate authority)
    │
    └─► kOFTAdapter
            │  initialized with (delegate, owner) — two distinct keys
            │
            ├─► LayerZero Delegate (cross-chain messaging config: libs,
            │   DVNs, executors; rotatable via setDelegate)
            │
            └─► Has approval to transfer kToken from users
```

#### Satellite Chains:

```
Owner (kRegistry/Governance)
    │
    ├─► Can grant/revoke ADMIN_ROLE on kToken0
    │
    ▼
ADMIN_ROLE (kToken0)
    │
    ├─► Can grant/revoke EMERGENCY_ADMIN_ROLE
    ├─► Can grant/revoke MINTER_ROLE
    ├─► Can grant/revoke BLACKLIST_ADMIN_ROLE
    │
    ▼
EMERGENCY_ADMIN_ROLE    MINTER_ROLE (kOFT)    BLACKLIST_ADMIN_ROLE
    │                        │                      │
    ├─► Emergency pause      ├─► crosschainMint()   ├─► freezeAccount()
    ├─► Emergency withdraw   └─► crosschainBurn()   └─► unfreezeAccount()
    └─► Protocol safety ops
```

### Security Features

#### Mainnet (kOFTAdapter):

1. **Token Custody**: Locked tokens held in adapter contract
2. **Standard ERC-20 Security**: Uses battle-tested transferFrom pattern
3. **LayerZero Security**: Inherits OFT adapter security guarantees
4. **Upgrade Safety**: Initializer disabled after first use
5. **Peer Validation**: Only accepts messages from trusted remote OFTs

#### Satellite Chains (kOFT + kToken0):

1. **Immutable References**: kOFT holds immutable reference to kToken0
2. **Role Segregation**: Only kOFT can mint/burn (MINTER_ROLE)
3. **Reentrancy Protection**: All crosschain functions protected
4. **Pause Mechanism**: Emergency circuit breaker for all operations
5. **Zero Address Protection**: Redirects to burn address, prevents lock-up
6. **Peer Validation**: Only accepts messages from trusted remotes
7. **Upgrade Safety**: Initializers disabled after deployment
8. **Freeze/Blacklist Mechanism**: USDC-style account freezing for compliance

#### Freeze/Blacklist Security Model:

The freeze mechanism provides USDC-style compliance capabilities:

1. **Blocked Operations for Frozen Accounts**:
   - Cannot send tokens (transfer, transferFrom)
   - Cannot receive tokens (transfer, transferFrom, mint)
   - Cannot be minted to (crosschainMint blocked)
   - Cannot be burned from (crosschainBurn blocked)
   - Funds remain locked until unfrozen

2. **Protection Rules**:
   - Owner address cannot be frozen
   - `address(0)` cannot be frozen (mint/burn sentinel)
   - Only `BLACKLIST_ADMIN_ROLE` can freeze/unfreeze

3. **Crosschain Considerations**:
   - Freeze status is checked in `_beforeTokenTransfer` hook
   - All crosschain operations (via kOFT) respect freeze status
   - Frozen accounts cannot participate in any crosschain transfers

### Supply Invariants

The system maintains critical supply invariants:

```
INVARIANT 1: Global Conservation
Total Supply on Mainnet = 
    Locked in kOFTAdapter + 
    Sum(All kToken0 supplies on satellite chains)

INVARIANT 2: Mainnet Supply
kToken.totalSupply() = constant (unless protocol mints/burns)

INVARIANT 3: Satellite Supply
Each kToken0.totalSupply() fluctuates with cross-chain transfers

INVARIANT 4: Locked Balance
kOFTAdapter balance = 
    Sum(All tokens ever sent from mainnet) - 
    Sum(All tokens ever returned to mainnet)
```

## Deployment Architecture

### Deployment Sequence

#### Phase 1: Mainnet Deployment

```
1. kToken already exists (original protocol token)
2. Deploy kOFTAdapter(kToken address, mainnet LZ endpoint)
3. Initialize kOFTAdapter with (delegate, owner) — two distinct addresses
   from deployments/config/<network>.json (roles.delegate, roles.owner)
4. Users must approve kOFTAdapter to spend kToken
```

#### Phase 2: Satellite Chain Deployment (for each chain)

```
1. Deploy kToken0(owner, admin, emergencyAdmin, address(0), name, symbol, decimals)
   - Note: Pass address(0) for kOFT initially

2. Deploy kOFT(satellite LZ endpoint, kToken0 address)

3. Initialize kOFT with (delegate, owner) — two distinct addresses
   from deployments/config/<network>.json (roles.delegate, roles.owner)

4. Grant MINTER_ROLE to kOFT:
   kToken0.grantMinterRole(kOFT address)

5. Configure LayerZero peers on kOFT:
   - Set trusted remote for mainnet kOFTAdapter
   - Set trusted remotes for other satellite kOFTs

6. Configure LayerZero peers on mainnet kOFTAdapter:
   - Set trusted remote for this satellite's kOFT
```

#### Phase 3: LayerZero Configuration (for each chain)

```
1. Set DVN (Decentralized Verifier Networks):
   - Configure security stack
   - Set required/optional DVNs
   - Define confirmation thresholds

2. Set Executor configuration:
   - Gas limits for destination chains
   - Executor addresses
   - Fee parameters

3. Configure send/receive libraries:
   - Set appropriate library versions
   - Configure ulnConfig parameters
```

### Multi-Chain Deployment Topology

```
                    ┌─────────────────────┐
                    │   MAINNET (ETH)     │
                    │                     │
                    │   kToken (locked)   │
                    │   kOFTAdapter       │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
    ┌─────▼─────┐       ┌─────▼─────┐       ┌─────▼─────┐
    │ Arbitrum  │       │ Optimism  │       │ Polygon   │
    │           │       │           │       │           │
    │ kToken0   │◄─────►│ kToken0   │◄─────►│ kToken0   │
    │ kOFT      │       │ kOFT      │       │ kOFT      │
    └───────────┘       └───────────┘       └───────────┘
```

**Key Points**:

- Mainnet acts as hub but is not required for satellite-to-satellite transfers
- Each satellite can communicate directly with others (peer-to-peer)
- LayerZero mesh network enables efficient routing

## ERC-7802 Integration

**Standard**: [ERC-7802 - Crosschain Token Interface](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-7802.md)

**Implementation** (kToken0 only):

```solidity
interface IERC7802 {
    event CrosschainMint(address indexed to, uint256 amount, address indexed sender);
    event CrosschainBurn(address indexed from, uint256 amount, address indexed sender);
    
    function crosschainMint(address _to, uint256 _amount) external;
    function crosschainBurn(address _from, uint256 _amount) external;
}
```

**Why Only on Satellites?**

- Mainnet kToken is legacy and doesn't need this interface
- kOFTAdapter handles cross-chain ops without modifying kToken
- Satellite kToken0s are purpose-built with ERC-7802 from the start

**Benefits**:

- Standardized cross-chain semantics across satellite chains
- Clear event trail for off-chain indexing
- Interoperability with other ERC-7802 systems
- Future-proof design for cross-chain ecosystem

## Testing Considerations

### Critical Test Scenarios

#### Mainnet ↔ Satellite Tests:

1. **Mainnet → Satellite**:
   - Approve and send kToken from mainnet
   - Verify lock in kOFTAdapter
   - Verify mint on satellite
   - Check adapter balance increases

2. **Satellite → Mainnet**:
   - Send kToken0 from satellite to mainnet
   - Verify burn on satellite
   - Verify release from adapter on mainnet
   - Check adapter balance decreases

3. **Round Trip**:
   - Mainnet → Satellite → Mainnet
   - Verify user gets same amount back
   - Verify adapter balance returns to original

#### Satellite ↔ Satellite Tests:

1. **Chain A → Chain B**:
   - Send from satellite A
   - Verify burn on chain A
   - Verify mint on chain B
   - Check total supplies adjust correctly

2. **Triangle Transfer**:
   - Chain A → Chain B → Chain C → Chain A
   - Verify supply conservation

#### Supply Invariant Tests:

1. **Global Supply Conservation**:
   - Track mainnet locked balance
   - Sum all satellite supplies
   - Verify equals mainnet total supply

2. **Adapter Balance**:
   - Verify adapter balance = tokens sent - tokens returned

#### Security Tests:

1. **Access Control**:
   - Unauthorized mint/burn attempts on kToken0
   - Unauthorized adapter operations
   - Role management operations

2. **Pause Mechanism**:
   - Pause on satellite, attempt transfers
   - Pause during cross-chain transfer
   - Resume and retry

3. **Edge Cases**:
   - Zero address handling
   - Maximum amount transfers
   - Insufficient balance scenarios
   - Failed cross-chain message handling

4. **Reentrancy**:
   - Attempt reentrancy during crosschainMint
   - Attempt reentrancy during crosschainBurn

5. **Peer Trust**:
   - Untrusted source chain messages
   - Replay attack attempts
   - Invalid peer configurations

## References

- [LayerZero V2 Documentation](https://docs.layerzero.network/)
- [OFT Standard](https://docs.layerzero.network/v2/developers/evm/oft/quickstart)
- [OFT Adapter Pattern](https://docs.layerzero.network/v2/developers/evm/oft/adapter)
- [ERC-7802 Specification](https://github.com/ethereum/ERCs/blob/master/ERCS/erc-7802.md)
- [Solady Library](https://github.com/Vectorized/solady)

## Conclusion

The kOFT architecture employs a sophisticated **hybrid approach** that optimally leverages the strengths of different LayerZero patterns:

- **Mainnet**: Uses **kOFTAdapter** with lock-and-release to preserve the original kToken while enabling cross-chain functionality
- **Satellites**: Use **kOFT + kToken0** with burn-and-mint for efficient, purpose-built cross-chain transfers

This design maintains the protocol's core 1:1 backing guarantees while enabling seamless multi-chain operations. The mainnet remains the canonical source of truth with locked tokens, while satellite chains provide flexible, gas-efficient cross-chain transfers through native burn/mint capabilities. The implementation of ERC-7802 on satellite chains ensures standardized cross-chain semantics and future interoperability.