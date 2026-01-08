// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IGhostDeployGuard
/// @notice Interface for factory-origin enforcement
interface IGhostDeployGuard {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event FactoryAuthorized(address indexed factory);
    event FactoryRevoked(address indexed factory);
    event TokenValidated(address indexed token, address indexed factory);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error UnauthorizedFactory(address factory);
    error UnauthorizedToken(address token);
    error ZeroAddress();
    error TokenAlreadyRegistered(address token);

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenInvalidated(address indexed token);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if a factory is authorized
    function isAuthorizedFactory(address factory) external view returns (bool);

    /// @notice Check if a token is valid (deployed by authorized factory)
    function isValidToken(address token) external view returns (bool);

    /// @notice Get the factory that deployed a token
    function getTokenFactory(address token) external view returns (address);

    /// @notice Validate a token (reverts if not valid)
    function validateToken(address token) external view;

    /*//////////////////////////////////////////////////////////////
                          FACTORY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Record a token deployment (only callable by authorized factories)
    function recordDeployment(address token) external;

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize a factory
    function authorizeFactory(address factory) external;

    /// @notice Revoke a factory's authorization
    function revokeFactory(address factory) external;

    /// @notice Invalidate a token (emergency use only)
    function invalidateToken(address token) external;
}
