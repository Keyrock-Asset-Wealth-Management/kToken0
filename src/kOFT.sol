// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { OFTCoreUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTCoreUpgradeable.sol";
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { kToken } from "./kToken.sol";

/// @title kOFT
/// @notice LayerZero OFT implementation for cross-chain token abstraction
/// @dev This contract is a wrapper around the OFTCoreUpgradeable contract to implement the kToken contract
contract kOFT is OFTCoreUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the address is the zero address
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The kToken contract
    kToken public immutable token0;

    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor to initialize the kOFT contract
    /// @param lzEndpoint_ The LayerZero endpoint
    /// @param kToken_ The kToken contract
    constructor(address lzEndpoint_, kToken kToken_) OFTCoreUpgradeable(kToken_.decimals(), lzEndpoint_) {
        if (lzEndpoint_ == address(0) || address(kToken_) == address(0)) {
            revert ZeroAddress();
        }

        token0 = kToken_;

        _disableInitializers();
    }

    /// @notice Initializes the kOFT contract
    /// @dev Splits LayerZero delegate authority (send/receive libs, DVN,
    /// executor config) from contract ownership (upgrade authority,
    /// setDelegate authority) so the two can be held by distinct keys.
    /// @param _delegate LayerZero delegate — may rotate via setDelegate
    /// @param _owner Contract owner — controls upgrades and setDelegate
    function initialize(address _delegate, address _owner) external initializer {
        if (_delegate == address(0) || _owner == address(0)) revert ZeroAddress();
        __OFTCore_init(_delegate);
        __Ownable_init(_owner);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Debits tokens from the sender's balance (internal, override)
    /// @param _from The address from which to debit tokens
    /// @param _amountLD The amount to debit (local decimals)
    /// @param _minAmountLD The minimum amount to debit (local decimals)
    /// @param _dstEid The destination chain id
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    )
        internal
        virtual
        override
        returns (uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // @dev In NON-default OFT, amountSentLD could be 100, with a 10% fee, the amountReceivedLD amount is 90,
        // therefore amountSentLD CAN differ from amountReceivedLD.

        // @dev Default OFT burns on src.
        token0.crosschainBurn(_from, amountSentLD);
    }

    /// @notice Credits tokens to the specified address (internal, override)
    /// @param _to The address to credit tokens to
    /// @param _amountLD The amount to credit (local decimals)
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    )
        internal
        virtual
        override
        returns (uint256 amountReceivedLD)
    {
        if (_to == address(0)) _to = address(0xdead); // _mint(...) does not support address(0x0)
        // @dev Default OFT mints on dst.
        token0.crosschainMint(_to, _amountLD);
        // @dev In the case of NON-default OFT, the _amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Indicates whether approval is required to send tokens (always false for OFT)
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /// @notice Returns the address of the token (OFT pattern: self-address)
    function token() public view returns (address) {
        return address(token0);
    }

    /// @notice Builds the message and options for a send operation
    /// @param _sendParam The send parameter struct
    /// @param _amountToCreditLD The amount to credit (local decimals)
    /// @return message The encoded message
    /// @return options The encoded options
    function buildMsgAndOptions(
        SendParam calldata _sendParam,
        uint256 _amountToCreditLD
    )
        external
        view
        returns (bytes memory message, bytes memory options)
    {
        return _buildMsgAndOptions(_sendParam, _amountToCreditLD);
    }
}
