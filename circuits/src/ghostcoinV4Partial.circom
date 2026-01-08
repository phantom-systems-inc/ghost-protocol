pragma circom 2.1.6;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/comparators.circom";

// Helper template to switch order of inputs based on selector
template Mux2() {
    signal input sel;
    signal input in[2];
    signal output out[2];

    signal aux[2];

    aux[0] <== (in[1] - in[0]) * sel;
    out[0] <== in[0] + aux[0];

    aux[1] <== (in[0] - in[1]) * sel;
    out[1] <== in[1] + aux[1];
}

// Circuit for GhostcoinV4 with partial redemption support
// Allows redeeming part of a voucher and creating a change voucher
template GhostcoinV4Partial() {
    // Private inputs (never revealed on-chain)
    signal input salt;              // Salt for original voucher
    signal input nullifier;         // Nullifier for original voucher
    signal input totalAmount;       // Total amount in original voucher
    signal input pathElements[20];  // Merkle proof path
    signal input pathIndices[20];   // Merkle proof indices

    // Private inputs for change voucher (only used if partial redemption)
    signal input newSalt;           // Salt for change voucher
    signal input newNullifier;      // Nullifier for change voucher

    // Public inputs (verified on-chain)
    signal input nullifierHash;     // Hash of original nullifier
    signal input recipient;         // Address receiving the redeemed tokens
    signal input root;              // Merkle tree root
    signal input redeemAmount;      // Amount to redeem (≤ totalAmount)
    signal input changeCommitment;  // Commitment for change voucher (0 if full redemption)

    // Internal signals
    signal commitmentHash;
    signal changeAmount;
    signal computedChangeCommitment;

    // 1. Verify nullifier hash matches
    component nullifierHasher = Poseidon(1);
    nullifierHasher.inputs[0] <== nullifier;
    nullifierHash === nullifierHasher.out;

    // 2. Generate original commitment = poseidon(salt, totalAmount, nullifier)
    component commitmentHasher = Poseidon(3);
    commitmentHasher.inputs[0] <== salt;
    commitmentHasher.inputs[1] <== totalAmount;
    commitmentHasher.inputs[2] <== nullifier;
    commitmentHash <== commitmentHasher.out;

    // 3. Verify redeemAmount <= totalAmount
    component lessEqCheck = LessEqThan(252);
    lessEqCheck.in[0] <== redeemAmount;
    lessEqCheck.in[1] <== totalAmount;
    lessEqCheck.out === 1;

    // 4. Compute change amount
    changeAmount <== totalAmount - redeemAmount;

    // 5. Compute expected change commitment
    // If changeAmount > 0: changeCommitment should be poseidon(newSalt, changeAmount, newNullifier)
    // If changeAmount == 0: changeCommitment should be 0
    component changeCommitmentHasher = Poseidon(3);
    changeCommitmentHasher.inputs[0] <== newSalt;
    changeCommitmentHasher.inputs[1] <== changeAmount;
    changeCommitmentHasher.inputs[2] <== newNullifier;

    // Check if changeAmount is zero
    component isZeroChange = IsZero();
    isZeroChange.in <== changeAmount;

    // If changeAmount == 0, computedChangeCommitment should be 0
    // If changeAmount > 0, computedChangeCommitment should be hash output
    // Formula: computedChangeCommitment = (1 - isZero) * hashOutput + isZero * 0
    computedChangeCommitment <== (1 - isZeroChange.out) * changeCommitmentHasher.out;

    // 6. Verify provided changeCommitment matches computed value
    changeCommitment === computedChangeCommitment;

    // 7. Verify Merkle tree proof - original commitment is in the tree
    component hashers[20];
    component mux[20];
    signal currentHash[21];
    currentHash[0] <== commitmentHash;

    for (var i = 0; i < 20; i++) {
        hashers[i] = Poseidon(2);

        // Use a multiplexer to select the order
        mux[i] = Mux2();
        mux[i].sel <== pathIndices[i];
        mux[i].in[0] <== currentHash[i];
        mux[i].in[1] <== pathElements[i];

        hashers[i].inputs[0] <== mux[i].out[0];
        hashers[i].inputs[1] <== mux[i].out[1];
        currentHash[i + 1] <== hashers[i].out;
    }

    // 8. Verify the computed root matches the provided root
    root === currentHash[20];

    // 9. Ensure redeemAmount is not zero
    component isZeroRedeem = IsZero();
    isZeroRedeem.in <== redeemAmount;
    isZeroRedeem.out === 0;
}

// Main component with public inputs in the order expected by contract
// Public inputs: [nullifierHash, recipient, root, redeemAmount, changeCommitment]
component main {public [nullifierHash, recipient, root, redeemAmount, changeCommitment]} = GhostcoinV4Partial();
