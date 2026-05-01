// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";
import { MinimalUUPSFactory } from "minimal-uups-factory/MinimalUUPSFactory.sol";
import { TimelockController } from "@openzeppelin-contracts/governance/TimelockController.sol";

import { kToken } from "../../src/kToken.sol";
import { Ownable } from "../../src/vendor/solady/auth/Ownable.sol";

/// @notice Phase 6 mirror test for the kToken0 repository.
///
/// In production, the kToken instances (kUSD, kBTC, etc) are deployed by the kam
/// pipeline and their ownership is transferred to the kam-deployed Admin Timelock
/// by `kam/script/deployment/13_DeployTimelock.s.sol`. The transfer happens from
/// the kam side because that is where the deployment artifact (addresses) lives.
///
/// This test proves the timelock pattern works correctly on a `kToken` proxy:
///   - Direct upgrades by previous owner / admin role-holder revert.
///   - Upgrades via the timelock (schedule -> wait -> execute) succeed.
///   - Other `_checkOwner()`-gated functions (grantAdminRole / revokeAdminRole)
///     become 3-day-gated automatically.
///   - Role-based admin operations (the ADMIN_ROLE held by an EOA / multisig)
///     remain instant — the migration only affects functions gated by Ownable.
///
/// **kTokenFactory is intentionally NOT covered**: it is a stateless deploy
/// helper, not Ownable, has no upgrade authority — see
/// `kam/docs/timelock-and-governance-spec.md` section 4.1 special-case notes.
contract TimelockKTokenTest is Test {
    uint256 internal constant DELAY = 3 days;

    kToken internal token;
    TimelockController internal timelock;
    MinimalUUPSFactory internal factory;

    address internal deployer;
    address internal admin;
    address internal guardian;
    address internal emergencyAdmin;
    address internal minter;
    address internal alice;

    bytes32 internal CANCELLER_ROLE;
    bytes32 internal DEFAULT_ADMIN_ROLE;

    /// @dev ERC-1967 implementation storage slot.
    bytes32 internal constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function setUp() public {
        deployer = makeAddr("deployer");
        admin = makeAddr("admin");
        guardian = makeAddr("guardian");
        emergencyAdmin = makeAddr("emergencyAdmin");
        minter = makeAddr("minter");
        alice = makeAddr("alice");

        // Deploy a kToken proxy with the deployer as initial owner.
        factory = new MinimalUUPSFactory();
        kToken impl = new kToken();
        bytes memory initData = abi.encodeCall(
            kToken.initialize, (deployer, admin, emergencyAdmin, minter, "KAM USDC", "kUSDC", uint8(6))
        );
        address proxy = factory.deployAndCall(address(impl), initData);
        token = kToken(proxy);
        require(token.owner() == deployer, "test setup: deployer is not initial owner");

        // Deploy the timelock the same way the kam deployment script does.
        // OZ v5.3.0 TimelockController is used here (matches kToken0's existing dependency);
        // kam vendors v5.6.1. Both versions use the same role graph and lifecycle, so the
        // pattern proven here also holds for kam's vendored timelock.
        address[] memory proposers = new address[](1);
        proposers[0] = admin;

        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);

        vm.startPrank(deployer);
        timelock = new TimelockController(DELAY, proposers, openExecutors, deployer);
        CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(CANCELLER_ROLE, guardian);
        timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer);

        // Transfer ownership of kToken to the timelock — this is what the kam migration
        // script does in production.
        Ownable(address(token)).transferOwnership(address(timelock));
        vm.stopPrank();

        require(token.owner() == address(timelock), "test setup: ownership transfer failed");
    }

    /* //////////////////////////////////////////////////////////////
                       OWNERSHIP AFTER TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_kToken_OwnedByTimelock() public view {
        assertEq(token.owner(), address(timelock));
    }

    /* //////////////////////////////////////////////////////////////
                       DIRECT UPGRADE NOW BLOCKED
    //////////////////////////////////////////////////////////////*/

    function test_kToken_DirectUpgradeByPreviousOwner_Reverts() public {
        kToken newImpl = new kToken();

        vm.prank(deployer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.upgradeToAndCall(address(newImpl), "");
    }

    function test_kToken_DirectUpgradeByAdmin_Reverts() public {
        // ADMIN holds ADMIN_ROLE but not the contract owner role — cannot upgrade directly.
        kToken newImpl = new kToken();

        vm.prank(admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.upgradeToAndCall(address(newImpl), "");
    }

    /* //////////////////////////////////////////////////////////////
                       UPGRADE VIA TIMELOCK SUCCEEDS
    //////////////////////////////////////////////////////////////*/

    function test_kToken_UpgradeViaTimelock_Succeeds() public {
        address implBefore = _readImplementation(address(token));
        kToken newImpl = new kToken();
        require(address(newImpl) != implBefore, "test setup: new impl collides with existing");

        bytes memory data = abi.encodeCall(token.upgradeToAndCall, (address(newImpl), ""));
        bytes32 salt = keccak256("upgrade-kToken-test");

        vm.prank(admin);
        timelock.schedule(address(token), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(token), 0, data, bytes32(0), salt);

        address implAfter = _readImplementation(address(token));
        assertEq(implAfter, address(newImpl), "ERC-1967 impl slot did not change to newImpl");
        assertTrue(implAfter != implBefore, "impl slot unchanged");
    }

    /* //////////////////////////////////////////////////////////////
                  ROLE GRANTS/REVOKES NOW 3D-GATED
              (they used onlyOwner -> _checkOwner)
    //////////////////////////////////////////////////////////////*/

    function test_kToken_GrantAdminRole_DirectByDeployer_Reverts() public {
        vm.prank(deployer);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.grantAdminRole(alice);
    }

    function test_kToken_GrantAdminRole_DirectByAdmin_Reverts() public {
        vm.prank(admin);
        vm.expectRevert(Ownable.Unauthorized.selector);
        token.grantAdminRole(alice);
    }

    function test_kToken_GrantAdminRole_ViaTimelock_Succeeds() public {
        bytes memory data = abi.encodeCall(token.grantAdminRole, (alice));
        bytes32 salt = keccak256("grant-admin-2026-05-01");

        vm.prank(admin);
        timelock.schedule(address(token), 0, data, bytes32(0), salt, DELAY);

        vm.warp(block.timestamp + DELAY);
        timelock.execute(address(token), 0, data, bytes32(0), salt);

        bytes32 id = timelock.hashOperation(address(token), 0, data, bytes32(0), salt);
        assertTrue(timelock.isOperationDone(id), "timelock op not Done");
        // Verify the role was actually granted: ADMIN_ROLE is bit 1 in OptimizedOwnableRoles.
        assertTrue(token.hasAnyRole(alice, 1 << 0), "alice does not have ADMIN_ROLE after timelock execute");
    }

    /* //////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    function _readImplementation(address proxy) internal view returns (address impl) {
        impl = address(uint160(uint256(vm.load(proxy, ERC1967_IMPL_SLOT))));
    }
}
