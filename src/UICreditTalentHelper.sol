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
     * @return interestRatePerSecond scaled 1e18 (see https://docs.morpho.org/morpho/contracts/irm/#borrow-apy to convert to APY)
     */
    function getUserLoanInfo(address creditCenter, address user)
        external
        view
        returns (uint256 creditLine, uint256 debtBalance, uint256 interestRatePerSecond)
    {
        CreditTalentCenter creditTalent = CreditTalentCenter(creditCenter);
        Application memory application;
        (,,, application.underwriter, application.status, application.irm) = creditTalent.applicationInfo(user);
        if (application.underwriter == address(0) || application.status != ApplicationStatus.Approved) {
            return (0, 0, 0);
        }
        creditLine = creditTalent.creditShares(application.underwriter);
        address irm = application.irm == address(0) ? creditTalent.adpativeIrm() : application.irm;

        IMorpho morpho = creditTalent.morpho();

        MarketParams memory marketParams = MarketParams(
            creditTalent.underwritingAsset(),
            creditTalent.creditPoints(),
            address(creditTalent),
            irm,
            creditTalent.DEFAULT_LLTV()
        );
        Position memory morphoPosition = morpho.position(marketParams.id(), user);
        Market memory market = morpho.market(marketParams.id());
        debtBalance =
            uint256(morphoPosition.borrowShares).toAssetsUp(market.totalBorrowAssets, market.totalBorrowShares);
        interestRatePerSecond = IIrm(irm).borrowRateView(marketParams, market);
    }
}
