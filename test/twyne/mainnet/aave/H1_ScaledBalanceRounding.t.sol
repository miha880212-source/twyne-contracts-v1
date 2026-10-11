// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveTestBase} from "./AaveTestBase.t.sol";
import {console2} from "../MainnetBase.t.sol";
import {IAToken as IAaveV3AToken} from "aave-v3/interfaces/IAToken.sol";
import {IPool as IAaveV3Pool} from "aave-v3/interfaces/IPool.sol";

/// Hypothesis H1: rounding in AaveV3ATokenWrapper.rebalanceATokens_CV can leave
/// aToken.scaledBalanceOf(CV) one unit below totalAssetsDepositedOrReserved,
/// which makes isExternallyLiquidated() return true without a real liquidation.
/// The test only OBSERVES: any "H1 BROKEN" log / failed assert = candidate finding.
contract H1_ScaledBalanceRounding is AaveTestBase {

    function _check(string memory tag) internal view returns (bool ok) {
        uint total = alice_aave_vault.totalAssetsDepositedOrReserved();
        uint scaled = IAaveV3AToken(alice_aave_vault.aToken()).scaledBalanceOf(address(alice_aave_vault));
        ok = total <= scaled;
        console2.log(tag);
        console2.log("  total  ", total);
        console2.log("  scaled ", scaled);
        if (!ok) console2.log("  >>> H1 BROKEN: scaled < total <<<");
    }

    function test_H1_depositsAtDifferentIndexes() public {
        // vault with credit already reserved, Alice has a vault (WETH collateral, USDC target)
        aave_createCollateralVault(address(aWETHWrapper), 9100);

        uint[8] memory amounts = [uint(1), 3, 7, 1e9 + 1, 1e15 + 7, 123456789012345678, 1e18 + 3, 2e18 + 11];
        bool anyBroken;

        vm.startPrank(alice);
        aWETHWrapper.approve(address(alice_aave_vault), type(uint).max);
        vm.stopPrank();

        for (uint i; i < amounts.length; i++) {
            // move the Aave liquidity index between deposits
            vm.warp(block.timestamp + 13 days + i * 977);
            vm.roll(block.number + 1000 + i);

            vm.startPrank(alice);
            aWETHWrapper.deposit(amounts[i], alice); // shares to Alice
            uint shares = aWETHWrapper.balanceOf(alice);
            if (shares > amounts[i]) shares = amounts[i];
            alice_aave_vault.deposit(shares > 0 ? shares : 1);
            vm.stopPrank();

            if (!_check("after deposit")) anyBroken = true;

            // permissionless rebalance if possible
            if (alice_aave_vault.canRebalance() > 0) {
                alice_aave_vault.rebalance();
                if (!_check("after rebalance")) anyBroken = true;
            }
            assertFalse(alice_aave_vault.isExternallyLiquidated(), "false external liquidation");
        }
        assertFalse(anyBroken, "H1: scaledBalance dropped below totalAssets");
    }

    function test_H1_withdrawsAtDifferentIndexes() public {
        aave_createCollateralVault(address(aWETHWrapper), 9100);
        aave_collateralDeposit(5e18);

        bool anyBroken;
        for (uint i; i < 6; i++) {
            vm.warp(block.timestamp + 9 days + i * 313);
            vm.roll(block.number + 700 + i);

            uint amt = 123456789 + i * 987654321;
            vm.prank(alice);
            alice_aave_vault.withdraw(amt, alice);

            if (!_check("after withdraw")) anyBroken = true;
            assertFalse(alice_aave_vault.isExternallyLiquidated(), "false external liquidation");
        }
        assertFalse(anyBroken, "H1: scaledBalance dropped below totalAssets");
    }
}
