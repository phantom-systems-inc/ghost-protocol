# Architecture

Ghost Protocol is a commit-once, reveal-once privacy primitive implemented using ZK-SNARKs and deployed on the Umbraline Testnet L1.

This document describes the architecture of the reference implementation. While the reference implementation demonstrates privacy-preserving token transfers (vanish and summon), the same architecture applies to arbitrary value or information commitments.

## System Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                        Ghost Protocol                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────┐    ┌───────────────────┐    ┌────────────┐   │
│   │              │    │                   │    │            │   │
│   │  GhostVault  │───▶│ GhostCommitment   │    │  Groth16   │   │
│   │              │    │      Tree         │    │  Verifier  │   │
│   │  (Coordinator)     │  (Merkle Roots)  │    │  (ZK Proofs)   │
│   │              │    │                   │    │            │   │
│   └──────┬───────┘    └───────────────────┘    └────────────┘   │
│          │                                                      │
│          │            ┌───────────────────┐                     │
│          │            │                   │                     │
│          └───────────▶│ GhostNullifier    │                     │
│                       │    Registry       │                     │
│                       │ (One-time use)    │                     │
│                       │                   │                     │
│                       └───────────────────┘                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### GhostVault

The main entry point for Ghost Protocol operations. Orchestrates:

- **Commit (Vanish in the reference app)**: Records a cryptographic commitment
- **Reveal (Summon in the reference app)**: Verifies a ZK proof and executes the bound action
- **Application Binding**: In the reference implementation, reveal triggers token mint logic

```solidity
function vanish(address token, uint256 amount, bytes32 commitment) external;
function summon(address token, Proof proof, SummonInputs inputs) external;
```

### GhostCommitmentTree

Off-chain incremental Merkle tree with on-chain root tracking:

- **Tree Depth**: 20 levels (max ~1M commitments)
- **Root History**: Maintains last 100 roots for concurrent proof generation
- **Hash Function**: Poseidon T3 (2 inputs) for internal nodes

### GhostNullifierRegistry

Enforces one-time reveal semantics:

- O(1) lookup and insertion
- Permanent storage (nullifiers never removed)
- Called after ZK proof verification

### GhostRedemptionVerifier

Groth16 proof verifier using EIP-197 precompiles:

- Verifies public inputs including root and nullifier
- ~220,000 gas per verification
- Verification key embedded in bytecode

## Privacy Flow

### Vanish (Commit)

```text
User                    GhostVault              CommitmentTree
  │                         │                         │
  │  1. Generate:           │                         │
  │     - secret            │                         │
  │     - nullifierSecret   │                         │
  │     - blinding          │                         │
  │                         │                         │
  │  2. Compute commitment: │                         │
  │     Poseidon5(secret,   │                         │
  │     nullifierSecret,    │                         │
  │     tokenId, amount,    │                         │
  │     blinding)           │                         │
  │                         │                         │
  │  3. vanish(token,       │                         │
  │     amount, commitment) │                         │
  │ ───────────────────────▶│                         │
  │                         │  4. recordCommitment()  │
  │                         │ ───────────────────────▶│
  │                         │                         │
  │                         │  5. Emit CommitmentAdded│
  │                         │ ◀───────────────────────│
  │                         │                         │
  │  6. Save voucher file   │                         │
  │     (secret, nullifier, │                         │
  │      amount)            │                         │
```

### Summon (Reveal)

```text
User                    GhostVault              Verifier       NullifierRegistry
  │                         │                      │                  │
  │  1. Build Merkle proof  │                      │                  │
  │     from indexed events │                      │                  │
  │                         │                      │                  │
  │  2. Generate ZK proof   │                      │                  │
  │     (groth16.fullProve) │                      │                  │
  │                         │                      │                  │
  │  3. summon(proof,       │                      │                  │
  │     inputs)             │                      │                  │
  │ ───────────────────────▶│                      │                  │
  │                         │  4. verifyProof()    │                  │
  │                         │ ────────────────────▶│                  │
  │                         │                      │                  │
  │                         │  5. record nullifier │                  │
  │                         │ ─────────────────────────────────────▶│
  │                         │                      │                  │
  │                         │  6. execute bound    │                  │
  │                         │     application logic│                  │
```

## Cryptographic Primitives

### Poseidon Hash

- **T3 (2 inputs)**: Merkle tree internal nodes
- **T6 (5 inputs)**: Commitment generation (off-chain)

### Commitment Scheme

```text
commitment = Poseidon5(
    secret,
    nullifierSecret,
    tokenId,
    amount,
    blinding
)
```

### Nullifier Derivation

```text
nullifier = Poseidon3(
    Poseidon2(nullifierSecret, commitment),
    leafIndex
)
```

## Deployed Contracts (Reference Implementation)

| Contract | Address |
|----------|---------|
| GhostVault | `0x7d6A02f4B7851F73Dcf017aF892e293a10502379` |
| GhostCommitmentTree | `0x9226FdDBe60CCce650b16C92D61801724516bc68` |
| GhostRedemptionVerifier | `0xD70E783Dfd1A00ec54fE635025f441F65bf12dA0` |

**Chain ID**: 47474

## Gas Costs

| Operation | Approximate Gas |
|-----------|-----------------|
| Vanish | ~150,000 |
| Summon (full) | ~300,000 |
| Summon (partial) | ~350,000 |
| Root Update | ~50,000 |

## Design Decisions

### Off-chain Tree, On-chain Roots

The full Merkle tree is maintained by off-chain indexers. Only roots are stored on-chain. This provides:

- **Gas Efficiency**
- **Scalability**
- **Minimal On-chain State**

### Root History

100 historical roots are maintained to support concurrent proof generation.

### Poseidon over Pedersen

Poseidon is circuit-friendly and reduces constraint count in zero-knowledge proofs.
