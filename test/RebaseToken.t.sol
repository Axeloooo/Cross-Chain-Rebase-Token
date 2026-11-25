// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        assertEq(startBalance, amount);
        vm.warp(block.timestamp + 1 hours);

        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        vm.warp(block.timestamp + 1 hours);

        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        vault.redeem(amount);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint32).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);

        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;

        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 userBalanceAfter = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfter = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfter, userBalance - amountToSend);
        assertEq(user2BalanceAfter, amountToSend);

        assertEq(rebaseToken.getUserInterestRate(user), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        uint256 interestRate = rebaseToken.getInterestRate();

        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, 100, interestRate);

        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, 100);
    }

    function testGetPrincipalAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principalBalanceOf(user), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    /*//////////////////////////////////////////////////////////////
                    INTEREST RATE MERGE (SECURITY REVIEW)
    //////////////////////////////////////////////////////////////*/

    uint256 private constant HIGH_RATE = 5e10;
    uint256 private constant LOW_RATE = 4e10;

    function _deposit(address _user, uint256 _amount) internal {
        vm.deal(_user, _amount);
        vm.prank(_user);
        vault.deposit{value: _amount}();
    }

    /// @dev Stands in for RebaseTokenPool.releaseOrMint, which calls mint(receiver, amount, sourceRate).
    function _bridgeMint(address _receiver, uint256 _amount, uint256 _sourceRate) internal returns (address pool) {
        pool = makeAddr("pool");
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(pool);
        vm.prank(pool);
        rebaseToken.mint(_receiver, _amount, _sourceRate);
    }

    function _weightedRate(uint256 _balanceA, uint256 _rateA, uint256 _balanceB, uint256 _rateB)
        internal
        pure
        returns (uint256)
    {
        return (_balanceA * _rateA + _balanceB * _rateB) / (_balanceA + _balanceB);
    }

    /// Finding 1: dust parked at an old high rate must not lift a large low-rate balance moved onto it.
    function testTransferOntoDustHolderDoesNotUpgradeRate() public {
        address attackerDust = makeAddr("attackerDust");
        address attackerMain = makeAddr("attackerMain");
        uint256 dust = 1e5;
        uint256 amount = 100 ether;

        _deposit(attackerDust, dust);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);
        _deposit(attackerMain, amount);
        assertEq(rebaseToken.getUserInterestRate(attackerMain), LOW_RATE);

        vm.prank(attackerMain);
        rebaseToken.transfer(attackerDust, type(uint256).max);

        assertEq(rebaseToken.getUserInterestRate(attackerDust), _weightedRate(dust, HIGH_RATE, amount, LOW_RATE));
        assertLt(rebaseToken.getUserInterestRate(attackerDust), LOW_RATE + 1e5);

        // The combined position earns no more than the two deposits would have earned separately.
        vm.warp(block.timestamp + 365 days);
        uint256 honestBalance =
            (dust * (1e18 + HIGH_RATE * 365 days)) / 1e18 + (amount * (1e18 + LOW_RATE * 365 days)) / 1e18;
        assertLe(rebaseToken.balanceOf(attackerDust), honestBalance);
    }

    /// Finding 1, transferFrom path.
    function testTransferFromOntoDustHolderDoesNotUpgradeRate() public {
        address attackerDust = makeAddr("attackerDust");
        address attackerMain = makeAddr("attackerMain");
        address spender = makeAddr("spender");
        uint256 dust = 1e5;
        uint256 amount = 100 ether;

        _deposit(attackerDust, dust);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);
        _deposit(attackerMain, amount);

        vm.prank(attackerMain);
        rebaseToken.approve(spender, amount);
        vm.prank(spender);
        rebaseToken.transferFrom(attackerMain, attackerDust, amount);

        assertEq(rebaseToken.getUserInterestRate(attackerDust), _weightedRate(dust, HIGH_RATE, amount, LOW_RATE));
    }

    /// A transfer into an empty account still hands over the sender's rate (unchanged behavior).
    function testTransferToEmptyAccountInheritsSenderRate() public {
        address recipient = makeAddr("recipient");
        _deposit(user, 1 ether);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);

        vm.prank(user);
        rebaseToken.transfer(recipient, 0.5 ether);

        assertEq(rebaseToken.getUserInterestRate(recipient), HIGH_RATE);
        assertEq(rebaseToken.getUserInterestRate(user), HIGH_RATE);
    }

    function testTransferToSelfKeepsRate() public {
        _deposit(user, 1 ether);
        vm.prank(user);
        rebaseToken.transfer(user, 0.5 ether);
        assertEq(rebaseToken.getUserInterestRate(user), HIGH_RATE);
        assertEq(rebaseToken.balanceOf(user), 1 ether);
    }

    /// The merged rate always lies between the two input rates, and never rounds up.
    function testFuzzTransferMergedRateIsBounded(uint256 recipientAmount, uint256 senderAmount) public {
        recipientAmount = bound(recipientAmount, 1, type(uint96).max);
        senderAmount = bound(senderAmount, 1, type(uint96).max);
        address recipient = makeAddr("recipient");

        _deposit(recipient, recipientAmount);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);
        _deposit(user, senderAmount);

        vm.prank(user);
        rebaseToken.transfer(recipient, senderAmount);

        uint256 merged = rebaseToken.getUserInterestRate(recipient);
        assertGe(merged, LOW_RATE);
        assertLe(merged, HIGH_RATE);
        assertEq(merged, _weightedRate(recipientAmount, HIGH_RATE, senderAmount, LOW_RATE));
    }

    /// Finding 2 (griefing): bridging 1 wei at a low rate must not wipe out a victim's rate.
    function testBridgedDustCannotLowerReceiverRate() public {
        address victim = makeAddr("victim");
        _deposit(victim, 100 ether);

        _bridgeMint(victim, 1, 0);

        assertApproxEqAbs(rebaseToken.getUserInterestRate(victim), HIGH_RATE, 1);
    }

    /// Finding 2 (self-dealing): bridging 1 wei from a high-rate account must not lift a large low-rate balance.
    function testBridgedDustCannotRaiseReceiverRate() public {
        address attacker = makeAddr("attacker");
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);
        _deposit(attacker, 100 ether);

        _bridgeMint(attacker, 1, HIGH_RATE);

        assertApproxEqAbs(rebaseToken.getUserInterestRate(attacker), LOW_RATE, 1);
    }

    /// Normal bridging: an empty receiver adopts the source chain rate, even above the local global rate.
    function testBridgedMintToEmptyAccountAdoptsSourceRate() public {
        address receiver = makeAddr("receiver");
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);

        _bridgeMint(receiver, 1 ether, HIGH_RATE);

        assertEq(rebaseToken.getUserInterestRate(receiver), HIGH_RATE);
        assertEq(rebaseToken.balanceOf(receiver), 1 ether);
    }

    /// Normal bridging onto an existing balance blends the two rates by amount.
    function testBridgedMintOntoExistingBalanceBlendsRates() public {
        address receiver = makeAddr("receiver");
        _deposit(receiver, 1 ether);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);

        _bridgeMint(receiver, 3 ether, LOW_RATE);

        assertEq(rebaseToken.getUserInterestRate(receiver), _weightedRate(1 ether, HIGH_RATE, 3 ether, LOW_RATE));
        assertEq(rebaseToken.balanceOf(receiver), 4 ether);
    }

    /// A receiver whose balance was fully burned starts fresh with the incoming rate.
    function testMintAfterFullRedeemAdoptsIncomingRate() public {
        _deposit(user, 1 ether);
        vm.prank(user);
        vault.redeem(type(uint256).max);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);

        _deposit(user, 1 ether);

        assertEq(rebaseToken.getUserInterestRate(user), LOW_RATE);
    }

    /// Vault deposits into a new account still get exactly the current global rate.
    function testDepositSetsCurrentGlobalRate() public {
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);
        _deposit(user, 1 ether);
        assertEq(rebaseToken.getUserInterestRate(user), LOW_RATE);
    }

    /// A top-up deposit earns the current global rate on the new tokens; existing tokens keep their rate.
    function testDepositTopUpBlendsWithCurrentGlobalRate() public {
        _deposit(user, 1 ether);
        vm.prank(owner);
        rebaseToken.setInterestRate(LOW_RATE);
        _deposit(user, 1 ether);
        assertEq(rebaseToken.getUserInterestRate(user), _weightedRate(1 ether, HIGH_RATE, 1 ether, LOW_RATE));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint256).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
