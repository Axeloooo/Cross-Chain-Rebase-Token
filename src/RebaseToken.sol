// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Axel Sanchez
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global rate at time of depositing.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5 * PRECISION_FACTOR / 1e8;
    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateUpdated(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the smart contract
     * @param _newInterestrate The new interest rate to set
     */
    function setInterestRate(uint256 _newInterestrate) external onlyOwner {
        if (_newInterestrate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestrate);
        }
        s_interestRate = _newInterestrate;
        emit InterestRateUpdated(_newInterestrate);
    }

    /**
     * @notice Get the principal balance for a user (the balance without any interest accumulated since the last update)
     * @param _user The user to get the principal balance for
     * @return The principal balance for the user
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The address to mint tokens to
     * @param _amount The amount of tokens to mint
     * @param _interestRate The interest rate to use for the user
     */
    function mint(address _to, uint256 _amount, uint256 _interestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = _interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The address to burn tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculate the balance for the user including any interest accumulated since the last update (principal balance) + some interest that has accrued
     * @param _user The user to calculate the balance for
     * @return The balance for the user including any interest accumulated since the last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from the sender to the recipient and mint any interest accumulated for both the sender and recipient since the last update
     * @param _recipient The address to transfer tokens to
     * @param _amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from the sender to the recipient and mint any interest accumulated for both the sender and recipient since the last update
     * @param _sender The address to transfer tokens from
     * @param _recipient The address to transfer tokens to
     * @param _amount The amount of tokens to transfer
     * @return A boolean value indicating whether the operation succeeded
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_userInterestRates[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest accumulated for a user since the last update
     * @param _user The user to calculate the interest accumulated for
     * @return The interest accumulated for the user since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        uint256 linearInterest = PRECISION_FACTOR + (s_userInterestRates[_user] * timeElapsed);
        return linearInterest;
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer)
     * @param _user The user to mint accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Get the global interest rate for the smart contract
     * @return The global interest rate for the smart contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate for a user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }
}
