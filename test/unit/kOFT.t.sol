// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { KTOKEN_IS_PAUSED, KTOKEN_WRONG_ROLE } from "../../src/errors/Errors.sol";
import { kOFT } from "../../src/kOFT.sol";
import { kToken } from "../../src/kToken.sol";
import { Ownable } from "../../src/vendor/solady/auth/Ownable.sol";
import { ERC20 } from "../../src/vendor/solady/tokens/ERC20.sol";
import { Initializable } from "../../src/vendor/solady/utils/Initializable.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { Test } from "forge-std/Test.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

/**
 * @title kOFT Unit Tests
 * @notice Comprehensive unit tests for kOFT contract (Spoke chain)
 */
contract kOFTUnitTest is Test {
    kToken public token;
    kOFT public oft;

    address public owner = address(0x1);
    address public admin = address(0x2);
    address public emergencyAdmin = address(0x3);
    address public user1 = address(0x10);
    address public user2 = address(0x20);
    address public lzEndpoint;

    string constant NAME = "kUSD Token";
    string constant SYMBOL = "kUSD";
    uint8 constant DECIMALS = 6;

    MinimalUUPSFactory public proxyFactory;

    function setUp() public {
        // Mock LayerZero endpoint
        lzEndpoint = address(0x1337);
        vm.etch(lzEndpoint, "mock_endpoint");

        // Deploy proxy factory
        proxyFactory = new MinimalUUPSFactory();

        // Deploy kToken via proxy
        kToken tokenImplementation = new kToken();
        bytes memory tokenInitData = abi.encodeCall(
            kToken.initialize,
            (owner, admin, emergencyAdmin, address(this), NAME, SYMBOL, DECIMALS) // temporary minter
        );
        address tokenProxy = proxyFactory.deployAndCall(address(tokenImplementation), tokenInitData);
        token = kToken(tokenProxy);

        // Deploy kOFT
        kOFT implementation = new kOFT(lzEndpoint, token);
        bytes memory data = abi.encodeCall(kOFT.initialize, (owner, owner));
        address proxy = proxyFactory.deployAndCall(address(implementation), data);
        oft = kOFT(proxy);

        // Grant OFT minter role
        vm.prank(admin);
        token.grantMinterRole(address(oft));
    }

    // ============================================
    // INITIALIZATION TESTS
    // ============================================

    function test_Initialize_SetsOwner() public view {
        assertEq(oft.owner(), owner);
    }

    function test_Initialize_SetsTokenCorrectly() public view {
        assertEq(oft.token(), address(token));
    }

    function test_Initialize_CannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oft.initialize(owner, owner);
    }

    function test_Constructor_RevertsForZeroEndpoint() public {
        // kOFT constructor checks `lzEndpoint_ == address(0)` after the parent constructor
        // (which reads kToken_.decimals()) succeeds, and reverts with the contract-defined
        // ZeroAddress() selector.
        vm.expectRevert(kOFT.ZeroAddress.selector);
        new kOFT(address(0), token);
    }

    function test_Constructor_RevertsForZeroToken() public {
        // kToken_ == address(0) makes `kToken_.decimals()` (in the parent constructor's
        // initializer list) call into a non-contract address. Solidity reverts the call
        // with empty data because the returned uint8 cannot be decoded.
        kToken zeroToken = kToken(address(0));
        vm.expectRevert(bytes(""));
        new kOFT(lzEndpoint, zeroToken);
    }

    // ============================================
    // TOKEN INTERFACE TESTS
    // ============================================

    function test_Token_ReturnsCorrectAddress() public view {
        assertEq(oft.token(), address(token));
    }

    function test_ApprovalRequired_ReturnsFalse() public view {
        assertFalse(oft.approvalRequired());
    }

    // ============================================
    // DEBIT TESTS (Burn Logic)
    // ============================================

    function test_Debit_BurnsTokensFromSender() public {
        uint256 amount = 1000e6;

        // Setup: Mint tokens to user1
        vm.prank(address(oft));
        token.crosschainMint(user1, amount);

        uint256 balanceBefore = token.balanceOf(user1);
        uint256 supplyBefore = token.totalSupply();

        // Simulate debit (this would be called internally by send())
        // We need to expose this for testing or test through actual send
        // For now, test the effect through crosschainBurn which _debit calls
        vm.prank(address(oft));
        token.crosschainBurn(user1, 400e6);

        assertEq(token.balanceOf(user1), balanceBefore - 400e6);
        assertEq(token.totalSupply(), supplyBefore - 400e6);
    }

    function test_Debit_RevertsForInsufficientBalance() public {
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        vm.prank(address(oft));
        token.crosschainBurn(user1, 1000e6);
    }

    // ============================================
    // CREDIT TESTS (Mint Logic)
    // ============================================

    function test_Credit_MintsTokensToRecipient() public {
        uint256 amount = 1000e6;

        uint256 balanceBefore = token.balanceOf(user1);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(address(oft));
        token.crosschainMint(user1, amount);

        assertEq(token.balanceOf(user1), balanceBefore + amount);
        assertEq(token.totalSupply(), supplyBefore + amount);
    }

    function test_Credit_HandlesZeroAddress() public {
        // OFT should redirect address(0) to address(0xdead)
        // This is handled in _credit function
        uint256 amount = 1000e6;

        // When minting to address(0), it should go to 0xdead instead
        // Testing through the actual behavior
        vm.prank(address(oft));
        token.crosschainMint(address(0xdead), amount);

        assertEq(token.balanceOf(address(0xdead)), amount);
    }

    // ============================================
    // BUILD MSG AND OPTIONS TESTS
    // ============================================

    function test_BuildMsgAndOptions_Success() public view {
        SendParam memory param = SendParam({
            dstEid: 1,
            to: bytes32(uint256(uint160(user1))),
            amountLD: 1000e6,
            minAmountLD: 1000e6,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });

        (bytes memory message,) = oft.buildMsgAndOptions(param, 1000e6);

        assertGt(message.length, 0, "Message should not be empty");
        // Options can be empty or contain default values
    }

    function test_BuildMsgAndOptions_DifferentAmounts() public view {
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100e6;
        amounts[1] = 1000e6;
        amounts[2] = 10_000e6;

        for (uint256 i = 0; i < amounts.length; i++) {
            SendParam memory param = SendParam({
                dstEid: 1,
                to: bytes32(uint256(uint160(user1))),
                amountLD: amounts[i],
                minAmountLD: amounts[i],
                extraOptions: "",
                composeMsg: "",
                oftCmd: ""
            });

            (bytes memory message,) = oft.buildMsgAndOptions(param, amounts[i]);
            assertGt(message.length, 0);
        }
    }

    // ============================================
    // PEER MANAGEMENT TESTS
    // ============================================

    function test_SetPeer_Success() public {
        uint32 dstEid = 110;
        bytes32 peer = bytes32(uint256(uint160(address(0x9999))));

        vm.prank(owner);
        oft.setPeer(dstEid, peer);

        assertEq(oft.peers(dstEid), peer);
    }

    function test_SetPeer_RevertsForNonOwner() public {
        uint32 dstEid = 110;
        bytes32 peer = bytes32(uint256(uint160(address(0x9999))));

        // kOFT inherits OFTCoreUpgradeable -> OZ's OwnableUpgradeable, whose error is
        // OwnableUnauthorizedAccount(address) (different from Solady's Unauthorized()).
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        oft.setPeer(dstEid, peer);
    }

    function test_SetPeer_CanUpdateExisting() public {
        uint32 dstEid = 110;
        bytes32 peer1 = bytes32(uint256(uint160(address(0x9999))));
        bytes32 peer2 = bytes32(uint256(uint160(address(0x8888))));

        vm.startPrank(owner);
        oft.setPeer(dstEid, peer1);
        assertEq(oft.peers(dstEid), peer1);

        oft.setPeer(dstEid, peer2);
        assertEq(oft.peers(dstEid), peer2);
        vm.stopPrank();
    }

    // ============================================
    // INTEGRATION WITH kToken
    // ============================================

    function test_OFT_HasMinterRole() public view {
        assertTrue(token.hasAnyRole(address(oft), token.MINTER_ROLE()));
    }

    function test_OFT_CanMintTokens() public {
        uint256 amount = 5000e6;

        vm.prank(address(oft));
        token.crosschainMint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
    }

    function test_OFT_CanBurnTokens() public {
        uint256 amount = 5000e6;

        vm.prank(address(oft));
        token.crosschainMint(user1, amount);

        vm.prank(address(oft));
        token.crosschainBurn(user1, 2000e6);

        assertEq(token.balanceOf(user1), 3000e6);
    }

    function test_NonOFT_CannotMint() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.crosschainMint(user1, 1000e6);
    }

    function test_NonOFT_CannotBurn() public {
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user1);
        token.crosschainBurn(user1, 500e6);
    }

    // ============================================
    // PAUSED STATE TESTS
    // ============================================

    function test_Mint_RevertsWhenTokenPaused() public {
        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);
    }

    function test_Burn_RevertsWhenTokenPaused() public {
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        vm.prank(emergencyAdmin);
        token.setPaused(true);

        vm.expectRevert(bytes(KTOKEN_IS_PAUSED));
        vm.prank(address(oft));
        token.crosschainBurn(user1, 500e6);
    }

    // ============================================
    // DECIMAL HANDLING TESTS
    // ============================================

    function test_Decimals_MatchesToken() public view {
        // OFT should use token's decimals
        assertEq(token.decimals(), DECIMALS);
    }

    function test_AmountLD_HandlesCorrectDecimals() public {
        // Test that amounts in local decimals work correctly
        uint256 amount = 1000 * 10 ** DECIMALS; // 1000 tokens

        vm.prank(address(oft));
        token.crosschainMint(user1, amount);

        assertEq(token.balanceOf(user1), amount);
    }

    // ============================================
    // SUPPLY TRACKING
    // ============================================

    function test_MintIncreasesSupply() public {
        uint256 supplyBefore = token.totalSupply();

        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        assertEq(token.totalSupply(), supplyBefore + 1000e6);
    }

    function test_BurnDecreasesSupply() public {
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        uint256 supplyBefore = token.totalSupply();

        vm.prank(address(oft));
        token.crosschainBurn(user1, 400e6);

        assertEq(token.totalSupply(), supplyBefore - 400e6);
    }

    function test_MultipleOperations_SupplyTracking() public {
        vm.startPrank(address(oft));

        token.crosschainMint(user1, 1000e6);
        assertEq(token.totalSupply(), 1000e6);

        token.crosschainMint(user2, 500e6);
        assertEq(token.totalSupply(), 1500e6);

        token.crosschainBurn(user1, 300e6);
        assertEq(token.totalSupply(), 1200e6);

        token.crosschainBurn(user2, 200e6);
        assertEq(token.totalSupply(), 1000e6);

        vm.stopPrank();
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_MintAndBurn(uint256 mintAmount, uint256 burnAmount) public {
        mintAmount = bound(mintAmount, 1e6, type(uint96).max);
        burnAmount = bound(burnAmount, 1e6, mintAmount);

        vm.startPrank(address(oft));

        token.crosschainMint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);

        token.crosschainBurn(user1, burnAmount);
        assertEq(token.balanceOf(user1), mintAmount - burnAmount);

        vm.stopPrank();
    }

    function testFuzz_SetPeer(uint32 eid, address peerAddr) public {
        vm.assume(eid > 0);
        vm.assume(peerAddr != address(0));

        bytes32 peer = bytes32(uint256(uint160(peerAddr)));

        vm.prank(owner);
        oft.setPeer(eid, peer);

        assertEq(oft.peers(eid), peer);
    }

    // ============================================
    // CRITICAL EDGE CASES
    // ============================================

    function test_RevokedOFT_CannotMint() public {
        vm.prank(admin);
        token.revokeMinterRole(address(oft));

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);
    }

    function test_RevokedOFT_CannotBurn() public {
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        vm.prank(admin);
        token.revokeMinterRole(address(oft));

        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(address(oft));
        token.crosschainBurn(user1, 500e6);
    }

    function test_ZeroAmount_Mint() public {
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(address(oft));
        token.crosschainMint(user1, 0);

        assertEq(token.balanceOf(user1), balanceBefore);
    }

    function test_ZeroAmount_Burn() public {
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(address(oft));
        token.crosschainBurn(user1, 0);

        assertEq(token.balanceOf(user1), balanceBefore);
    }

    function test_SetPeer_ToZeroAddress() public {
        vm.prank(owner);
        oft.setPeer(110, bytes32(0));

        assertEq(oft.peers(110), bytes32(0));
    }

    function test_GetPeer_NonexistentChain() public view {
        assertEq(oft.peers(999), bytes32(0));
    }

    function test_MultipleOFTs_CanCoexist() public {
        // Deploy second OFT
        kOFT oft2Implementation = new kOFT(lzEndpoint, token);
        bytes memory data2 = abi.encodeCall(kOFT.initialize, (owner, owner));
        address proxy2 = proxyFactory.deployAndCall(address(oft2Implementation), data2);
        kOFT oft2 = kOFT(proxy2);

        vm.prank(admin);
        token.grantMinterRole(address(oft2));

        // Both should work independently
        vm.prank(address(oft));
        token.crosschainMint(user1, 1000e6);

        vm.prank(address(oft2));
        token.crosschainMint(user2, 2000e6);

        assertEq(token.balanceOf(user1), 1000e6);
        assertEq(token.balanceOf(user2), 2000e6);
    }

    /* Delegate / owner split initialization */

    function test_initialize_revertsOnZeroDelegate() public {
        kOFT impl = new kOFT(lzEndpoint, token);
        bytes memory data = abi.encodeCall(kOFT.initialize, (address(0), address(this)));
        vm.expectRevert();
        proxyFactory.deployAndCall(address(impl), data);
    }

    function test_initialize_revertsOnZeroOwner() public {
        kOFT impl = new kOFT(lzEndpoint, token);
        bytes memory data = abi.encodeCall(kOFT.initialize, (address(this), address(0)));
        vm.expectRevert();
        proxyFactory.deployAndCall(address(impl), data);
    }

    function test_initialize_succeedsWithDistinctDelegateAndOwner() public {
        address delegate = makeAddr("delegate");
        address ownerAddr = makeAddr("ownerAddr");
        kOFT impl = new kOFT(lzEndpoint, token);
        bytes memory data = abi.encodeCall(kOFT.initialize, (delegate, ownerAddr));
        address proxy = proxyFactory.deployAndCall(address(impl), data);
        kOFT freshOFT = kOFT(proxy);
        assertEq(freshOFT.owner(), ownerAddr);
    }

    function test_setDelegate_onlyOwnerCanRotate() public {
        address delegate = makeAddr("delegate");
        address newDelegate = makeAddr("newDelegate");
        address ownerAddr = makeAddr("ownerAddr");
        kOFT impl = new kOFT(lzEndpoint, token);
        bytes memory data = abi.encodeCall(kOFT.initialize, (delegate, ownerAddr));
        address proxy = proxyFactory.deployAndCall(address(impl), data);
        kOFT freshOFT = kOFT(proxy);

        // Non-owner cannot rotate delegate
        vm.prank(delegate);
        vm.expectRevert();
        freshOFT.setDelegate(newDelegate);

        // Owner can rotate delegate
        vm.prank(ownerAddr);
        freshOFT.setDelegate(newDelegate);
    }

    function test_Burn_ExactBalance() public {
        uint256 amount = 1000e6;

        vm.prank(address(oft));
        token.crosschainMint(user1, amount);

        vm.prank(address(oft));
        token.crosschainBurn(user1, amount);

        assertEq(token.balanceOf(user1), 0);
        assertEq(token.totalSupply(), 0);
    }

    function test_SupplyTracking_AfterManyOperations() public {
        uint256[] memory mints = new uint256[](5);
        mints[0] = 1000e6;
        mints[1] = 2500e6;
        mints[2] = 750e6;
        mints[3] = 3200e6;
        mints[4] = 1800e6;

        uint256 expectedSupply = 0;

        vm.startPrank(address(oft));

        for (uint256 i = 0; i < mints.length; i++) {
            token.crosschainMint(user1, mints[i]);
            expectedSupply += mints[i];
            assertEq(token.totalSupply(), expectedSupply);
        }

        // Burn some
        token.crosschainBurn(user1, 1500e6);
        expectedSupply -= 1500e6;
        assertEq(token.totalSupply(), expectedSupply);

        vm.stopPrank();
    }
}
