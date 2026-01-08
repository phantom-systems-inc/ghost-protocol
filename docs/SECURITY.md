# Security Model

Ghost Protocol is a commit-once, reveal-once privacy primitive designed to make certain classes of surveillance and data extraction mathematically impossible.

This document describes the security model, threat assumptions, and known limitations of the protocol and its reference implementation.

## Overview

Ghost Protocol allows data or value to be committed without being stored, and revealed exactly once, or never.

Security is achieved not by encrypting stored data, but by ensuring the data never exists in a retrievable form. On-chain state consists only of cryptographic commitments and nullifiers. All meaningful information is held off-chain by the bearer of the secret.

Ghostcoin token transfers are one application of this model, but the security properties described here apply to any system built on Ghost Protocol.

## Threat Model

### What Ghost Protocol Protects Against

1. **Post-hoc Data Recovery**
   - No committed data is stored on-chain
   - There is nothing to decrypt, subpoena, or leak later

2. **Linkability**
   - Commit and reveal events cannot be cryptographically linked
   - Observers cannot determine which commitment corresponds to which reveal

3. **Double Use**
   - Nullifiers ensure each commitment can be revealed exactly once
   - Replay or duplication is cryptographically prevented

4. **Forgery**
   - Only commitments recorded in the commitment structure can be revealed
   - Zero-knowledge proofs enforce correctness without revealing secrets

5. **Unauthorized Revelation**
   - Only the holder of the original secret can successfully reveal a commitment

### Trust Assumptions

#### Cryptographic Assumptions

- The discrete logarithm problem on BN254 is hard
- Poseidon is collision-resistant
- Groth16 proofs are sound under standard knowledge assumptions

If any of these assumptions fail, the protocol’s guarantees may degrade.

#### Trusted Setup

- Phase 1 uses a public Powers of Tau ceremony
- Phase 2 parameters are described in [TRUSTED_SETUP.md](./TRUSTED_SETUP.md)

A compromised Phase 2 setup could allow the creation of invalid proofs, but does not enable recovery of committed data, because no data exists to recover.

#### Commitment Structure Operator

- The operator responsible for updating commitment roots can:
  - Delay root publication (denial of service)
- The operator cannot:
  - Steal value
  - Reveal commitments
  - Forge valid reveals

Users can independently verify roots by indexing commitment events.

#### Execution Environment

The current reference implementation runs on a dedicated Avalanche Subnet Layer 1 (Umbraline Testnet). Validator-level observation and execution assumptions are those of the underlying Avalanche consensus. These considerations affect transaction visibility and availability, but do not weaken the protocol’s non-existence-based privacy guarantees.

## What Ghost Protocol Does NOT Protect Against

Ghost Protocol makes strong guarantees about data non-existence, but it does not eliminate all forms of information leakage.

1. **Metadata Leakage**
   - Timing, transaction ordering, gas usage, and amounts may leak information

2. **Network-Level Correlation**
   - IP addresses, RPC endpoints, or client fingerprinting may correlate actions

3. **Amount Fingerprinting**
   - Unique or uncommon values may be distinguishable

4. **Validator Observation**
   - Validators observe all transactions, though they cannot access committed data

Ghost Protocol deliberately does not attempt to solve these problems. It focuses on eliminating stored data, not all observable behavior.

## Security Features

### Contract-Level Security

- Reentrancy protection on all state-changing functions
- Checks-Effects-Interactions pattern enforced
- Custom errors for clarity and gas efficiency
- Explicit access control for administrative actions
- Rate limiting to reduce abuse and denial-of-service vectors

### Cryptographic Enforcement

- Field validation for all public inputs
- Commitment and nullifier validation
- Permanent nullifier storage for one-time enforcement
- Root history maintained for concurrent proof generation

## Known Limitations

1. **Single-Contributor Phase 2 Setup**
   - Current setup has a single contributor
   - A multi-party ceremony is planned

2. **Root Update Latency**
   - Commitments are not immediately usable for reveal

3. **Fixed Commitment Capacity**
   - Tree depth is fixed at 20 levels (~1M commitments)

4. **Irrecoverable Loss**
   - Loss of secrets results in permanent loss by design
   - There are no recovery or override mechanisms

## Responsible Disclosure

If you discover a vulnerability:

1. Do not open a public GitHub issue
2. Email: hello@ghostcoin.com
3. Include a description, reproduction steps, and potential impact

We aim to respond within 48 hours.

## Bug Bounty

A formal bug bounty program is planned. Until then, responsible disclosures may be rewarded at our discretion based on severity.

### Severity Guidelines

| Severity | Description |
|--------|-------------|
| Critical | Fund loss or reveal forgery |
| High | Protocol-level denial of service |
| Medium | Limited exploitation or griefing |
| Low | Best practice or hygiene issues |

## Audit Status

This implementation has undergone internal review. External audits will be published when available.

## Contact

hello@ghostcoin.com  
