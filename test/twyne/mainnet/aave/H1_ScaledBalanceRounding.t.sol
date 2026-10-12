// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AaveTestBase.t.sol";

/// @title H1_ScaledBalanceRounding
/// @notice Hypothesis H1: rounding in rebalanceATokens_CV may leave CV with
///         fewer aTokens than totalAssetsDepositedOrReserved.
///         If so, _isNotExternallyLiquidated() returns false → vault blocked.
///
/// Fix v2: deposit(1) reverted with StaticATokenInvalidZeroShares at rate > RAY.
/// Minimum valid deposit = ceil(rate / RAY). Use 2 as safe floor.
/// Added deterministic adversarial case targeting frac > 0.5.
contract H1_ScaledBalanceRounding is AaveTestBase {
    uint256 constant RAY = 1e27;

    function setUp() public override {
        super.setUp();
    }

    // ---------------------------------------------------------------------
    // Test 1: deposits at different indexes
    // ---------------------------------------------------------------------
    function test_H1_depositsAtDifferentIndexes() public {
        address vault = _createAaveVault();

        // All amounts are well above minimum-valid deposit (>= 2 wei at any rate).
        uint[5] memory amounts = [
            uint(1e9 + 1),
            uint(3e9 + 7),
            uint(9e9 + 13),
            uint(27e9 + 3),
            uint(1e9 + 1)
        ];

        for (uint i = 0; i < amounts.length; i++) {
            _depositToVault(vault, amounts[i]);
            _assertInvariant(vault, "after deposit");
        }

        uint[4] memory jumps = [uint(3 hours), uint(11 hours), uint(1 days + 7), uint(5 days)];

        for (uint i = 0; i < jumps.length; i++) {
            skip(jumps[i]);
            _accrueAave();
            _assertInvariant(vault, "after time jump");
        }

        // Partial withdraw then re-deposit to force rebalanceATokens_CV
        _withdrawFromVault(vault, 3e9 + 5);
        _assertInvariant(vault, "after withdraw");

        _depositToVault(vault, 7e9 + 11);
        _assertInvariant(vault, "after redeposit");

        skip(2 days);
        _accrueAave();
        _assertInvariant(vault, "final");
    }

    // ---------------------------------------------------------------------
    // Test 2: withdraws at different indexes (already passing — keep as-is)
    // ---------------------------------------------------------------------
    function test_H1_withdrawsAtDifferentIndexes() public {
        address vault = _createAaveVault();

        _depositToVault(vault, 5e18);
        _assertInvariant(vault, "initial deposit");

        uint[6] memory withdrawals = [
            uint(1e15 + 1),
            uint(1e15 + 7),
            uint(1e15 + 13),
            uint(1e15 + 3),
            uint(1e15 + 11),
            uint(1e15 + 5)
        ];

        for (uint i = 0; i < withdrawals.length; i++) {
            _withdrawFromVault(vault, withdrawals[i]);
            _assertInvariant(vault, "after withdraw");

            skip(6 hours + i);
            _accrueAave();
        }
    }

    // ---------------------------------------------------------------------
    // Test 3: deterministic adversarial amount
    // ---------------------------------------------------------------------
    /// @dev Target: d · r / RAY has fractional part > 0.5, so half-up rounding
    ///      on mint yields floor(d + 0.5 - s/r) = d - 1 → actual = shares - 1.
    ///      Choose d = floor(0.75 · RAY / r) so that s/r ≈ 0.75 > 0.5.
    function test_H1_adversarialAmount() public {
        address vault = _createAaveVault();

        uint256 r = IAaveV3Pool(POOL).getReserveNormalizedIncome(WETH);

        // d = floor(0.75 · RAY / r). At r ≈ RAY (1.0), d ≈ 0.75 · RAY = 7.5e26.
        // At r ≈ 1.067 · RAY, d ≈ 7.03e26. Well above min-valid deposit.
        uint256 d = (RAY * 75 / 100) * RAY / r;
        require(d > 1, "adversarial d too small");

        emit log_named_uint("rate", r);
        emit log_named_uint("adversarial d", d);

        _depositToVault(vault, d);
        _assertInvariant(vault, "adversarial deposit");
    }

    // ---------------------------------------------------------------------
    // Internals — wire to your AaveTestBase helpers
    // ---------------------------------------------------------------------

    function _assertInvariant(address vault, string memory ctx) internal view {
        uint accounted = IAaveV3CollateralVault(vault).totalAssetsDepositedOrReserved();
        uint scaled = IAToken(IAaveV3CollateralVault(vault).aToken()).scaledBalanceOf(vault);

        emit log_named_uint(string(abi.encodePacked("accounted @ ", ctx)), accounted);
        emit log_named_uint(string(abi.encodePacked("scaled    @ ", ctx)), scaled);

        if (scaled < accounted) {
            emit log(string(abi.encodePacked("H1 BROKEN @ ", ctx)));
        }
        assertGe(scaled, accounted, "H1: scaledBalanceOf < totalAssetsDepositedOrReserved");
    }

    // These are placeholders — replace with your real AaveTestBase helpers:
    // _createAaveVault(), _depositToVault(), _withdrawFromVault(), _accrueAave()
    function _createAaveVault() internal returns (address) {
        // TODO: hook into AaveTestBase
        revert("wire _createAaveVault to AaveTestBase");
    }

    function _depositToVault(address vault, uint256 amount) internal {
        // TODO: hook into AaveTestBase
        revert("wire _depositToVault to AaveTestBase");
    }

    function _withdrawFromVault(address vault, uint256 amount) internal {
        // TODO: hook into AaveTestBase
        revert("wire _withdrawFromVault to AaveTestBase");
    }

    function _accrueAave() internal {
        // TODO: hook into AaveTestBase
        revert("wire _accrueAave to AaveTestBase");
    }
}
