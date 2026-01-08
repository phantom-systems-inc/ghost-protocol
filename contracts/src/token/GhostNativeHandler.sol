// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title GhostNativeHandler
/// @notice Thin adapter for Avalanche's Native Minter precompile
/// @dev This is the ONLY Avalanche-coupled contract in the codebase.
///
///      Design principles:
///        - Treat as a thin adapter wrapping the Native Minter precompile
///        - GhostVault calls this adapter, NOT the precompile directly
///        - No Avalanche-specific types or logic should leak to other contracts
///        - If future portability needed, swap this adapter for another chain's mechanism
///
///      Avalanche Native Minter Precompile:
///        - Address: 0x0200000000000000000000000000000000000001
///        - Allows minting/burning native tokens on Avalanche Subnets
///        - Must be enabled in genesis config with admin addresses
///
/// @custom:security-contact security@ghostcoin.com
contract GhostNativeHandler is Ownable {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Avalanche Native Minter precompile address
    /// @dev Standard address for all Avalanche Subnets
    address public constant NATIVE_MINTER = 0x0200000000000000000000000000000000000001;

    /// @notice Function selector for mintNativeCoin(address,uint256)
    /// @dev From Avalanche Subnet-EVM Native Minter precompile
    bytes4 private constant MINT_SELECTOR = 0x4f5aaaba;

    /// @notice Standard burn address for native tokens
    /// @dev Avalanche Native Minter precompile has NO burn function.
    ///      Burning is done by transferring to an unowned address.
    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The authorized contract that can mint/burn (GhostVault)
    address public vault;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when native GHOST is minted
    event NativeMinted(address indexed to, uint256 amount);

    /// @notice Emitted when native GHOST is burned
    event NativeBurned(address indexed from, uint256 amount);

    /// @notice Emitted when vault is set
    event VaultSet(address indexed vault);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyVault();
    error MintFailed();
    error BurnFailed();
    error VaultAlreadySet();
    error InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the native handler
    /// @param initialOwner The initial owner (can set vault)
    constructor(address initialOwner) Ownable(initialOwner) {
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the vault address (one-time setup)
    /// @param _vault The GhostVault address
    function setVault(address _vault) external onlyOwner {
        if (vault != address(0)) revert VaultAlreadySet();
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        emit VaultSet(_vault);
    }

    /*//////////////////////////////////////////////////////////////
                          MINT/BURN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint native GHOST to a recipient
    /// @param to The recipient address
    /// @param amount The amount to mint
    /// @dev Only callable by GhostVault during redemption
    function mintNativeTo(address to, uint256 amount) external {
        if (msg.sender != vault) revert OnlyVault();
        if (amount == 0) revert InvalidAmount();

        // Call Native Minter precompile
        (bool success, ) = NATIVE_MINTER.call(
            abi.encodeWithSelector(MINT_SELECTOR, to, amount)
        );

        if (!success) revert MintFailed();

        emit NativeMinted(to, amount);
    }

    /// @notice Burn native GHOST (must receive msg.value)
    /// @dev Only callable by GhostVault during ghosting
    ///      The vault must send the GHOST to burn as msg.value.
    ///      Avalanche Native Minter has NO burn function - we transfer to a dead address.
    function burnNative() external payable {
        if (msg.sender != vault) revert OnlyVault();
        if (msg.value == 0) revert InvalidAmount();

        // Transfer native tokens to burn address (no burn function in Native Minter)
        // Using low-level call to handle any edge cases
        (bool success, ) = BURN_ADDRESS.call{value: msg.value}("");

        if (!success) revert BurnFailed();

        emit NativeBurned(msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check if Native Minter precompile is available
    /// @dev Returns true if the precompile has code (enabled in genesis)
    function isNativeMinterEnabled() external view returns (bool) {
        uint256 size;
        address minter = NATIVE_MINTER;
        assembly {
            size := extcodesize(minter)
        }
        return size > 0;
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow receiving native GHOST for burning
    receive() external payable {}
}
