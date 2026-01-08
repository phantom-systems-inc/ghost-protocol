# Ghost Protocol Circuits

ZK-SNARK circuits for Ghost Protocol using Circom and Groth16.

## License

These circuits are licensed under the [Business Source License 2.0](../LICENSE-CIRCUITS).

- **Permitted**: Security research, auditing, education, personal non-commercial use
- **Not Permitted**: Deploying competing privacy protocols
- **Change Date**: January 1, 2029 (converts to MIT)

## Circuits

### ghostcoinV4Simple.circom

Main redemption circuit for full withdrawals.

**Public Inputs (6):**
1. `nullifierHash` - Prevents double-spending
2. `recipient` - Bound to prevent front-running
3. `root` - Merkle root being proven against
4. `amount` - Withdrawal amount

**Private Inputs:**
- `salt` - Random 254-bit value
- `nullifier` - Secret nullifier preimage
- `pathElements[20]` - Merkle proof siblings
- `pathIndices[20]` - Merkle proof path (0/1)

### ghostcoinV4Partial.circom

Extended circuit supporting partial withdrawals with change commitments.

## Compilation

Requires [Circom](https://docs.circom.io/getting-started/installation/) v2.1+.

```bash
cd src

# Compile to R1CS and WASM
circom ghostcoinV4Simple.circom --r1cs --wasm --sym

# The output files:
# - ghostcoinV4Simple.r1cs (constraint system)
# - ghostcoinV4Simple_js/ (WASM witness generator)
# - ghostcoinV4Simple.sym (symbol file for debugging)
```

## Verification Keys

The `verification_keys/` directory contains the public verification keys:

- `verification_key.json` - For ghostcoinV4Simple
- `verification_key_partial.json` - For ghostcoinV4Partial

These are embedded in the on-chain verifier contracts.

## Proving Keys

**Proving keys (.zkey) are NOT included in this repository.**

The proving keys are required to generate proofs but are not published for security reasons. If you need to generate proofs, you must either:

1. Use the official Ghost Protocol frontend (which loads proving keys at runtime)
2. Contact the team for proving key access

## Trusted Setup

See [../docs/TRUSTED_SETUP.md](../docs/TRUSTED_SETUP.md) for details on the ceremony.

## Dependencies

The circuits use [circomlib](https://github.com/iden3/circomlib):

```bash
npm install circomlib
```

Required circomlib components:
- `poseidon.circom` - Poseidon hash function
- `comparators.circom` - Comparison circuits
