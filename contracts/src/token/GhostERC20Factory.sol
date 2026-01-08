// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IGhostERC20Factory} from "../interfaces/IGhostERC20Factory.sol";
import {IGhostDeployGuard} from "../interfaces/IGhostDeployGuard.sol";
import {GhostERC20} from "./GhostERC20.sol";
import {PoseidonLib} from "../libraries/PoseidonLib.sol";

/// @title GhostERC20Factory
/// @notice Factory for deploying GhostERC20 tokens with deterministic addresses
/// @dev Uses OpenZeppelin Create2 for gas-efficient deterministic deployments.
///
///      Per migration plan:
///        - Uses OZ Create2.sol instead of inline assembly
///        - Verifies deployed address matches expected address
///        - Records deployments with GhostDeployGuard
contract GhostERC20Factory is IGhostERC20Factory, Ownable {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostERC20Factory
    address public override vault;

    /// @notice The deploy guard address
    address public deployGuard;

    /// @notice Mapping of deployed tokens
    mapping(address => bool) public override isFactoryDeployed;

    /// @notice Mapping of token address to token ID hash
    mapping(address => bytes32) private _tokenIdHashes;

    /// @notice Authorized deployers
    mapping(address => bool) public isAuthorizedDeployer;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event DeployerAuthorized(address indexed deployer);
    event DeployerRevoked(address indexed deployer);
    event DeployGuardUpdated(address indexed newDeployGuard);
    event VaultUpdated(address indexed newVault);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyAuthorizedDeployer();
    error ZeroAddress();
    error AlreadyDeployed();
    error Create2AddressMismatch(address expected, address deployed);
    error VaultAlreadySet();
    error DeployGuardAlreadySet();
    error VaultNotSet();
    error UseComputeTokenAddressWithParams();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyAuthorized() {
        if (msg.sender != owner() && !isAuthorizedDeployer[msg.sender]) {
            revert OnlyAuthorizedDeployer();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the factory
    /// @param initialOwner The initial owner address
    constructor(address initialOwner) Ownable(initialOwner) {
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the vault address (one-time setup)
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) revert VaultAlreadySet();
        if (_vault == address(0)) revert ZeroAddress();
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @notice Set the deploy guard address (one-time setup)
    /// @dev M-1 fix: Added one-time guard
    function setDeployGuard(address _deployGuard) external onlyOwner {
        if (deployGuard != address(0)) revert DeployGuardAlreadySet();
        if (_deployGuard == address(0)) revert ZeroAddress();
        deployGuard = _deployGuard;
        emit DeployGuardUpdated(_deployGuard);
    }

    /*//////////////////////////////////////////////////////////////
                          DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostERC20Factory
    function deployToken(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address gateway,
        address counterpart,
        bytes32 salt
    ) external override onlyAuthorized returns (address token) {
        // M-7 fix: Block deployment until vault is configured
        if (vault == address(0)) revert VaultNotSet();
        if (gateway == address(0)) revert ZeroAddress();

        // Compute expected address
        bytes memory bytecode = _getCreationBytecode(
            name,
            symbol,
            decimals,
            gateway,
            counterpart
        );
        address expected = Create2.computeAddress(salt, keccak256(bytecode));

        // Check if already deployed
        if (isFactoryDeployed[expected]) revert AlreadyDeployed();

        // Deploy with CREATE2
        token = Create2.deploy(0, salt, bytecode);

        // Verify address matches (mandatory per plan)
        if (token != expected) {
            revert Create2AddressMismatch(expected, token);
        }

        // Compute token ID hash
        bytes32 tokenIdHash = PoseidonLib.computeTokenId(token);
        _tokenIdHashes[token] = tokenIdHash;
        isFactoryDeployed[token] = true;

        // Record with deploy guard
        if (deployGuard != address(0)) {
            IGhostDeployGuard(deployGuard).recordDeployment(token);
        }

        // Enable ghost functionality
        GhostERC20(token).enableGhost();

        emit GhostTokenDeployed(counterpart, token, tokenIdHash);

        return token;
    }

    /// @inheritdoc IGhostERC20Factory
    function registerToken(address token) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (isFactoryDeployed[token]) revert AlreadyDeployed();

        bytes32 tokenIdHash = PoseidonLib.computeTokenId(token);
        _tokenIdHashes[token] = tokenIdHash;
        isFactoryDeployed[token] = true;

        // Record with deploy guard
        if (deployGuard != address(0)) {
            IGhostDeployGuard(deployGuard).recordDeployment(token);
        }

        emit TokenRegistered(token, tokenIdHash);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostERC20Factory
    /// @dev HIGH-5 fix: Revert instead of returning misleading address(0)
    function computeTokenAddress(bytes32 /* salt */) external pure override returns (address) {
        // This function cannot compute address without full bytecode params
        // Use computeTokenAddressWithParams instead
        revert UseComputeTokenAddressWithParams();
    }

    /// @notice Compute token address with full parameters
    function computeTokenAddressWithParams(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address gateway,
        address counterpart,
        bytes32 salt
    ) external view returns (address) {
        bytes memory bytecode = _getCreationBytecode(
            name,
            symbol,
            decimals,
            gateway,
            counterpart
        );
        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /// @inheritdoc IGhostERC20Factory
    function getTokenIdHash(address token) external view override returns (bytes32) {
        return _tokenIdHashes[token];
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorize a deployer
    function authorizeDeployer(address deployer) external onlyOwner {
        if (deployer == address(0)) revert ZeroAddress();
        isAuthorizedDeployer[deployer] = true;
        emit DeployerAuthorized(deployer);
    }

    /// @notice Revoke a deployer's authorization
    function revokeDeployer(address deployer) external onlyOwner {
        isAuthorizedDeployer[deployer] = false;
        emit DeployerRevoked(deployer);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Get creation bytecode for GhostERC20
    function _getCreationBytecode(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address gateway,
        address counterpart
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            type(GhostERC20).creationCode,
            abi.encode(name, symbol, decimals, gateway, counterpart, vault)
        );
    }
}
