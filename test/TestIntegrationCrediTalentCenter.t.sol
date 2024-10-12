// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/StdUtils.sol";
import {console} from "forge-std/Console.sol";
import {CreditTalentCenter} from "../src/CreditTalentCenter.sol";
import {CreditPoints} from "../src/CreditPoints.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MarketParamsLib} from "@morpho/contracts/libraries/MarketParamsLib.sol";
import {IMorpho, MarketParams, Position, Id} from "@morpho/contracts/interfaces/IMorpho.sol";

contract TestIntegrationCrediTalentCenter is Test {
    using MarketParamsLib for MarketParams;

    /// Base Sepolia fork
    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MOPRHO_ADAPTIVEIRM = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    MockToken public xocolatl;
    CreditPoints public creditPoints;
    CreditTalentCenter public talentCenter;

    VmSafe.Wallet public User1;
    VmSafe.Wallet public User2;
    VmSafe.Wallet public User3;
    VmSafe.Wallet public User4;
    VmSafe.Wallet public Admin;

    function setUp() public {
        User1 = vm.createWallet("User1");
        User2 = vm.createWallet("User2");
        User3 = vm.createWallet("User3");
        User4 = vm.createWallet("User4");
        Admin = vm.createWallet("Admin");

        vm.createSelectFork("baseSepolia");

        vm.startPrank(Admin.addr);
        xocolatl = new MockToken("Xocolatl MXN Stablecoin", "MXNX");
        CreditPoints CreditPointsImpl = new CreditPoints();
        talentCenter = new CreditTalentCenter(address(xocolatl), CreditPointsImpl, IMorpho(MORPHO), MOPRHO_ADAPTIVEIRM);
        vm.stopPrank();
        creditPoints = CreditPoints(talentCenter.creditPoints());
    }

    function test_constructor() public view {
        assertEq(talentCenter.underwritingAsset(), address(xocolatl));
    }

    function test_applyToCredit() public {
        vm.startPrank(User1.addr);
        talentCenter.applyToCredit("0x1234");
        vm.stopPrank();
        assertEq(talentCenter.applications(), 1);
    }

    function test_applyToUnderwrite() public {
        uint256 tenThousandXocs = 10000e18;
        load_tokens_to_user(xocolatl, User2.addr, tenThousandXocs);
        vm.startPrank(User2.addr);
        xocolatl.approve(address(talentCenter), tenThousandXocs);
        talentCenter.applyToUnderwrite(tenThousandXocs);
        vm.stopPrank();
        assertEq(xocolatl.balanceOf(address(talentCenter)), tenThousandXocs);
        assertEq(creditPoints.balanceOf(address(talentCenter)), tenThousandXocs);
    }

    function test_approveCredit() public {
        address applicant = User1.addr;
        do_applyToCredit(applicant);

        address underWriter = User2.addr;
        uint256 tenThousandXocs = 10000e18;
        do_applyToUnderwrite(underWriter, tenThousandXocs);

        uint256 floatingRate = type(uint256).max;
        vm.startPrank(underWriter);
        talentCenter.approveCredit(applicant, 1, tenThousandXocs, floatingRate);

        assertEq(creditPoints.balanceOf(applicant), 0);
        assertEq(xocolatl.balanceOf(applicant), 0);

        IMorpho morpho = IMorpho(MORPHO);

        MarketParams memory marketParams = MarketParams({
            loanToken: address(xocolatl),
            collateralToken: address(creditPoints),
            oracle: address(talentCenter),
            irm: MOPRHO_ADAPTIVEIRM,
            lltv: talentCenter.DEFAULT_LLTV()
        });
        Position memory position = morpho.position(marketParams.id(), applicant);
        assertEq(position.supplyShares, tenThousandXocs);
        assertEq(position.collateral, tenThousandXocs);
        assertEq(position.borrowShares, 0);
    }

    function load_tokens_to_user(MockToken token, address user, uint256 amount) internal {
        token.mint(user, amount);
    }

    function do_applyToCredit(address user) internal {
        vm.prank(user);
        talentCenter.applyToCredit("0x1234");
    }

    function do_applyToUnderwrite(address user, uint256 amount) internal {
        load_tokens_to_user(xocolatl, user, amount);
        vm.startPrank(User2.addr);
        xocolatl.approve(address(talentCenter), amount);
        talentCenter.applyToUnderwrite(amount);
        vm.stopPrank();
    }
}
