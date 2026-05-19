// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { KTOKEN_WRONG_ROLE } from "../../src/errors/Errors.sol";
import { kOFTAdapter } from "../../src/kOFTAdapter.sol";
import { kToken } from "../../src/kToken.sol";
import { Initializable } from "../../src/vendor/solady/utils/Initializable.sol";
import { Test } from "forge-std/Test.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";

contract kOFTAdapterTest is Test {
    kToken public token;
    kOFTAdapter public oftAdapter;
    address public lzEndpoint;
    address public owner = address(0x1);
    address public admin = address(0x2);
    address public emergencyAdmin = address(0x3);
    address public user = address(0x4);
    MinimalUUPSFactory public proxyFactory;

    string public constant NAME = "kUSD";
    string public constant SYMBOL = "kUSD";
    uint8 public constant DECIMALS = 18;

    function setUp() public {
        // Deploy mock LayerZero endpoint
        lzEndpoint = address(0x1337);
        vm.etch(lzEndpoint, "mock");

        // Deploy proxy factory
        proxyFactory = new MinimalUUPSFactory();

        // Deploy kToken via proxy (hub deployment pattern)
        kToken tokenImplementation = new kToken();
        bytes memory tokenInitData = abi.encodeCall(
            kToken.initialize,
            (owner, admin, emergencyAdmin, address(this), NAME, SYMBOL, DECIMALS) // temporary minter
        );
        address tokenProxy = proxyFactory.deployAndCall(address(tokenImplementation), tokenInitData);
        token = kToken(tokenProxy);

        // Deploy kOFTAdapter
        kOFTAdapter implementation = new kOFTAdapter(address(token), lzEndpoint);
        bytes memory data = abi.encodeCall(kOFTAdapter.initialize, (owner, owner));
        address proxy = proxyFactory.deployAndCall(address(implementation), data);
        oftAdapter = kOFTAdapter(proxy);

        // Grant adapter minter role
        vm.prank(admin);
        token.grantMinterRole(address(oftAdapter));

        // Mint initial supply to admin for testing lock/release pattern
        vm.prank(admin);
        token.grantMinterRole(address(this));
        token.crosschainMint(admin, 1_000_000e18);
    }

    function testInitialSetup() public view {
        assertEq(oftAdapter.token(), address(token));
        assertEq(oftAdapter.owner(), owner);
    }

    function testApprovalRequiredIsTrue() public view {
        // OFTAdapter requires approval because it transfers tokens
        assertTrue(oftAdapter.approvalRequired());
    }

    function testTokenFunctionReturnsToken() public view {
        assertEq(oftAdapter.token(), address(token));
    }

    function testLockAndReleasePattern() public {
        uint256 lockAmount = 1000e18;

        // Owner approves adapter to transfer tokens
        vm.prank(admin);
        token.approve(address(oftAdapter), lockAmount);

        uint256 ownerBalanceBefore = token.balanceOf(admin);
        uint256 adapterBalanceBefore = token.balanceOf(address(oftAdapter));

        // Simulate lock by transferring to adapter
        vm.prank(admin);
        token.transfer(address(oftAdapter), lockAmount);

        assertEq(token.balanceOf(admin), ownerBalanceBefore - lockAmount);
        assertEq(token.balanceOf(address(oftAdapter)), adapterBalanceBefore + lockAmount);
    }

    function testCrosschainMintOnlyByAdapter() public {
        // Adapter should be able to mint
        vm.prank(address(oftAdapter));
        token.crosschainMint(user, 1000e18);
        assertEq(token.balanceOf(user), 1000e18);

        // Non-minter should not be able to mint
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user);
        token.crosschainMint(user, 1000e18);
    }

    function testCrosschainBurnOnlyByAdapter() public {
        // First mint some tokens
        vm.prank(address(oftAdapter));
        token.crosschainMint(user, 1000e18);

        // Adapter should be able to burn
        vm.prank(address(oftAdapter));
        token.crosschainBurn(user, 500e18);
        assertEq(token.balanceOf(user), 500e18);

        // Non-minter should not be able to burn
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user);
        token.crosschainBurn(user, 100e18);
    }

    function testCannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oftAdapter.initialize(owner, owner);
    }

    function testAdapterHasMinterRole() public view {
        assertTrue(token.hasAnyRole(address(oftAdapter), token.MINTER_ROLE()));
    }

    function testUserCannotDirectlyMint() public {
        vm.expectRevert(bytes(KTOKEN_WRONG_ROLE));
        vm.prank(user);
        token.crosschainMint(user, 1000e18);
    }

    /* Delegate / owner split initialization */

    function test_initialize_revertsOnZeroDelegate() public {
        kOFTAdapter impl = new kOFTAdapter(address(token), lzEndpoint);
        bytes memory data = abi.encodeCall(kOFTAdapter.initialize, (address(0), address(this)));
        vm.expectRevert();
        proxyFactory.deployAndCall(address(impl), data);
    }

    function test_initialize_revertsOnZeroOwner() public {
        kOFTAdapter impl = new kOFTAdapter(address(token), lzEndpoint);
        bytes memory data = abi.encodeCall(kOFTAdapter.initialize, (address(this), address(0)));
        vm.expectRevert();
        proxyFactory.deployAndCall(address(impl), data);
    }

    function test_initialize_succeedsWithDistinctDelegateAndOwner() public {
        address delegate = makeAddr("delegate");
        address ownerAddr = makeAddr("ownerAddr");
        kOFTAdapter impl = new kOFTAdapter(address(token), lzEndpoint);
        bytes memory data = abi.encodeCall(kOFTAdapter.initialize, (delegate, ownerAddr));
        address proxy = proxyFactory.deployAndCall(address(impl), data);
        kOFTAdapter freshAdapter = kOFTAdapter(proxy);
        assertEq(freshAdapter.owner(), ownerAddr);
    }

    function test_setDelegate_onlyOwnerCanRotate() public {
        address delegate = makeAddr("delegate");
        address newDelegate = makeAddr("newDelegate");
        address ownerAddr = makeAddr("ownerAddr");
        kOFTAdapter impl = new kOFTAdapter(address(token), lzEndpoint);
        bytes memory data = abi.encodeCall(kOFTAdapter.initialize, (delegate, ownerAddr));
        address proxy = proxyFactory.deployAndCall(address(impl), data);
        kOFTAdapter freshAdapter = kOFTAdapter(proxy);

        vm.prank(delegate);
        vm.expectRevert();
        freshAdapter.setDelegate(newDelegate);

        vm.prank(ownerAddr);
        freshAdapter.setDelegate(newDelegate);
    }
}
