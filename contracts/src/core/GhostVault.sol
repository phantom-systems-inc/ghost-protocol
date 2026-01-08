// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGhostVault} from "../interfaces/IGhostVault.sol";
import {IGhostRedemptionVerifier} from "../interfaces/IGhostRedemptionVerifier.sol";
import {IGhostDeployGuard} from "../interfaces/IGhostDeployGuard.sol";
import {IGhostERC20} from "../interfaces/IGhostERC20.sol";
import {GhostCommitmentTree} from "./GhostCommitmentTree.sol";
import {GhostNullifierRegistry} from "./GhostNullifierRegistry.sol";
import {GhostNativeHandler} from "../token/GhostNativeHandler.sol";
import {PoseidonLib} from "../libraries/PoseidonLib.sol";

/// @title GhostVault
/// @notice Main privacy pool vault for Ghost Protocol on Avalanche L1
/// @dev Orchestrates vanish/summon operations with ZK proof verification.
///
///      Architecture:
///        - Commitments are computed OFF-CHAIN (Poseidon T6)
///        - On-chain uses only Poseidon T3 for Merkle tree operations
///        - Native GHOST minting/burning via GhostNativeHandler adapter
///        - Uses OpenZeppelin Ownable for access control
///
///      Vanish flow:
///        1. User computes commitment off-chain: Poseidon5(secret, nullifier_secret, token_id, amount, blinding)
///        2. User calls vanish(token, amount, commitment)
///        3. Vault validates token via deployGuard
///        4. Vault burns tokens from user via GhostERC20
///        5. Vault records commitment in tree
///
///      Summon flow:
///        1. User generates ZK proof off-chain
///        2. User calls summon(token, proof, inputs)
///        3. Vault validates root and verifies ZK proof
///        4. Vault records nullifier (AFTER proof verification)
///        5. Vault mints tokens to recipient
contract GhostVault is IGhostVault, Ownable, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostVault
    address public override commitmentTree;

    /// @inheritdoc IGhostVault
    address public override nullifierRegistry;

    /// @notice The ZK proof verifier for summon operations
    address public override summonVerifier;

    /// @inheritdoc IGhostVault
    address public override deployGuard;

    /// @notice The native GHOST handler (Avalanche adapter)
    address public nativeHandler;

    /// @inheritdoc IGhostVault
    bool public override paused;

    /// @inheritdoc IGhostVault
    mapping(address => uint256) public override totalVanished;

    /// @notice Mapping of token address to token ID hash
    mapping(address => bytes32) public tokenIdHashes;

    /// @notice Total native GHOST in privacy pool
    uint256 private _totalNativeVanished;

    /// @notice Cached native token ID hash
    bytes32 private _nativeTokenId;

    /// @notice Mapping of commitment => depositor address (for DMS)
    mapping(bytes32 => address) public commitmentDepositors;

    /// @notice Rate limiting: last vanish timestamp per address
    mapping(address => uint256) public lastVanishTime;

    /// @notice Cooldown period between vanish operations (seconds)
    uint256 public vanishCooldown = 5;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event VaultPaused(address indexed account);
    event VaultUnpaused(address indexed account);
    event VanishCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event ComponentsSet(
        address commitmentTree,
        address nullifierRegistry,
        address summonVerifier,
        address deployGuard,
        address nativeHandler
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AlreadyPaused();
    error NotPaused();
    error RateLimited(uint256 timeRemaining);
    error ComponentsAlreadySet();
    error InvalidCommitment();

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier rateLimited() {
        if (vanishCooldown > 0) {
            uint256 timeSinceLastVanish = block.timestamp - lastVanishTime[msg.sender];
            if (timeSinceLastVanish < vanishCooldown) {
                revert RateLimited(vanishCooldown - timeSinceLastVanish);
            }
        }
        _;
        lastVanishTime[msg.sender] = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize the vault
    /// @param initialOwner The initial owner address
    constructor(address initialOwner) Ownable(initialOwner) {
        // Compute native token ID: Poseidon(address(0), 0)
        _nativeTokenId = PoseidonLib.hash2(bytes32(0), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Set all component addresses (one-time setup after CREATE2 deployment)
    /// @param _commitmentTree The commitment tree address
    /// @param _nullifierRegistry The nullifier registry address
    /// @param _summonVerifier The summon verifier address
    /// @param _deployGuard The deploy guard address
    /// @param _nativeHandler The native handler address
    function setComponents(
        address _commitmentTree,
        address _nullifierRegistry,
        address _summonVerifier,
        address _deployGuard,
        address _nativeHandler
    ) external onlyOwner {
        if (commitmentTree != address(0)) revert ComponentsAlreadySet();

        require(_commitmentTree != address(0), "Invalid commitmentTree");
        require(_nullifierRegistry != address(0), "Invalid nullifierRegistry");
        require(_summonVerifier != address(0), "Invalid summonVerifier");
        require(_deployGuard != address(0), "Invalid deployGuard");
        require(_nativeHandler != address(0), "Invalid nativeHandler");

        commitmentTree = _commitmentTree;
        nullifierRegistry = _nullifierRegistry;
        summonVerifier = _summonVerifier;
        deployGuard = _deployGuard;
        nativeHandler = _nativeHandler;

        emit ComponentsSet(
            _commitmentTree,
            _nullifierRegistry,
            _summonVerifier,
            _deployGuard,
            _nativeHandler
        );
    }

    /*//////////////////////////////////////////////////////////////
                          VANISH FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostVault
    function vanish(
        address token,
        uint256 amount,
        bytes32 commitment
    ) external override nonReentrant whenNotPaused rateLimited returns (uint256 leafIndex) {
        // Validate inputs
        if (amount == 0) revert InvalidAmount();
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (!PoseidonLib.isValidCommitment(commitment)) revert InvalidCommitment();

        // Validate token is authorized (CRITICAL-2 fix)
        IGhostDeployGuard(deployGuard).validateToken(token);

        // Burn tokens from user (CRITICAL-2 fix)
        IGhostERC20(token).vaultTransferFrom(msg.sender, amount);

        // Record commitment in tree
        leafIndex = GhostCommitmentTree(commitmentTree).recordCommitment(commitment);

        // Store depositor for DMS ownership verification
        commitmentDepositors[commitment] = msg.sender;

        // Update accounting
        totalVanished[token] += amount;

        emit Vanish(token, msg.sender, amount, commitment, leafIndex);

        return leafIndex;
    }

    /// @inheritdoc IGhostVault
    function vanishNative(
        bytes32 commitment
    ) external payable override nonReentrant whenNotPaused rateLimited returns (uint256 leafIndex) {
        // Validate inputs
        if (msg.value == 0) revert InvalidAmount();
        if (commitment == bytes32(0)) revert InvalidCommitment();
        if (!PoseidonLib.isValidCommitment(commitment)) revert InvalidCommitment();

        // Burn native GHOST via handler
        GhostNativeHandler(payable(nativeHandler)).burnNative{value: msg.value}();

        // Record commitment in tree
        leafIndex = GhostCommitmentTree(commitmentTree).recordCommitment(commitment);

        // Store depositor for DMS ownership verification
        commitmentDepositors[commitment] = msg.sender;

        // Update accounting
        _totalNativeVanished += msg.value;

        emit VanishNative(msg.sender, msg.value, commitment, leafIndex);

        return leafIndex;
    }

    /*//////////////////////////////////////////////////////////////
                          SUMMON FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostVault
    function summon(
        address token,
        Proof calldata proof,
        SummonInputs calldata inputs
    ) external override nonReentrant whenNotPaused {
        // Validate inputs
        if (inputs.amount == 0) revert InvalidAmount();
        if (inputs.recipient == address(0)) revert InvalidRecipient();

        // Validate token is authorized (CRITICAL-2 fix)
        IGhostDeployGuard(deployGuard).validateToken(token);

        // Validate tokenId matches token (M-6 fix)
        bytes32 expectedTokenId = PoseidonLib.computeTokenId(token);
        if (inputs.tokenId != expectedTokenId) revert InvalidTokenId();

        // Validate root is known
        if (!GhostCommitmentTree(commitmentTree).isKnownRoot(inputs.root)) {
            revert InvalidRoot();
        }

        // Convert proof format for verifier
        uint256[8] memory proofArray = _packProof(proof);

        // CRITICAL-1 & CRITICAL-3 fix: Verify ZK proof BEFORE recording nullifier
        bool isValid = IGhostRedemptionVerifier(summonVerifier).verifyRedemptionProof(
            proofArray,
            inputs.root,
            inputs.nullifier,
            inputs.amount,
            inputs.recipient,
            inputs.changeCommitment,
            inputs.tokenId
        );
        if (!isValid) revert InvalidProof();

        // Record nullifier AFTER proof verification (CRITICAL-3 fix)
        GhostNullifierRegistry(nullifierRegistry).checkAndRecord(inputs.nullifier);

        // Update accounting
        totalVanished[token] -= inputs.amount;

        // Mint tokens to recipient (CRITICAL-2 fix)
        IGhostERC20(token).vaultMint(inputs.recipient, inputs.amount);

        emit Summon(token, inputs.recipient, inputs.amount, inputs.nullifier);

        // Record change commitment if partial withdrawal
        if (inputs.changeCommitment != bytes32(0)) {
            if (!PoseidonLib.isValidCommitment(inputs.changeCommitment)) {
                revert InvalidCommitment();
            }
            uint256 changeLeafIndex = GhostCommitmentTree(commitmentTree).recordCommitment(
                inputs.changeCommitment
            );
            emit ChangeCommitment(inputs.changeCommitment, changeLeafIndex);
        }
    }

    /// @inheritdoc IGhostVault
    function summonNative(
        Proof calldata proof,
        SummonInputs calldata inputs
    ) external override nonReentrant whenNotPaused {
        // Validate inputs
        if (inputs.amount == 0) revert InvalidAmount();
        if (inputs.recipient == address(0)) revert InvalidRecipient();

        // Validate token ID matches native
        if (inputs.tokenId != _nativeTokenId) revert InvalidToken();

        // Validate root is known
        if (!GhostCommitmentTree(commitmentTree).isKnownRoot(inputs.root)) {
            revert InvalidRoot();
        }

        // Convert proof format for verifier
        uint256[8] memory proofArray = _packProof(proof);

        // CRITICAL-1 & CRITICAL-3 fix: Verify ZK proof BEFORE recording nullifier
        bool isValid = IGhostRedemptionVerifier(summonVerifier).verifyRedemptionProof(
            proofArray,
            inputs.root,
            inputs.nullifier,
            inputs.amount,
            inputs.recipient,
            inputs.changeCommitment,
            inputs.tokenId
        );
        if (!isValid) revert InvalidProof();

        // Record nullifier AFTER proof verification (CRITICAL-3 fix)
        GhostNullifierRegistry(nullifierRegistry).checkAndRecord(inputs.nullifier);

        // Update accounting
        _totalNativeVanished -= inputs.amount;

        // Mint native GHOST via handler
        GhostNativeHandler(payable(nativeHandler)).mintNativeTo(inputs.recipient, inputs.amount);

        emit SummonNative(inputs.recipient, inputs.amount, inputs.nullifier);

        // Record change commitment if partial withdrawal
        if (inputs.changeCommitment != bytes32(0)) {
            if (!PoseidonLib.isValidCommitment(inputs.changeCommitment)) {
                revert InvalidCommitment();
            }
            uint256 changeLeafIndex = GhostCommitmentTree(commitmentTree).recordCommitment(
                inputs.changeCommitment
            );
            emit ChangeCommitment(inputs.changeCommitment, changeLeafIndex);
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostVault
    function pause() external override onlyOwner {
        if (paused) revert AlreadyPaused();
        paused = true;
        emit VaultPaused(msg.sender);
    }

    /// @inheritdoc IGhostVault
    function unpause() external override onlyOwner {
        if (!paused) revert NotPaused();
        paused = false;
        emit VaultUnpaused(msg.sender);
    }

    /// @notice Set the vanish cooldown period
    function setVanishCooldown(uint256 newCooldown) external onlyOwner {
        uint256 oldCooldown = vanishCooldown;
        vanishCooldown = newCooldown;
        emit VanishCooldownUpdated(oldCooldown, newCooldown);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Pack proof struct into array format for verifier
    function _packProof(Proof calldata proof) internal pure returns (uint256[8] memory) {
        return [
            proof.a[0],
            proof.a[1],
            proof.b[0][0],
            proof.b[0][1],
            proof.b[1][0],
            proof.b[1][1],
            proof.c[0],
            proof.c[1]
        ];
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostVault
    function totalNativeVanished() external view override returns (uint256) {
        return _totalNativeVanished;
    }

    /// @inheritdoc IGhostVault
    function nativeTokenId() external view override returns (bytes32) {
        return _nativeTokenId;
    }

    /// @notice Get vault statistics
    function getStats()
        external
        view
        returns (uint256 treeLeafCount, uint256 nullifierCount, bool isPaused)
    {
        treeLeafCount = GhostCommitmentTree(commitmentTree).leafCount();
        nullifierCount = GhostNullifierRegistry(nullifierRegistry).nullifierCount();
        isPaused = paused;
    }

    /// @notice Check if a nullifier has been spent
    function isNullifierSpent(bytes32 nullifier) external view returns (bool) {
        return GhostNullifierRegistry(nullifierRegistry).isSpent(nullifier);
    }

    /// @notice Check if a root is valid for proofs
    function isValidRoot(bytes32 root) external view returns (bool) {
        return GhostCommitmentTree(commitmentTree).isKnownRoot(root);
    }

    /*//////////////////////////////////////////////////////////////
                          RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow receiving native GHOST
    receive() external payable {}
}
