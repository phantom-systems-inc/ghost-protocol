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

// Simple circuit for GhostcoinV4Fixed that matches the expected 4 public inputs
template GhostcoinV4Simple() {
    // Private inputs
    signal input salt;
    signal input nullifier;
    signal input pathElements[20];
    signal input pathIndices[20];
    
    // Public inputs matching GhostcoinV4Fixed.sol expectations:
    // [nullifierHash, recipient, root, amount]
    signal input nullifierHash; // public
    signal input recipient;     // public  
    signal input root;          // public
    signal input amount;        // public
    
    // Internal signals
    signal commitmentHash;
    
    // Verify nullifier hash matches
    component nullifierHasher = Poseidon(1);
    nullifierHasher.inputs[0] <== nullifier;
    nullifierHash === nullifierHasher.out;
    
    // Generate commitment = poseidon(salt, amount, nullifier)
    component commitmentHasher = Poseidon(3);
    commitmentHasher.inputs[0] <== salt;
    commitmentHasher.inputs[1] <== amount;
    commitmentHasher.inputs[2] <== nullifier;
    commitmentHash <== commitmentHasher.out;
    
    // Simple Merkle tree verification
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
    
    // Verify the computed root matches
    root === currentHash[20];
    
    // Ensure amount is not zero
    component isZero = IsZero();
    isZero.in <== amount;
    isZero.out === 0;
}

// Main component with public inputs in the order expected by contract
component main {public [nullifierHash, recipient, root, amount]} = GhostcoinV4Simple();