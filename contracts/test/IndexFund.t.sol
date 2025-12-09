// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/IndexFund.sol";
import "../src/interfaces/IIndexFund.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./helpers/TestHelpers.sol";

contract IndexFundTest is Test {
    IndexFund public fundImplementation;
    IndexFund public fund;

    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;
    MockSwapRouter public swapRouter;

    address owner = address(1);
    address treasury = address(2);
    address user1 = address(3);
    address user2 = address(4);

    function setUp() public {
        // Deploy mock tokens
        vm.startPrank(owner);

        usdc = new MockERC20("USDC", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC");
        swapRouter = new MockSwapRouter();

        // Setup allocations
        IIndexFund.TokenAllocation[] memory allocations = new IIndexFund.TokenAllocation[](2);
        allocations[0] = IIndexFund.TokenAllocation({
            token: address(weth),
            targetPercentage: 6000 // 60%
        });
        allocations[1] = IIndexFund.TokenAllocation({
            token: address(wbtc),
            targetPercentage: 4000 // 40%
        });

        // Deploy implementation
        fundImplementation = new IndexFund();

        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            IndexFund.initialize.selector,
            "Test Index Fund",
            "TIF",
            address(usdc),
            allocations,
            200, // 2% management fee
            address(swapRouter),
            treasury
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(fundImplementation), initData);
        fund = IndexFund(address(proxy));

        // Distribute tokens to users
        usdc.transfer(user1, 10000 * 10 ** 18);
        usdc.transfer(user2, 10000 * 10 ** 18);
        weth.transfer(address(fund), 100 * 10 ** 18);
        wbtc.transfer(address(fund), 10 * 10 ** 18);

        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(fund.name(), "Test Index Fund");
        assertEq(fund.symbol(), "TIF");
        assertEq(fund.managementFee(), 200);
        assertEq(fund.treasury(), treasury);

        IIndexFund.TokenAllocation[] memory allocations = fund.getAllocations();
        assertEq(allocations.length, 2);
        assertEq(allocations[0].token, address(weth));
        assertEq(allocations[0].targetPercentage, 6000);
    }

    function testDeposit() public {
        vm.startPrank(user1);

        uint256 depositAmount = 1000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);

        uint256 shares = fund.deposit(depositAmount, user1);

        assertGt(shares, 0);
        assertEq(fund.balanceOf(user1), shares);

        vm.stopPrank();
    }

    function testWithdraw() public {
        // First deposit
        vm.startPrank(user1);
        uint256 depositAmount = 1000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);
        uint256 shares = fund.deposit(depositAmount, user1);

        // Then redeem (burn shares to withdraw assets)
        uint256 redeemShares = shares / 2;
        fund.redeem(redeemShares, user1, user1);

        assertEq(fund.balanceOf(user1), shares - redeemShares);

        vm.stopPrank();
    }

    function testUpdateAllocations() public {
        vm.startPrank(owner);

        IIndexFund.TokenAllocation[] memory newAllocations = new IIndexFund.TokenAllocation[](2);
        newAllocations[0] = IIndexFund.TokenAllocation({
            token: address(weth),
            targetPercentage: 5000 // 50%
        });
        newAllocations[1] = IIndexFund.TokenAllocation({
            token: address(wbtc),
            targetPercentage: 5000 // 50%
        });

        fund.updateAllocations(newAllocations);

        IIndexFund.TokenAllocation[] memory allocations = fund.getAllocations();
        assertEq(allocations[0].targetPercentage, 5000);
        assertEq(allocations[1].targetPercentage, 5000);

        vm.stopPrank();
    }

    function test_RevertWhen_UpdateAllocationsNotOwner() public {
        vm.startPrank(user1);

        IIndexFund.TokenAllocation[] memory newAllocations = new IIndexFund.TokenAllocation[](2);
        newAllocations[0] = IIndexFund.TokenAllocation({token: address(weth), targetPercentage: 5000});
        newAllocations[1] = IIndexFund.TokenAllocation({token: address(wbtc), targetPercentage: 5000});

        vm.expectRevert();
        fund.updateAllocations(newAllocations);

        vm.stopPrank();
    }

    function testCollectFees() public {
        // Deposit more funds to get meaningful fees
        vm.startPrank(user1);
        uint256 depositAmount = 10000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);
        fund.deposit(depositAmount, user1);
        vm.stopPrank();

        // Fast forward time
        vm.warp(block.timestamp + 365 days);

        // Collect fees
        uint256 treasuryBalanceBefore = fund.balanceOf(treasury);
        fund.collectFees();
        uint256 treasuryBalanceAfter = fund.balanceOf(treasury);

        assertGt(treasuryBalanceAfter, treasuryBalanceBefore);
    }

    function testTotalAssets() public view {
        uint256 total = fund.totalAssets();
        assertGt(total, 0);
    }

    function testGetFundInfo() public view {
        IIndexFund.FundInfo memory info = fund.getFundInfo();
        assertEq(info.name, "Test Index Fund");
        assertEq(info.symbol, "TIF");
        assertEq(info.managementFee, 200);
    }

    function testRebalance() public {
        vm.startPrank(owner);

        bytes[] memory swapData = new bytes[](2);
        // Empty swap data for test

        fund.rebalance(swapData);

        vm.stopPrank();
    }

    function testPause() public {
        // Pause the fund
        vm.prank(owner);
        fund.pause();

        // Try to deposit - should revert
        vm.startPrank(user1);
        uint256 depositAmount = 1000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);

        vm.expectRevert();
        fund.deposit(depositAmount, user1);

        vm.stopPrank();
    }

    function testPauseBlocksMint() public {
        vm.prank(owner);
        fund.pause();

        vm.startPrank(user1);
        usdc.approve(address(fund), 1000 * 10 ** 18);

        vm.expectRevert();
        fund.mint(100 * 10 ** 18, user1);

        vm.stopPrank();
    }

    function testPauseBlocksWithdraw() public {
        // First deposit while unpaused
        vm.startPrank(user1);
        uint256 depositAmount = 1000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);
        fund.deposit(depositAmount, user1);
        vm.stopPrank();

        // Pause the fund
        vm.prank(owner);
        fund.pause();

        // Try to withdraw - should revert
        vm.startPrank(user1);
        vm.expectRevert();
        fund.withdraw(100 * 10 ** 18, user1, user1);
        vm.stopPrank();
    }

    function testPauseBlocksRedeem() public {
        // First deposit while unpaused
        vm.startPrank(user1);
        uint256 depositAmount = 1000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);
        uint256 shares = fund.deposit(depositAmount, user1);
        vm.stopPrank();

        // Pause the fund
        vm.prank(owner);
        fund.pause();

        // Try to redeem - should revert
        vm.startPrank(user1);
        vm.expectRevert();
        fund.redeem(shares / 2, user1, user1);
        vm.stopPrank();
    }

    function testPauseBlocksRebalance() public {
        vm.prank(owner);
        fund.pause();

        vm.prank(owner);
        bytes[] memory swapData = new bytes[](2);
        vm.expectRevert();
        fund.rebalance(swapData);
    }

    function testUnpause() public {
        // Pause
        vm.prank(owner);
        fund.pause();

        // Unpause
        vm.prank(owner);
        fund.unpause();

        // Should be able to deposit now
        vm.startPrank(user1);
        uint256 depositAmount = 1000 * 10 ** 18;
        usdc.approve(address(fund), depositAmount);
        uint256 shares = fund.deposit(depositAmount, user1);
        assertGt(shares, 0);
        vm.stopPrank();
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        fund.pause();
    }

    function testOnlyOwnerCanUnpause() public {
        vm.prank(owner);
        fund.pause();

        vm.prank(user1);
        vm.expectRevert();
        fund.unpause();
    }
}
