// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AaveTestBase.t.sol";
import {IAToken} from "aave-v3/interfaces/IAToken.sol";

/// @title H1_ScaledBalanceRounding
/// @notice Hypothesis H1: rounding in rebalanceATokens_CV may leave CV with
///         fewer aTokens than totalAssetsDepositedOrReserved.
///         If so, _isNotExternallyLiquidated() returns false → vault blocked.
/// @dev Fix v2: deposit(1) reverted with StaticATokenInvalidZeroShares at rate > RAY.
///      Use larger amounts. Added deterministic adversarial case.
contract H1_ScaledBalanceRounding is AaveTestBase {
    uint256 constant RAY = 1e27;

    function setUp() public override {
        super.setUp();
        aave_createCollateralVault(address(aWETHWrapper), 9100);
    }

    // ---------------------------------------------------------------------
    // Test 1: deposits at different indexes (up-direction / mint)
    // ---------------------------------------------------------------------
    function test_H1_depositsAtDifferentIndexes() public {
        uint[5] memory amounts = [
            uint(1e9 + 1),
            uint(3e9 + 7),
            uint(9e9 + 13),
            uint(27e9 + 3),
            uint(1e9 + 1)
        ];

        for (uint i = 0; i < amounts.length; i++) {
            _depositToVault(amounts[i]);
            _assertInvariant("after deposit");
        }

        uint[4] memory jumps = [uint(3 hours), uint(11 hours), uint(1 days + 7), uint(5 days)];

        for (uint i = 0; i < jumps.length; i++) {
            skip(jumps[i]);
            _assertInvariant("after time jump");
        }

        _withdrawFromVault(3e9 + 5);
        _assertInvariant("after withdraw");

        _depositToVault(7e9 + 11);
        _assertInvariant("after redeposit");

        skip(2 days);
        _assertInvariant("final");
    }

    // ---------------------------------------------------------------------
    // Test 2: withdraws at different indexes (down-direction / burn)
    // ---------------------------------------------------------------------
    function test_H1_withdrawsAtDifferentIndexes() public {
        _depositToVault(5e18);
        _assertInvariant("initial deposit");

        uint[6] memory withdrawals = [
            uint(1e15 + 1),
            uint(1e15 + 7),
            uint(1e15 + 13),
            uint(1e15 + 3),
            uint(1e15 + 11),
            uint(1e15 + 5)
        ];

        for (uint i = 0; i < withdrawals.length; i++) {
            _withdrawFromVault(withdrawals[i]);
            _assertInvariant("after withdraw");

            skip(6 hours + i);
        }
    }

    // ---------------------------------------------------------------------
    // Test 3: deterministic adversarial amount
    // ---------------------------------------------------------------------
    function test_H1_adversarialAmount() public {
        uint256 r = IAaveV3Pool(aavePool).getReserveNormalizedIncome(WETH);

        // d = floor(0.75 · RAY / r). At r ≈ RAY, d ≈ 0.75 · RAY.
        uint256 d = (RAY * 75 / 100) * RAY / r;
        require(d > 2, "adversarial d too small");

        emit log_named_uint("rate", r);
        emit log_named_uint("adversarial d", d);

        _depositToVault(d);
        _assertInvariant("adversarial deposit");
    }

    // ---------------------------------------------------------------------
    // Internals wired to AaveTestBase
    // ---------------------------------------------------------------------

    function _depositToVault(uint256 amount) internal {
        deal(WETH, alice, amount);

        vm.startPrank(alice);
        IERC20(WETH).approve(address(aWETHWrapper), amount);
        uint256 shares = aWETHWrapper.deposit(amount, alice);

        aWETHWrapper.approve(address(alice_aave_vault), shares);
        alice_aave_vault.deposit(shares);
        vm.stopPrank();
    }

    function _withdrawFromVault(uint256 amount) internal {
        vm.startPrank(alice);
        alice_aave_vault.withdraw(amount, alice);
        vm.stopPrank();
    }

    function _assertInvariant(string memory ctx) internal view {
        uint accounted = alice_aave_vault.totalAssetsDepositedOrReserved();
        uint scaled = IAToken(aWETHWrapper.aToken()).scaledBalanceOf(address(alice_aave_vault));

        emit log_named_uint(string(abi.encodePacked("accounted @ ", ctx)), accounted);
        emit log_named_uint(string(abi.encodePacked("scaled    @ ", ctx)), scaled);

        if (scaled < accounted) {
            emit log(string(abi.encodePacked("H1 BROKEN @ ", ctx)));
        }
        assertGe(scaled, accounted, "H1: scaledBalanceOf < totalAssetsDepositedOrReserved");
    }
}
