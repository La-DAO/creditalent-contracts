// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CrediTalentCenter} from "../src/CrediTalentCenter.sol";
import {CrediPoints} from "../src/CrediPoints.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {IMorpho} from "@morpho/contracts/interfaces/IMorpho.sol";

contract TestIntegrationCrediTalentCenter is Test {
    /// Base Sepolia fork
    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant MOPRHO_ADAPTIVEIRM = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    MockToken public xocolatl;
    CrediPoints public crediPoints;
    CrediTalentCenter public talentCenter;

    function setUp() public {
        vm.createSelectFork("baseSepolia");
        xocolatl = new MockToken("Xocolatl MXN Stablecoin", "MXNX");
        CrediPoints crediPointsImpl = new CrediPoints();
        talentCenter = new CrediTalentCenter(address(xocolatl), crediPointsImpl, IMorpho(MORPHO), MOPRHO_ADAPTIVEIRM);
    }

    function test_constructor() public view {
        assertEq(talentCenter.underwritingAsset(), address(xocolatl));
    }
}
