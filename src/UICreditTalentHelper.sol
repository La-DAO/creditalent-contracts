// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Application, ApplicationStatus, CreditTalentCenter} from "./CreditTalentCenter.sol";
import {IMorpho, Id, MarketParams, Market, Position} from "@morpho/contracts/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@morpho/contracts/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/contracts/libraries/SharesMathLib.sol";
import {IIrm} from "@morpho/contracts/interfaces/IIrm.sol";

contract UICreditTalentHelper {
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;

    // Number of seconds in a year (365 days)
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // Scaling factors
    uint256 private constant SCALING_FACTOR = 1e18;
    uint256 private constant RAY = 1e27;

    /**
     * @notice Get user loan information
     * @param user from whom to get loan information
     * @return creditLine amount approved by underwriter to user
     * @return debtBalance borrowed + accrued interest amount by user currently
     * @return borrowAPY (scaled by 1e27)
     */
    function getUserLoanInfo(address creditCenter, address user)
        external
        view
        returns (uint256 creditLine, uint256 debtBalance, uint256 borrowAPY)
    {
        CreditTalentCenter creditTalent = CreditTalentCenter(creditCenter);
        Application memory application = creditTalent.applicationInfo(user);
        if (application.underwriter == address(0) || application.status != ApplicationStatus.Approved) {
            return (0, 0, 0);
        }
        creditLine = creditTalent.creditShares(application.underwriter);
        address irm = application.irm == address(0) ? creditTalent.adpativeIrm() : application.irm;

        IMorpho morpho = creditTalent.morpho();

        MarketParams memory marketParams = MarketParams(
            creditTalent.underwritingAsset(),
            creditTalent.creditPoints(),
            address(this),
            irm,
            creditTalent.DEFAULT_LLTV()
        );
        Position memory morphoPosition = morpho.position(marketParams.id(), user);
        Market memory market = morpho.market(marketParams.id());
        debtBalance =
            uint256(morphoPosition.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        borrowAPY = _convertToAPY(IIrm(irm).borrowRateView(marketParams, market));
    }

    /**
     * @dev Converts a rate per second to Annual Percentage Yield (APY)
     * @param ratePerSecond The interest rate per second (scaled by 1e18)
     * @return apy The Annual Percentage Yield (scaled by 1e27)
     * @notice Calculates compound interest with continuous compounding
     * @notice APY = (1 + rate)^(seconds in year) - 1
     */
    function _convertToAPY(uint256 ratePerSecond) internal pure returns (uint256 apy) {
        // Adjust rate to ray scale by multiplying by 1e9
        uint256 adjustedRatePerSecond = ratePerSecond * (RAY / SCALING_FACTOR);

        // Compound the rate for a year
        // This calculates (1 + r)^t - 1, where:
        // r = interest rate per compounding period
        // t = number of compounding periods (seconds in a year)
        uint256 compoundedRate = RAY;
        for (uint256 i = 0; i < SECONDS_PER_YEAR; i++) {
            compoundedRate = (compoundedRate * (adjustedRatePerSecond + RAY)) / RAY;
        }

        // Subtract the initial principal to get the yield
        apy = compoundedRate - RAY;
        return apy;
    }
}
