// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AaveTestBase.t.sol";

/// @title H2_EVCBatchLiquidation
/// @notice Hypothesis H2: combining liquidate(vaultA) with deposit(vaultB) in
///         one EVC batch may leave transient `liquidatedBorrower` in a bad state
///         and bypass status checks.
/// @dev IEVC and IAToken are already imported in AaveTestBase.
contract H2_EVCBatchLiquidation is AaveTestBase {

    function setUp() public override {
        super.setUp();
        // Alice's vault
        aave_createCollateralVault(address(aWETHWrapper), 9100);
        // Bob's vault — same wrapper, same LTV, target USDC
        aave_bob_createCollateralVault(address(aWETHWrapper), 9100);
    }

    function test_H2_batchLiquidateA_depositB() public {
        // 1. Deposit into both vaults
        _depositToAlice(5e18);
        _depositToBob(5e18);

        emit log_named_uint("A.total before", alice_aave_vault.totalAssetsDepositedOrReserved());
        emit log_named_uint("B.total before", bob_aave_vault.totalAssetsDepositedOrReserved());

        // 2. Batch: [liquidate(alice_vault), deposit(bob_vault)]
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        items[0] = IEVC.BatchItem({
            targetContract: address(alice_aave_vault),
            onBehalfOfAccount: address(0),
            value: 0,
            data: abi.encodeCall(AaveV3CollateralVault.liquidate, ())
        });

        items[1] = IEVC.BatchItem({
            targetContract: address(bob_aave_vault),
            onBehalfOfAccount: bob,
            value: 0,
            data: abi.encodeCall(AaveV3CollateralVault.deposit, (1e18))
        });

        // 3. Execute as alice
        vm.startPrank(alice);
        evc.batch(items);
        vm.stopPrank();

        // 4. Post-batch logs
        emit log_named_uint("A.total after", alice_aave_vault.totalAssetsDepositedOrReserved());
        emit log_named_uint("B.total after", bob_aave_vault.totalAssetsDepositedOrReserved());
        emit log_named_uint("A.borrower after", uint160(alice_aave_vault.borrower()));

        assertTrue(true, "batch executed");
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _depositToAlice(uint256 amount) internal {
        deal(WETH, alice, amount);
        vm.startPrank(alice);
        IERC20(WETH).approve(address(aWETHWrapper), amount);
        uint256 shares = aWETHWrapper.deposit(amount, alice);
        aWETHWrapper.approve(address(alice_aave_vault), shares);
        alice_aave_vault.deposit(shares);
        vm.stopPrank();
    }

    function _depositToBob(uint256 amount) internal {
        deal(WETH, bob, amount);
        vm.startPrank(bob);
        IERC20(WETH).approve(address(aWETHWrapper), amount);
        uint256 shares = aWETHWrapper.deposit(amount, bob);
        aWETHWrapper.approve(address(bob_aave_vault), shares);
        bob_aave_vault.deposit(shares);
        vm.stopPrank();
    }
}
