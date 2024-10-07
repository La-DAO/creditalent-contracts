// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IIrm} from "@morpho/contracts/interfaces/IIrm.sol";
import {MarketParamsLib} from "@morpho/contracts/libraries/MarketParamsLib.sol";
import {Id, MarketParams, Market} from "@morpho/contracts/interfaces/IMorpho.sol";

/* ERRORS */

/// @dev Thrown when the rate is not already set for this market.
string constant RATE_NOT_SET = "rate not set";
/// @dev Thrown when the rate is already set for this market.
string constant RATE_SET = "rate set";
/// @dev Thrown when trying to set the rate at zero.
string constant RATE_ZERO = "rate zero";
/// @dev Thrown when trying to set a rate that is too high.
string constant RATE_TOO_HIGH = "rate too high";

/// @title FixedRateIrm
/// @author Modified from Morpho Labs
/// @custom:contact security@xocolatl.xyz
contract FixedRateIrm {
    using MarketParamsLib for MarketParams;

    /* EVENTS */
    event SetBorrowRate(uint256 newBorrowRate);

    /* CONSTANTS */
    uint256 public constant MAX_BORROW_RATE = 8.0 ether / uint256(365 days);

    /* STORAGE */
    uint256 public borrowRateStored;

    constructor(uint256 borrowRate_) {
        _setBorrowRate(borrowRate_);
    }

    /* SETTER */
    function _setBorrowRate(uint256 borrowRate_) internal {
        require(borrowRateStored == 0, RATE_SET);
        require(borrowRate_ != 0, RATE_ZERO);
        require(borrowRate_ <= MAX_BORROW_RATE, RATE_TOO_HIGH);
        borrowRateStored = borrowRate_;
        emit SetBorrowRate(borrowRate_);
    }

    /* BORROW RATES */

    function borrowRateView(MarketParams memory, Market memory) external view returns (uint256) {
        uint256 borrowRateCached = borrowRateStored;
        require(borrowRateCached != 0, RATE_NOT_SET);
        return borrowRateCached;
    }

    /// @dev Reverts on not set rate, so the rate has to be set before the market creation.
    function borrowRate(MarketParams memory, Market memory) external view returns (uint256) {
        uint256 borrowRateCached = borrowRateStored;
        require(borrowRateCached != 0, RATE_NOT_SET);
        return borrowRateCached;
    }
}
