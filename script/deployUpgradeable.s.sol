// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CreditTalentCenterUpgradeable} from "../src/upgradeable/CreditTalentCenterUpgradeable.sol";

contract DeployUpgradeable is Script {
    address public constant CREDIT_TOKEN_IMPL = 0xa3ceD4b017F17Fd4ff5a4f1786b7bBF8F8067B31;
    address public constant UNDERWRITING_XOC = 0x4eE906B7135bDBdfC83FE40b8f2156C99FCB64c2;
    address public constant UNDERWRITING_USDC = 0x03E5F3A1aE8FaeA9d8Ec56a3eD1e708CFEDe1970;
    address public constant UNDERWRITING_TALENT = 0xaAE22ccff30E636BDa436D54E5efea72227B2868;

    address public constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant ADAPTIV_IRM = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    function run() public {
        vm.startBroadcast();
        address implementation = address(0x032C5D2E4dD2B9B2Dc163C2BfFC5039F77a033e1);
        bytes memory initData = abi.encodeWithSelector(
            CreditTalentCenterUpgradeable.initialize.selector,
            UNDERWRITING_TALENT,
            CREDIT_TOKEN_IMPL,
            MORPHO,
            ADAPTIV_IRM
        );
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);
        console.log("Deployed CreditTalentCenterUpgradeable at:", address(proxy));
        vm.stopBroadcast();
    }
}
