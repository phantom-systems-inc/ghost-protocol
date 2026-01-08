# Trusted Setup

Ghost Protocol uses Groth16 ZK-SNARKs, which require a trusted setup ceremony. This document describes the current setup and its security implications.

## Overview

Groth16 trusted setup has two phases:

1. **Phase 1 (Powers of Tau)**: Universal, can be reused across circuits
2. **Phase 2 (Circuit-specific)**: Generates proving/verification keys for specific circuit

## Current Setup

### Phase 1: Powers of Tau

We use the publicly available Powers of Tau from the zkEVM ceremony:

- **Source**: `https://storage.googleapis.com/zkevm/ptau/`
- **File**: `powersOfTau28_hez_final_15.ptau`
- **Ceremony**: Polygon zkEVM (Hermez) community ceremony
- **Participants**: 54+ contributors

This Phase 1 setup is widely trusted and used by many production ZK systems.

### Phase 2: Circuit-Specific Setup

**Current Status**: Single contributor

The Phase 2 setup for Ghost Protocol's redemption circuit was performed with a single contributor. This is a **known limitation**.

#### Security Implications

With a single-contributor Phase 2:

1. **Privacy is NOT affected**: Even a compromised setup cannot break transaction privacy
2. **Soundness MAY be affected**: The setup contributor could potentially create fake proofs
3. **In practice**: The contributor would need to have saved the "toxic waste" (random values) from the ceremony

#### Mitigation

- The single contributor is the Phantom Systems team
- We did not retain the toxic waste
- A multi-party ceremony is planned for future versions

## Verification

You can verify the setup locally:

### Verify Phase 1 (Powers of Tau)

```bash
# Download the ptau file
wget https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_15.ptau

# Verify the ceremony (requires snarkjs)
snarkjs powersoftau verify powersOfTau28_hez_final_15.ptau
```

### Verify Circuit Compilation

```bash
cd circuits/src

# Compile the circuit
circom ghostcoinV4Simple.circom --r1cs --wasm --sym

# The r1cs file contains the constraint system
# This can be independently verified
```

### Verify Verification Key

The verification key in `circuits/verification_keys/verification_key.json` should match the constants embedded in `GhostRedemptionVerifier.sol`.

## Future Plans

We are planning a proper multi-party ceremony (MPC) for Phase 2:

1. **Open Participation**: Anyone can contribute to the ceremony
2. **Security Guarantee**: Only ONE honest participant is needed for soundness
3. **Transparency**: All contributions will be logged and verifiable
4. **Timeline**: TBD

### How MPC Ceremonies Work

In a multi-party ceremony:
- Each participant adds randomness to the proving key
- Participants destroy their random input after contributing
- If ANY participant destroys their input, the setup is secure
- Even if N-1 participants collude, the one honest participant ensures security

## Q&A

### Q: Can a compromised setup steal funds?

No. Even with a compromised trusted setup:
- Transaction privacy cannot be broken
- The attacker cannot see who sent what to whom
- They would need to create a fake proof to steal funds

### Q: Should I wait for the MPC ceremony?

For most use cases, the current setup is acceptable:
- The Phantom Systems team performed the setup and did not retain toxic waste
- Privacy guarantees are unaffected
- For high-value applications, you may want to wait for MPC

### Q: Is this similar to Tornado Cash?

Yes. Tornado Cash also launched with a limited initial ceremony and later performed a full MPC ceremony with thousands of participants.

## References

- [Groth16 Paper](https://eprint.iacr.org/2016/260.pdf)
- [Powers of Tau Ceremony](https://github.com/weijiekoh/perpetualpowersoftau)
- [snarkjs Documentation](https://github.com/iden3/snarkjs)
- [Trusted Setup Explanation](https://vitalik.eth.limo/general/2022/03/14/trustedsetup.html)
