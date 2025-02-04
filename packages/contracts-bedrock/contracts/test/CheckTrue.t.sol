// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from "forge-std/Test.sol";
import { CheckTrue } from "../periphery/drippie/dripchecks/CheckTrue.sol";

/// @title  CheckTrueTest
/// @notice Ensures that the CheckTrue DripCheck contract always returns true.
contract CheckTrueTest is Test {
    /// @notice An instance of the CheckTrue contract.
    CheckTrue c;

    /// @notice Deploy the `CheckTrue` contract.
    function setUp() external {
        c = new CheckTrue();
    }

    /// @notice Fuzz the `check` function and assert that it always returns true.
    function testFuzz_always_true_succeeds(bytes memory input) external {
        assertEq(c.check(input), true);
    }
}
