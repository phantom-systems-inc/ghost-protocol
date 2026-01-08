// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGhostRedemptionVerifier} from "../interfaces/IGhostRedemptionVerifier.sol";

/// @title GhostRedemptionVerifier
/// @notice Groth16 proof verifier for Ghost Protocol redemptions using EIP-197 bn256 pairing
/// @dev This contract verifies ZK proofs that demonstrate:
///      1. Knowledge of commitment preimage (secret, nullifier_secret, token_id, amount, blinding)
///      2. Merkle tree membership (commitment exists in tree at claimed root)
///      3. Correct nullifier derivation (prevents double-spend)
///      4. Amount conservation (withdraw_amount <= original_amount)
///
///      Public inputs (6 total):
///        0. merkle_root - Tree root being proven against
///        1. nullifier - Derived from commitment (prevents double-spend)
///        2. withdraw_amount - Amount being withdrawn
///        3. recipient - Bound in proof (front-running protection)
///        4. change_commitment - New commitment for remaining funds (0 if full withdrawal)
///        5. token_id_hash - Public token identifier
///
///      Gas cost: ~220,000 per verification
contract GhostRedemptionVerifier is IGhostRedemptionVerifier {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev BN254 scalar field modulus
    uint256 internal constant Q_MOD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    /// @dev BN254 base field modulus
    uint256 internal constant P_MOD =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;

    /// @notice Number of public inputs for the redemption circuit
    uint256 public constant override NUM_PUBLIC_INPUTS = 6;

    /*//////////////////////////////////////////////////////////////
                            VERIFICATION KEY
    //////////////////////////////////////////////////////////////*/

    // All VK constants are embedded directly in bytecode (no storage needed)
    // This is more gas efficient for CREATE2 deployments

    /// @dev G1 point representing alpha (from trusted setup)
    uint256 internal constant ALPHA1_X = 16832678449163003211042012304505523326644941469645115004625374414630591168773;
    uint256 internal constant ALPHA1_Y = 3877393360101169052789862960401493649906503154669091902052552220856412082284;

    /// @dev G2 point representing beta (from trusted setup)
    /// @dev Stored as [real, imag] per snarkjs template convention, matching EIP-197 format
    uint256 internal constant BETA2_X1 = 12737307702272086920176334868990142907423414408036737497238102614505388660520;
    uint256 internal constant BETA2_X2 = 18861091154298193269093807031381953730918502424538536902455747644101261903331;
    uint256 internal constant BETA2_Y1 = 11306404237529859619852337423774023573416913502522734121980402275532757990254;
    uint256 internal constant BETA2_Y2 = 11008414864035410688664949432550950460010866110483417611959076551138596373219;

    /// @dev G2 point representing gamma (from trusted setup)
    uint256 internal constant GAMMA2_X1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant GAMMA2_X2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant GAMMA2_Y1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 internal constant GAMMA2_Y2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;

    /// @dev G2 point representing delta (from trusted setup)
    uint256 internal constant DELTA2_X1 = 7193262008020100997230192131909791588632787714684365037420938985555803087546;
    uint256 internal constant DELTA2_X2 = 20956943095236624114418461284512635234295670875407875814194481502303416983009;
    uint256 internal constant DELTA2_Y1 = 15573437350209656071604369691323899447813059806336040655254934808622499115810;
    uint256 internal constant DELTA2_Y2 = 11609918108317601039408103781452267182222916628549255537710246032480408777792;

    /// @dev IC (public input commitments) - length = NUM_PUBLIC_INPUTS + 1
    /// @dev All IC points as constants for gas efficiency
    uint256 internal constant IC0_X = 12959684094631005793397665087697487629997984983261761100972426203021209270474;
    uint256 internal constant IC0_Y = 7381673115837854728551083396474646354364674674614164758305878980888875373441;

    uint256 internal constant IC1_X = 19751740086741541637436609061707525277468661187445550255274691430485865024832;
    uint256 internal constant IC1_Y = 15362986155915528440587825580828964082750874825724941472511178108355059912267;

    uint256 internal constant IC2_X = 6410194969883296241509185681118875297409077507969726592520828039466324034528;
    uint256 internal constant IC2_Y = 3780435094639821110887014008584953595714928466361885475353320693816194489479;

    uint256 internal constant IC3_X = 12354532015231834490218058083565660055556358937532793766042184674659688457232;
    uint256 internal constant IC3_Y = 12308790406264718790842970313135325983262473937787680307449070155115456878711;

    uint256 internal constant IC4_X = 13702451083171875229726867336315206093422881582560395973097048114233209735211;
    uint256 internal constant IC4_Y = 409853159045041122991884958941800480291690197240847659320540747329608486542;

    uint256 internal constant IC5_X = 7248141822994076106205125927013572116946999549399375467696937800954469205166;
    uint256 internal constant IC5_Y = 5935346693281522886760744319276757306725156034286825083099143087129243651464;

    uint256 internal constant IC6_X = 13635716836406754226614133690132741070098517531377377452863274513602099955140;
    uint256 internal constant IC6_Y = 10247435384448461629643659600730052277158553416395535506200862771084527986277;

    /*//////////////////////////////////////////////////////////////
                          VERIFICATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IGhostRedemptionVerifier
    function verifyProof(
        uint256[8] calldata proof,
        uint256[6] calldata publicInputs
    ) external view override returns (bool isValid) {
        // Validate inputs are in the scalar field
        for (uint256 i = 0; i < 6; i++) {
            if (publicInputs[i] >= Q_MOD) revert InvalidInputValue();
        }

        // Compute the linear combination of IC points with public inputs
        // vk_x = IC[0] + sum(publicInputs[i] * IC[i+1])
        uint256 vk_x;
        uint256 vk_y;
        (vk_x, vk_y) = _computeVkX(publicInputs);

        // Verify the pairing equation:
        // e(A, B) = e(alpha, beta) * e(vk_x, gamma) * e(C, delta)
        // Which is equivalent to checking:
        // e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e(C, delta) == 1
        isValid = _verifyPairing(
            proof[0], proof[1], // A
            proof[2], proof[3], proof[4], proof[5], // B
            proof[6], proof[7], // C
            vk_x, vk_y
        );

        return isValid;
    }

    /// @inheritdoc IGhostRedemptionVerifier
    function verifyRedemptionProof(
        uint256[8] calldata proof,
        bytes32 root,
        bytes32 nullifier,
        uint256 amount,
        address recipient,
        bytes32 changeCommitment,
        bytes32 tokenId
    ) external view override returns (bool isValid) {
        uint256[6] memory publicInputs;
        publicInputs[0] = uint256(root);
        publicInputs[1] = uint256(nullifier);
        publicInputs[2] = amount;
        publicInputs[3] = uint256(uint160(recipient));
        publicInputs[4] = uint256(changeCommitment);
        publicInputs[5] = uint256(tokenId);

        return this.verifyProof(proof, publicInputs);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Compute vk_x = IC[0] + sum(publicInputs[i] * IC[i+1])
    function _computeVkX(uint256[6] calldata publicInputs)
        internal
        view
        returns (uint256 x, uint256 y)
    {
        // Start with IC[0]
        x = IC0_X;
        y = IC0_Y;

        // IC points array for iteration
        uint256[2][6] memory icPoints = [
            [IC1_X, IC1_Y],
            [IC2_X, IC2_Y],
            [IC3_X, IC3_Y],
            [IC4_X, IC4_Y],
            [IC5_X, IC5_Y],
            [IC6_X, IC6_Y]
        ];

        // Add publicInputs[i] * IC[i+1] for each public input
        for (uint256 i = 0; i < 6; i++) {
            if (publicInputs[i] != 0) {
                (uint256 px, uint256 py) = _ecMul(icPoints[i][0], icPoints[i][1], publicInputs[i]);
                (x, y) = _ecAdd(x, y, px, py);
            }
        }

        return (x, y);
    }

    /// @dev Verify the pairing equation using EIP-197 precompile
    function _verifyPairing(
        uint256 aX,
        uint256 aY,
        uint256 bX1,
        uint256 bX2,
        uint256 bY1,
        uint256 bY2,
        uint256 cX,
        uint256 cY,
        uint256 vkX,
        uint256 vkY
    ) internal view returns (bool) {
        // Prepare pairing input: 4 pairs of (G1, G2) points
        // Check: e(-A, B) * e(alpha, beta) * e(vk_x, gamma) * e(C, delta) == 1

        uint256[24] memory input;

        // Pair 1: (-A, B) - negate A.y
        // HIGH-7 fix: Handle aY == 0 case (P_MOD - 0 = P_MOD which is invalid)
        input[0] = aX;
        input[1] = aY == 0 ? 0 : P_MOD - aY; // Negate Y coordinate safely
        // B coordinates are passed from UI in precompile-ready format [imag, real]
        input[2] = bX1;
        input[3] = bX2;
        input[4] = bY1;
        input[5] = bY2;

        // Pair 2: (alpha, beta)
        input[6] = ALPHA1_X;
        input[7] = ALPHA1_Y;
        input[8] = BETA2_X1;
        input[9] = BETA2_X2;
        input[10] = BETA2_Y1;
        input[11] = BETA2_Y2;

        // Pair 3: (vk_x, gamma)
        input[12] = vkX;
        input[13] = vkY;
        input[14] = GAMMA2_X1;
        input[15] = GAMMA2_X2;
        input[16] = GAMMA2_Y1;
        input[17] = GAMMA2_Y2;

        // Pair 4: (C, delta)
        input[18] = cX;
        input[19] = cY;
        input[20] = DELTA2_X1;
        input[21] = DELTA2_X2;
        input[22] = DELTA2_Y1;
        input[23] = DELTA2_Y2;

        // Call pairing precompile (address 8)
        uint256[1] memory result;
        bool success;
        assembly {
            success := staticcall(gas(), 8, input, 768, result, 32)
        }

        if (!success) revert PairingFailed();

        return result[0] == 1;
    }

    /// @dev Elliptic curve point addition using EIP-196 precompile (address 6)
    function _ecAdd(
        uint256 x1,
        uint256 y1,
        uint256 x2,
        uint256 y2
    ) internal view returns (uint256 x, uint256 y) {
        uint256[4] memory input;
        input[0] = x1;
        input[1] = y1;
        input[2] = x2;
        input[3] = y2;

        bool success;
        assembly {
            success := staticcall(gas(), 6, input, 128, input, 64)
        }
        require(success, "EC add failed");

        return (input[0], input[1]);
    }

    /// @dev Elliptic curve scalar multiplication using EIP-196 precompile (address 7)
    function _ecMul(
        uint256 px,
        uint256 py,
        uint256 s
    ) internal view returns (uint256 x, uint256 y) {
        uint256[3] memory input;
        input[0] = px;
        input[1] = py;
        input[2] = s;

        bool success;
        assembly {
            success := staticcall(gas(), 7, input, 96, input, 64)
        }
        require(success, "EC mul failed");

        return (input[0], input[1]);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get verification key components
    /// @return alpha1 Alpha G1 point
    /// @return beta2 Beta G2 point
    /// @return gamma2 Gamma G2 point
    /// @return delta2 Delta G2 point
    function getVerificationKey()
        external
        pure
        returns (
            uint256[2] memory alpha1,
            uint256[4] memory beta2,
            uint256[4] memory gamma2,
            uint256[4] memory delta2
        )
    {
        alpha1 = [ALPHA1_X, ALPHA1_Y];
        beta2 = [BETA2_X1, BETA2_X2, BETA2_Y1, BETA2_Y2];
        gamma2 = [GAMMA2_X1, GAMMA2_X2, GAMMA2_Y1, GAMMA2_Y2];
        delta2 = [DELTA2_X1, DELTA2_X2, DELTA2_Y1, DELTA2_Y2];
    }

    /// @inheritdoc IGhostRedemptionVerifier
    function getIC(uint256 index) external pure override returns (uint256 x, uint256 y) {
        if (index == 0) return (IC0_X, IC0_Y);
        if (index == 1) return (IC1_X, IC1_Y);
        if (index == 2) return (IC2_X, IC2_Y);
        if (index == 3) return (IC3_X, IC3_Y);
        if (index == 4) return (IC4_X, IC4_Y);
        if (index == 5) return (IC5_X, IC5_Y);
        if (index == 6) return (IC6_X, IC6_Y);
        revert("Index out of bounds");
    }
}
