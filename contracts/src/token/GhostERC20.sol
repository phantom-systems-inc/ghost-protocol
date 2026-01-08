// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IGhostERC20} from "../interfaces/IGhostERC20.sol";
import {PoseidonLib} from "../libraries/PoseidonLib.sol";

/// @title GhostERC20
/// @notice Privacy-enabled ERC20 token for Ghost Protocol on Avalanche L1
/// @dev Non-upgradeable ERC20 deployed via CREATE2 for deterministic addresses.
///
///      Features:
///        - Integrates with GhostVault for vanish/summon operations
///        - Computes token ID hash using Poseidon (T3) for ZK proofs
///        - Supports ERC677 transferAndCall for bridge integration
///        - ERC20Permit for gasless approvals
contract GhostERC20 is ERC20Permit, IGhostERC20 {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostERC20
    address public override gateway;

    /// @inheritdoc IGhostERC20
    address public override counterpart;

    /// @inheritdoc IGhostERC20
    address public override vault;

    /// @notice The factory that deployed this token
    address public factory;

    /// @notice Token decimals
    uint8 private immutable _decimals;

    /// @notice Cached token ID hash for ZK proofs
    bytes32 private immutable _tokenIdHash;

    /// @notice Whether this token is ghost-enabled
    bool private _ghostEnabled;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice L-3 fix: Emitted when ghost functionality is enabled
    event GhostEnabled(address indexed token);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyGateway();
    error OnlyVault();
    error NotGhostEnabled();
    error AlreadyEnabled();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyGateway() {
        if (msg.sender != gateway) revert OnlyGateway();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy a new GhostERC20 token
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param decimals_ Token decimals
    /// @param gateway_ Gateway contract address
    /// @param counterpart_ Counterpart token address on other chain
    /// @param vault_ GhostVault address
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address gateway_,
        address counterpart_,
        address vault_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _decimals = decimals_;
        gateway = gateway_;
        counterpart = counterpart_;
        vault = vault_;
        factory = msg.sender;

        // Compute and cache the token ID hash
        _tokenIdHash = PoseidonLib.computeTokenId(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Enable ghost functionality (enables vanish/summon operations)
    /// @dev Called by factory after deployment and registration
    function enableGhost() external {
        if (_ghostEnabled) revert AlreadyEnabled();
        require(msg.sender == factory, "Only factory");
        _ghostEnabled = true;

        // L-3 fix: Emit event when ghost functionality is enabled
        emit GhostEnabled(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get token decimals
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc IGhostERC20
    function tokenIdHash() external view override returns (bytes32) {
        return _tokenIdHash;
    }

    /// @inheritdoc IGhostERC20
    function isGhostEnabled() external view override returns (bool) {
        return _ghostEnabled;
    }

    /*//////////////////////////////////////////////////////////////
                          GATEWAY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostERC20
    function mint(address to, uint256 amount) external override onlyGateway {
        _mint(to, amount);
    }

    /// @inheritdoc IGhostERC20
    function burn(address from, uint256 amount) external override onlyGateway {
        _burn(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostERC20
    function vaultTransferFrom(address from, uint256 amount) external override onlyVault {
        if (!_ghostEnabled) revert NotGhostEnabled();
        _burn(from, amount);
    }

    /// @inheritdoc IGhostERC20
    function vaultMint(address to, uint256 amount) external override onlyVault {
        if (!_ghostEnabled) revert NotGhostEnabled();
        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC677 SUPPORT
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC677 transferAndCall for bridge integration
    function transferAndCall(
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        _transfer(msg.sender, receiver, amount);

        if (receiver.code.length > 0) {
            (bool success, ) = receiver.call(
                abi.encodeWithSignature(
                    "onTokenTransfer(address,uint256,bytes)",
                    msg.sender,
                    amount,
                    data
                )
            );
            require(success, "ERC677: callback failed");
        }

        return true;
    }
}
