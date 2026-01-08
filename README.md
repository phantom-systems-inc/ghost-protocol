# Ghost Protocol

A commit-once, reveal-once privacy primitive based on cryptographic non-existence.

## Overview

Ghost Protocol is a general-purpose privacy system for digital value and information.

Instead of hiding data through encryption or obfuscation, Ghost Protocol eliminates data entirely until the moment it is revealed. Commitments prove that something exists without storing what it is. Revelations are final, verifiable, and can occur exactly once.

This creates a new privacy model where absence, not secrecy, is the security property.

Ghostcoin is one application of the protocol. The protocol itself is designed to support many categories of privacy-native systems beyond tokens.

## For Developers

Ghost Protocol is live and ready to build on.

Full developer documentation, contract references, and examples are available here:  
https://docs.umbraline.com

## Core Model

Ghost Protocol enforces a simple rule:

Commit once.  
Reveal once, or never.

Between commitment and revelation, data exists in a provably real but provably inaccessible state. There is nothing to decrypt, nothing to subpoena, and nothing to leak.

If the secret is never revealed, the commitment remains permanently meaningless. This is not a failure mode. It is an intentional outcome.

## What Gets Recorded

On-chain, Ghost Protocol records only:

- Commitments (fixed-size cryptographic hashes)
- Nullifiers (to enforce one-time revelation)

No committed data, secrets, identities, balances, or access logs are ever stored.

Everything meaningful exists off-chain, held only by the bearer of the secret.

## Guarantees

Ghost Protocol provides guarantees that traditional privacy systems cannot:

- **Non-existence over secrecy**  
  No encrypted data is stored. There is nothing to decrypt later.

- **One-time finality**  
  Every commitment can be revealed exactly once. Double use is cryptographically impossible.

- **Unlinkability by design**  
  Commit and reveal events cannot be correlated.

- **Bearer semantics**  
  Whoever holds the secret controls the value or information. Possession is ownership.

## What This Enables

Because Ghost Protocol removes data rather than hiding it, it enables entirely new classes of applications:

- One-time access tokens
- Private credentials that cannot be leaked
- Sealed disclosures and delayed reveals
- Dead-drop style exchanges
- Offline or bearer-held digital value
- Digital artifacts that can only be accessed once

Cryptocurrency is simply the first domain where these guarantees are demonstrated.

## Architecture

At a high level, Ghost Protocol consists of:

- **Commitment storage**  
  An append-only structure for recording commitments

- **Nullifier registry**  
  Enforces one-time revelation and prevents reuse

- **Verification logic**  
  Cryptographically verifies that a reveal matches a prior commitment

The protocol maintains no accounts, balances, or user state.

## Implementation Notes

This repository contains a reference implementation of Ghost Protocol using zero-knowledge proofs.

The current reference implementation runs on a dedicated Avalanche Subnet Layer 1 (Umbraline Testnet), optimized for privacy operations with low, predictable fees and protocol-aligned execution. The protocol itself is chain-agnostic and can be deployed on other execution environments.

The cryptography and contracts are public and verifiable. The protocol makes no trust assumptions beyond the soundness of the underlying primitives.

## Status

Ghost Protocol is functional, early, and evolving.

It is not yet audited or production-hardened. There are no recovery mechanisms. Loss of secrets results in permanent loss by design.

This system prioritizes strong guarantees over convenience.

## License

- Smart contracts: MIT License
- Circuits: Business Source License 2.0 (converts to MIT in 2029)

## Links

Website: https://ghostcoin.com  
Portal: https://portal.ghostcoin.com  
Documentation: https://docs.umbraline.com  
Whitepaper: https://whitepaper.umbraline.com
