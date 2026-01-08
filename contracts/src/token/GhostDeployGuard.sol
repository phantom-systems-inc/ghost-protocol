// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGhostDeployGuard} from "../interfaces/IGhostDeployGuard.sol";

/// @title GhostDeployGuard
/// @notice Factory-origin enforcement for Ghost Protocol tokens
/// @dev Ensures only tokens deployed by authorized factories can interact with GhostVault.
///
///      Security model:
///        1. Only authorized factories can record deployments
///        2. GhostVault calls validateToken() before any ghost/redeem operation
///        3. Tokens not deployed by authorized factories are rejected
contract GhostDeployGuard is IGhostDeployGuard, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of authorized factory addresses
    mapping(address => bool) public override isAuthorizedFactory;

    /// @notice Mapping of token address to deploying factory
    mapping(address => address) private _tokenFactory;

    /// @notice Count of authorized factories
    uint256 public factoryCount;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the deploy guard
    /// @param initialOwner The initial owner address
    constructor(address initialOwner) Ownable(initialOwner) {
    }

    /*//////////////////////////////////////////////////////////////
                          VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostDeployGuard
    function isValidToken(address token) external view override returns (bool) {
        return _tokenFactory[token] != address(0);
    }

    /// @inheritdoc IGhostDeployGuard
    function getTokenFactory(address token) external view override returns (address) {
        return _tokenFactory[token];
    }

    /// @inheritdoc IGhostDeployGuard
    function validateToken(address token) external view override {
        if (_tokenFactory[token] == address(0)) {
            revert UnauthorizedToken(token);
        }
    }

    /// @inheritdoc IGhostDeployGuard
    function recordDeployment(address token) external override {
        if (!isAuthorizedFactory[msg.sender]) {
            revert UnauthorizedFactory(msg.sender);
        }
        if (token == address(0)) revert ZeroAddress();
        // HIGH-9 fix: Prevent overwriting existing token registrations
        if (_tokenFactory[token] != address(0)) {
            revert TokenAlreadyRegistered(token);
        }

        _tokenFactory[token] = msg.sender;

        emit TokenValidated(token, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostDeployGuard
    function authorizeFactory(address factory) external override onlyOwner {
        if (factory == address(0)) revert ZeroAddress();
        if (isAuthorizedFactory[factory]) return;

        isAuthorizedFactory[factory] = true;
        unchecked {
            factoryCount++;
        }

        emit FactoryAuthorized(factory);
    }

    /// @inheritdoc IGhostDeployGuard
    function revokeFactory(address factory) external override onlyOwner {
        if (!isAuthorizedFactory[factory]) return;

        isAuthorizedFactory[factory] = false;
        unchecked {
            factoryCount--;
        }

        emit FactoryRevoked(factory);
    }

    /// @inheritdoc IGhostDeployGuard
    /// @notice HIGH-1 fix: Allow owner to invalidate compromised tokens
    function invalidateToken(address token) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (_tokenFactory[token] == address(0)) revert UnauthorizedToken(token);

        delete _tokenFactory[token];

        emit TokenInvalidated(token);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get guard statistics
    function getStats() external view returns (uint256 factoriesCount, address guardOwner) {
        return (factoryCount, owner());
    }
}
