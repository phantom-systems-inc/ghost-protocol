// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGhostERC20Factory
/// @notice Interface for the GhostERC20 token factory
interface IGhostERC20Factory {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new GhostERC20 token is deployed
    event GhostTokenDeployed(
        address indexed counterpart,
        address indexed token,
        bytes32 tokenIdHash
    );

    /// @notice Emitted when an existing token is registered
    event TokenRegistered(address indexed token, bytes32 tokenIdHash);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the vault address
    function vault() external view returns (address);

    /// @notice Check if a token was deployed by this factory
    function isFactoryDeployed(address token) external view returns (bool);

    /// @notice Compute the address of a token before deployment
    function computeTokenAddress(
        bytes32 salt
    ) external view returns (address);

    /// @notice Get the token ID hash for a token
    function getTokenIdHash(address token) external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new GhostERC20 token
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address gateway,
        address counterpart,
        bytes32 salt
    ) external returns (address token);

    /// @notice Register an existing token
    function registerToken(address token) external;
}
