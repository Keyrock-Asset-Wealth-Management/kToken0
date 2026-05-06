// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { kToken } from "../../src/kToken.sol";
import {
    KTOKEN_ACCOUNT_FROZEN,
    KTOKEN_IS_PAUSED,
    KTOKEN_TRANSFER_FAILED,
    KTOKEN_WRONG_ROLE,
    KTOKEN_ZERO_ADDRESS,
    KTOKEN_ZERO_AMOUNT
} from "../../src/errors/Errors.sol";
import { Ownable } from "../../src/vendor/solady/auth/Ownable.sol";
import { ERC20 } from "../../src/vendor/solady/tokens/ERC20.sol";
import { Initializable } from "../../src/vendor/solady/utils/Initializable.sol";
import { Test } from "forge-std/Test.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

/**
 * @title kToken Unit Tests
 * @notice Comprehensive unit tests for kToken contract (unified with ERC7802)
 */
contract kTokenUnitTest is Test {
    kToken public token;

    address public owner = address(0x1001);
    address public admin = address(0x1002);
    address public emergencyAdmin = address(0x1003);
    address public minter = address(0x1004);
    address public blacklistAdmin = address(0x1005);
    address public user1 = address(0x2001);
    address public user2 = address(0x2002);

    string constant NAME = "kUSD Token";
    string constant SYMBOL = "kUSD";
    uint8 constant DECIMALS = 6;

    event CrosschainMint(address indexed to, uint256 amount, address indexed minter);
    event CrosschainBurn(address indexed from, uint256 amount, address indexed minter);
    event PauseState(bool paused);
    event AccountFrozen(address indexed account, address indexed by);
    event AccountUnfrozen(address indexed account, address indexed by);

    function setUp() public {
        // Deploy via UUPS proxy pattern
        MinimalUUPSFactory proxyFactory = new MinimalUUPSFactory();
        kToken implementation = new kToken();
        bytes memory initData =
            abi.encodeCall(kToken.initialize, (owner, admin, emergencyAdmin, minter, NAME, SYMBOL, DECIMALS));
        address proxy = proxyFactory.deployAndCall(address(implementation), initData);
        token = kToken(proxy);

        // Grant blacklist admin role
        vm.prank(admin);
        token.grantBlacklistAdminRole(blacklistAdmin);
    }

    // ============================================
    // INITIALIZATION TESTS
    // ============================================

    function test_Initialize_SetsNameCorrectly() public view {
        assertEq(token.name(), NAME);
    }

    function test_Initialize_SetsSymbolCorrectly() public view {
        assertEq(token.symbol(), SYMBOL);
    }

    function test_Initialize_SetsDecimalsCorrectly() public view {
        assertEq(token.decimals(), DECIMALS);
    }

    function test_Initialize_SetsOwnerCorrectly() public view {
        assertEq(token.owner(), owner);
    }

    function test_Initialize_GrantsAdminRole() public view {
        assertTrue(token.hasAnyRole(admin, token.ADMIN_ROLE()));
    }

    function test_Initialize_GrantsMinterRole() public view {
        assertTrue(token.hasAnyRole(minter, token.MINTER_ROLE()));
    }

    function test_Initialize_InitialSupplyIsZero() public view {
        assertEq(token.totalSupply(), 0);
    }

    function test_Initialize_CannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        token.initialize(owner, admin, emergencyAdmin, minter, NAME, SYMBOL, DECIMALS);
    }

    // ============================================
    // CROSSCHAIN MINT TESTS
    // ============================================

    function test_CrosschainMint_Success() public {
        uint256 amount = 1000e6;

        vm.prank(minter);
        token.crosschainMint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_CrosschainMint_EmitsCrosschainMintEvent() public {
        uint256 amount = 1000e6;

        vm.expectEmit(true, true, false, true);
        emit CrosschainMint(user1, amount, minter);

        vm.prank(minter);
        token.crosschainMint(user1, amount);
    }

    function test_CrosschainMint_RevertsForNonMinter() public {
        uint256 amount = 1000e6;

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.crosschainMint(user1, amount);
    }

    function test_CrosschainMint_RevertsWhenPaused() public {
        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);
    }

    function test_CrosschainMint_MultipleMintsAccumulate() public {
        vm.startPrank(minter);
        token.crosschainMint(user1, 500e6);
        token.crosschainMint(user1, 300e6);
        token.crosschainMint(user1, 200e6);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), 1000e6);
    }

    // ============================================
    // CROSSCHAIN BURN TESTS
    // ============================================

    function test_CrosschainBurn_Success() public {
        uint256 amount = 1000e6;

        // Mint first
        vm.prank(minter);
        token.crosschainMint(user1, amount);

        // Burn
        vm.prank(minter);
        token.crosschainBurn(user1, 400e6);

        assertEq(token.balanceOf(user1), 600e6);
        assertEq(token.totalSupply(), 600e6);
    }

    function test_CrosschainBurn_EmitsCrosschainBurnEvent() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.expectEmit(true, true, false, true);
        emit CrosschainBurn(user1, 400e6, minter);

        vm.prank(minter);
        token.crosschainBurn(user1, 400e6);
    }

    function test_CrosschainBurn_RevertsForNonMinter() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.crosschainBurn(user1, 100e6);
    }

    function test_CrosschainBurn_RevertsWhenPaused() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        vm.prank(minter);
        token.crosschainBurn(user1, 100e6);
    }

    function test_CrosschainBurn_RevertsForInsufficientBalance() public {
        vm.prank(minter);
        token.crosschainMint(user1, 100e6);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        vm.prank(minter);
        token.crosschainBurn(user1, 200e6);
    }

    // ============================================
    // MINT/BURN (NON-CROSSCHAIN) TESTS
    // ============================================

    function test_Mint_Success() public {
        uint256 amount = 1000e6;

        vm.prank(minter);
        token.mint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
    }

    function test_Mint_RevertsForNonMinter() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.mint(user1, 1000e6);
    }

    function test_Burn_Success() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(minter);
        token.burn(user1, 400e6);

        assertEq(token.balanceOf(user1), 600e6);
    }

    function test_BurnFrom_Success() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        // User approves minter to burn on their behalf
        vm.prank(user1);
        token.approve(minter, 500e6);

        vm.prank(minter);
        token.burnFrom(user1, 400e6);

        assertEq(token.balanceOf(user1), 600e6);
        assertEq(token.allowance(user1, minter), 100e6);
    }

    function test_BurnFrom_RevertsForInsufficientAllowance() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(user1);
        token.approve(minter, 100e6);

        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        vm.prank(minter);
        token.burnFrom(user1, 200e6);
    }

    // ============================================
    // ROLE MANAGEMENT TESTS
    // ============================================

    function test_GrantMinterRole_Success() public {
        address newMinter = address(0x999);

        vm.prank(admin);
        token.grantMinterRole(newMinter);

        assertTrue(token.hasAnyRole(newMinter, token.MINTER_ROLE()));
    }

    function test_GrantMinterRole_RevertsForNonAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.grantMinterRole(user1);
    }

    function test_RevokeMinterRole_Success() public {
        vm.prank(admin);
        token.revokeMinterRole(minter);

        assertFalse(token.hasAnyRole(minter, token.MINTER_ROLE()));
    }

    function test_RevokeMinterRole_RevertsForNonAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.revokeMinterRole(minter);
    }

    function test_RevokedMinter_CannotMint() public {
        vm.prank(admin);
        token.revokeMinterRole(minter);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);
    }

    function test_GrantAdminRole_OnlyOwner() public {
        address newAdmin = address(0x888);

        vm.prank(owner);
        token.grantAdminRole(newAdmin);

        assertTrue(token.hasAnyRole(newAdmin, token.ADMIN_ROLE()));
    }

    function test_GrantAdminRole_RevertsForNonOwner() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(admin);
        token.grantAdminRole(user1);
    }

    function test_GrantEmergencyRole_Success() public {
        address newEmergency = address(0x777);

        vm.prank(admin);
        token.grantEmergencyRole(newEmergency);

        assertTrue(token.hasAnyRole(newEmergency, token.EMERGENCY_ADMIN_ROLE()));
    }

    // ============================================
    // PAUSE FUNCTIONALITY TESTS
    // ============================================

    function test_SetPaused_Success() public {
        vm.prank(emergencyAdmin);
        token.setPaused(true);

        assertTrue(token.isPaused());
    }

    function test_SetPaused_EmitsPauseStateEvent() public {
        vm.expectEmit(false, false, false, true);
        emit PauseState(true);

        vm.prank(emergencyAdmin);
        token.setPaused(true);
    }

    function test_SetPaused_RevertsForNonEmergencyAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.setPaused(true);
    }

    function test_SetUnpaused_Success() public {
        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.prank(emergencyAdmin);
        token.setPaused(false);

        assertFalse(token.isPaused());
    }

    function test_Unpause_AllowsMinting() public {
        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.prank(emergencyAdmin);
        token.setPaused(false);

        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        assertEq(token.balanceOf(user1), 1000e6);
    }

    function test_Pause_BlocksTransfers() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        vm.prank(user1);
        token.transfer(user2, 100e6);
    }

    // ============================================
    // ERC20 FUNCTIONALITY TESTS
    // ============================================

    function test_Transfer_Success() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.prank(user1);
        token.transfer(user2, 300e6);

        assertEq(token.balanceOf(user1), 700e6);
        assertEq(token.balanceOf(user2), 300e6);
    }

    function test_Approve_Success() public {
        vm.prank(user1);
        token.approve(user2, 500e6);

        assertEq(token.allowance(user1, user2), 500e6);
    }

    function test_TransferFrom_Success() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.prank(user1);
        token.approve(user2, 500e6);

        vm.prank(user2);
        token.transferFrom(user1, user2, 300e6);

        assertEq(token.balanceOf(user1), 700e6);
        assertEq(token.balanceOf(user2), 300e6);
        assertEq(token.allowance(user1, user2), 200e6);
    }

    // ============================================
    // INTERFACE SUPPORT TESTS
    // ============================================

    function test_SupportsInterface_ERC7802() public view {
        bytes4 interfaceId = type(IERC7802).interfaceId;
        assertTrue(token.supportsInterface(interfaceId));
    }

    function test_SupportsInterface_ERC165() public view {
        bytes4 interfaceId = type(IERC165).interfaceId;
        assertTrue(token.supportsInterface(interfaceId));
    }

    function test_SupportsInterface_InvalidInterface() public view {
        bytes4 invalidId = bytes4(0xffffffff);
        assertFalse(token.supportsInterface(invalidId));
    }

    // ============================================
    // SUPPLY TRACKING TESTS
    // ============================================

    function test_TotalSupply_UpdatesOnMint() public {
        assertEq(token.totalSupply(), 0);

        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        assertEq(token.totalSupply(), 1000e6);
    }

    function test_TotalSupply_UpdatesOnBurn() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.prank(minter);
        token.crosschainBurn(user1, 400e6);

        assertEq(token.totalSupply(), 600e6);
    }

    function test_TotalSupply_EqualsAllBalances() public {
        vm.startPrank(minter);
        token.crosschainMint(user1, 500e6);
        token.crosschainMint(user2, 300e6);
        token.crosschainMint(owner, 200e6);
        vm.stopPrank();

        uint256 totalBalances = token.balanceOf(user1) + token.balanceOf(user2) + token.balanceOf(owner);

        assertEq(token.totalSupply(), totalBalances);
    }

    // ============================================
    // EMERGENCY WITHDRAW TESTS
    // ============================================

    function test_EmergencyWithdraw_ERC20() public {
        // Send some tokens to the kToken contract accidentally
        vm.prank(minter);
        token.mint(address(token), 1000e6);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(emergencyAdmin);
        token.emergencyWithdraw(address(token), user1, 1000e6);

        assertEq(token.balanceOf(user1), balanceBefore + 1000e6);
    }

    function test_EmergencyWithdraw_ETH() public {
        // Send ETH to the token contract
        vm.deal(address(token), 1 ether);

        uint256 balanceBefore = user1.balance;

        vm.prank(emergencyAdmin);
        token.emergencyWithdraw(address(0), user1, 1 ether);

        assertEq(user1.balance, balanceBefore + 1 ether);
    }

    function test_EmergencyWithdraw_RevertsForNonEmergencyAdmin() public {
        vm.deal(address(token), 1 ether);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.emergencyWithdraw(address(0), user1, 1 ether);
    }

    // ============================================
    // DOMAIN SEPARATOR TEST
    // ============================================

    function test_DomainSeparator_Exists() public view {
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0));
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_CrosschainMint(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 1, type(uint96).max);

        vm.prank(minter);
        token.crosschainMint(to, amount);

        assertEq(token.balanceOf(to), amount);
    }

    function testFuzz_CrosschainBurn(address user, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(user != address(0));
        mintAmount = bound(mintAmount, 1, type(uint96).max);
        burnAmount = bound(burnAmount, 1, mintAmount);

        vm.prank(minter);
        token.crosschainMint(user, mintAmount);

        vm.prank(minter);
        token.crosschainBurn(user, burnAmount);

        assertEq(token.balanceOf(user), mintAmount - burnAmount);
    }

    function testFuzz_BurnFrom(address user, uint256 mintAmount, uint256 allowance, uint256 burnAmount) public {
        vm.assume(user != address(0) && user != minter);
        mintAmount = bound(mintAmount, 1, type(uint96).max);
        allowance = bound(allowance, 1, mintAmount);
        burnAmount = bound(burnAmount, 1, allowance);

        vm.prank(minter);
        token.mint(user, mintAmount);

        vm.prank(user);
        token.approve(minter, allowance);

        vm.prank(minter);
        token.burnFrom(user, burnAmount);

        assertEq(token.balanceOf(user), mintAmount - burnAmount);
    }

    // ============================================
    // FREEZE FUNCTIONALITY TESTS
    // ============================================

    function test_FreezeAccount_Success() public {
        vm.expectEmit(true, true, false, true);
        emit AccountFrozen(user1, blacklistAdmin);

        vm.prank(blacklistAdmin);
        token.freeze(user1);

        assertTrue(token.isFrozen(user1));
    }

    function test_UnfreezeAccount_Success() public {
        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectEmit(true, true, false, true);
        emit AccountUnfrozen(user1, blacklistAdmin);

        vm.prank(blacklistAdmin);
        token.unfreeze(user1);

        assertFalse(token.isFrozen(user1));
    }

    function test_FrozenAccount_CannotTransfer() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(user1);
        token.transfer(user2, 100e6);
    }

    function test_FrozenAccount_CannotReceive() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(blacklistAdmin);
        token.freeze(user2);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(user1);
        token.transfer(user2, 100e6);
    }

    function test_FrozenAccount_CannotBeMinted() public {
        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(minter);
        token.mint(user1, 1000e6);
    }

    function test_FrozenAccount_CannotBeBurned() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(minter);
        token.burn(user1, 500e6);
    }

    function test_FreezeAccount_RevertsForNonAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.freeze(user2);
    }

    function test_CannotFreezeZeroAddress() public {
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        vm.prank(blacklistAdmin);
        token.freeze(address(0));
    }

    function test_CannotFreezeOwner() public {
        // freeze() rejects owner with KTOKEN_WRONG_ROLE — owner cannot be blacklisted.
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(blacklistAdmin);
        token.freeze(owner);
    }

    function test_CrosschainMint_RespectsFreeze() public {
        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);
    }

    function test_CrosschainBurn_RespectsFreeze() public {
        vm.prank(minter);
        token.crosschainMint(user1, 1000e6);

        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(minter);
        token.crosschainBurn(user1, 500e6);
    }

    function test_GrantBlacklistAdminRole_Success() public {
        address newBlacklistAdmin = address(0x888);

        vm.prank(admin);
        token.grantBlacklistAdminRole(newBlacklistAdmin);

        assertTrue(token.hasAnyRole(newBlacklistAdmin, token.BLACKLIST_ADMIN_ROLE()));
    }

    function test_GrantBlacklistAdminRole_RevertsForNonAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.grantBlacklistAdminRole(user1);
    }

    function test_RevokeBlacklistAdminRole_Success() public {
        vm.prank(admin);
        token.revokeBlacklistAdminRole(blacklistAdmin);

        assertFalse(token.hasAnyRole(blacklistAdmin, token.BLACKLIST_ADMIN_ROLE()));
    }

    function test_RevokedBlacklistAdmin_CannotFreeze() public {
        vm.prank(admin);
        token.revokeBlacklistAdminRole(blacklistAdmin);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(blacklistAdmin);
        token.freeze(user1);
    }

    function test_TransferFrom_RevertsForFrozenFrom() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(user1);
        token.approve(user2, 500e6);

        vm.prank(blacklistAdmin);
        token.freeze(user1);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(user2);
        token.transferFrom(user1, user2, 100e6);
    }

    function test_TransferFrom_RevertsForFrozenTo() public {
        vm.prank(minter);
        token.mint(user1, 1000e6);

        vm.prank(user1);
        token.approve(user2, 500e6);

        vm.prank(blacklistAdmin);
        token.freeze(user2);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(user2);
        token.transferFrom(user1, user2, 100e6);
    }

    function testFuzz_FreezeAccount(address account) public {
        vm.assume(account != address(0) && account != owner);

        vm.prank(blacklistAdmin);
        token.freeze(account);

        assertTrue(token.isFrozen(account));
    }

    function testFuzz_FrozenAccountCannotTransfer(address account, uint256 amount) public {
        vm.assume(account != address(0) && account != owner && account != address(token));
        amount = bound(amount, 1, type(uint96).max);

        vm.prank(minter);
        token.mint(account, amount);

        vm.prank(blacklistAdmin);
        token.freeze(account);

        vm.expectRevert(bytes(KTOKEN_ACCOUNT_FROZEN));
        vm.prank(account);
        token.transfer(user2, 1);
    }

    // ============================================
    // ROLE REVOCATION TESTS (revokeAdminRole, revokeEmergencyRole)
    // ============================================

    function test_RevokeAdminRole_Success() public {
        vm.prank(owner);
        token.revokeAdminRole(admin);

        assertFalse(token.hasAnyRole(admin, token.ADMIN_ROLE()));
    }

    function test_RevokeAdminRole_RevertsForNonOwner() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(admin);
        token.revokeAdminRole(admin);
    }

    function test_RevokedAdmin_CannotGrantMinterRole() public {
        vm.prank(owner);
        token.revokeAdminRole(admin);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(admin);
        token.grantMinterRole(user1);
    }

    function test_GrantEmergencyRole_RevertsForNonAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.grantEmergencyRole(user1);
    }

    function test_RevokeEmergencyRole_Success() public {
        vm.prank(admin);
        token.revokeEmergencyRole(emergencyAdmin);

        assertFalse(token.hasAnyRole(emergencyAdmin, token.EMERGENCY_ADMIN_ROLE()));
    }

    function test_RevokeEmergencyRole_RevertsForNonAdmin() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.revokeEmergencyRole(emergencyAdmin);
    }

    function test_RevokedEmergencyAdmin_CannotPause() public {
        vm.prank(admin);
        token.revokeEmergencyRole(emergencyAdmin);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(emergencyAdmin);
        token.setPaused(true);
    }

    // ============================================
    // EMERGENCY WITHDRAW INPUT VALIDATION
    // ============================================

    function test_EmergencyWithdraw_RevertsForZeroDestination() public {
        vm.deal(address(token), 1 ether);

        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        vm.prank(emergencyAdmin);
        token.emergencyWithdraw(address(0), address(0), 1 ether);
    }

    function test_EmergencyWithdraw_RevertsForZeroAmount() public {
        vm.deal(address(token), 1 ether);

        vm.expectRevert(bytes(KTOKEN_ZERO_AMOUNT));
        vm.prank(emergencyAdmin);
        token.emergencyWithdraw(address(0), user1, 0);
    }

    function test_EmergencyWithdraw_RevertsWhenETHTransferFails() public {
        // Deploy a contract with no payable receive — sending ETH to it triggers
        // the KTOKEN_TRANSFER_FAILED branch.
        ETHRejector rejector = new ETHRejector();
        vm.deal(address(token), 1 ether);

        vm.expectRevert(bytes(KTOKEN_TRANSFER_FAILED));
        vm.prank(emergencyAdmin);
        token.emergencyWithdraw(address(0), address(rejector), 1 ether);
    }

    // ============================================
    // INITIALIZE ZERO ADDRESS CHECKS
    // ============================================

    function test_Initialize_RevertsForZeroOwner() public {
        MinimalUUPSFactory f = new MinimalUUPSFactory();
        kToken impl = new kToken();
        bytes memory initData = abi.encodeCall(
            kToken.initialize, (address(0), admin, emergencyAdmin, minter, NAME, SYMBOL, DECIMALS)
        );
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        f.deployAndCall(address(impl), initData);
    }

    function test_Initialize_RevertsForZeroAdmin() public {
        MinimalUUPSFactory f = new MinimalUUPSFactory();
        kToken impl = new kToken();
        bytes memory initData = abi.encodeCall(
            kToken.initialize, (owner, address(0), emergencyAdmin, minter, NAME, SYMBOL, DECIMALS)
        );
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        f.deployAndCall(address(impl), initData);
    }

    function test_Initialize_RevertsForZeroEmergencyAdmin() public {
        MinimalUUPSFactory f = new MinimalUUPSFactory();
        kToken impl = new kToken();
        bytes memory initData = abi.encodeCall(
            kToken.initialize, (owner, admin, address(0), minter, NAME, SYMBOL, DECIMALS)
        );
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        f.deployAndCall(address(impl), initData);
    }

    function test_Initialize_RevertsForZeroMinter() public {
        MinimalUUPSFactory f = new MinimalUUPSFactory();
        kToken impl = new kToken();
        bytes memory initData = abi.encodeCall(
            kToken.initialize, (owner, admin, emergencyAdmin, address(0), NAME, SYMBOL, DECIMALS)
        );
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        f.deployAndCall(address(impl), initData);
    }

    // ============================================
    // UUPS UPGRADE AUTHORIZATION
    // ============================================

    function test_AuthorizeUpgrade_Success() public {
        kToken newImpl = new kToken();

        vm.prank(owner);
        token.upgradeToAndCall(address(newImpl), "");

        // Read ERC-1967 implementation slot to verify upgrade landed.
        bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address current = address(uint160(uint256(vm.load(address(token), implSlot))));
        assertEq(current, address(newImpl));
    }

    function test_AuthorizeUpgrade_RevertsForNonOwner() public {
        kToken newImpl = new kToken();

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(admin);
        token.upgradeToAndCall(address(newImpl), "");
    }

    function test_AuthorizeUpgrade_RevertsForZeroImplementation() public {
        vm.expectRevert(bytes(KTOKEN_ZERO_ADDRESS));
        vm.prank(owner);
        token.upgradeToAndCall(address(0), "");
    }
}

// Helper that rejects ETH — used to exercise emergencyWithdraw failure branch.
contract ETHRejector {
    // No receive/fallback — any value-bearing call reverts.
}

// Minimal interfaces for testing
interface IERC7802 {
    function crosschainMint(address to, uint256 amount) external;
    function crosschainBurn(address from, uint256 amount) external;
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
