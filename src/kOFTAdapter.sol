// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";

/// @title kOFTAdapter
/// @notice LayerZero OFT Adapter implementation for cross-chain token abstraction
/// @dev This contract is a wrapper around the OFTAdapterUpgradeable contract to implement the kToken contract
contract kOFTAdapter is OFTAdapterUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the address is the zero address
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor to initialize the kOFTAdapter contract
    /// @param _token The kToken contract
    /// @param _lzEndpoint The LayerZero endpoint
    constructor(address _token, address _lzEndpoint) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        _disableInitializers();
    }

    /// @notice Initializes the kOFTAdapter contract
    /// @dev Splits LayerZero delegate authority (send/receive libs, DVN,
    /// executor config) from contract ownership (upgrade authority,
    /// setDelegate authority) so the two can be held by distinct keys.
    /// @param _delegate LayerZero delegate — may rotate via setDelegate
    /// @param _owner Contract owner — controls upgrades and setDelegate
    function initialize(address _delegate, address _owner) external initializer {
        if (_delegate == address(0) || _owner == address(0)) revert ZeroAddress();
        __OFTAdapter_init(_delegate);
        __Ownable_init(_owner);
    }
}
