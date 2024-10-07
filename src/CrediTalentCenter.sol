// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CrediPoints} from "./CrediPoints.sol";
import {FixedRateIrm} from "./FixedRateIrm.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MarketParamsLib} from "@morpho/contracts/libraries/MarketParamsLib.sol";
import {IMorpho, Id, MarketParams, Market} from "@morpho/contracts/interfaces/IMorpho.sol";
import {IIrm} from "@morpho/contracts/interfaces/IIrm.sol";
import {IOracle} from "@morpho/contracts/interfaces/IOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

enum ApplicationStatus {
    None,
    Pending,
    Approved,
    Rejected
}

struct Underwriter {
    address underwriter;
    uint256 approvalLimit;
}

struct Application {
    uint256 id;
    address applicant;
    address receiver;
    bytes32 dataHash;
    ApplicationStatus status;
}

contract CrediTalentCenter is IOracle, AccessControl {
    using MarketParamsLib for MarketParams;

    // cast keccak 'UNDERWRITER_ROLE'
    bytes32 public constant UNDERWRITER_ROLE = 0xf63acc52fa4ad8a2695e14522f3df504db5c225cdd3d3a5acd3569b444572187;
    uint256 public constant DEFAULT_LLTV = 0.98e18;

    /// Events
    event ApplicationCreated(uint256 id, address applicant, address receiver, bytes32 dataHash);
    event UnderwriterSet(address indexed account, uint256 approvalLimit);
    event FixedRateIrmSet(uint256 indexed interestRate, address irm);

    /// Custom errors
    error CrediTalentCenter_applicationAlreadyExists();
    error CrediTalentCenter_fixedRateIrmAlreadyExists();

    address public immutable underwritingAsset;
    address public immutable creditPoints;
    IMorpho public immutable morpho;
    uint256 public applications;
    mapping(uint256 => FixedRateIrm) public fixedRateIrms; // InterestRate (in WAD) => IIrm address
    mapping(address => Underwriter) public underwriters;
    mapping(address => Application) public applicationInfo;

    constructor(
        address underwritingAsset_,
        CrediPoints crediPointsImpl_,
        IMorpho morpho_,
        uint256 defaultInterestRate
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UNDERWRITER_ROLE, msg.sender);
        underwritingAsset = underwritingAsset_;
        bytes memory initData =
            abi.encodeWithSelector(CrediPoints.initialize.selector, address(this), underwritingAsset_);
        creditPoints = address(new ERC1967Proxy(address(crediPointsImpl_), initData));
        morpho = morpho_;
        FixedRateIrm firm = _setFixedRateIrms(defaultInterestRate);
        MarketParams memory marketParams =
            MarketParams(underwritingAsset_, creditPoints, address(this), address(firm), DEFAULT_LLTV);
        morpho.createMarket(marketParams);
    }

    /// @inheritdoc IOracle
    function price() external view returns (uint256) {
        uint256 underwriteAssetDecimals = IERC20Metadata(underwritingAsset).decimals();
        uint256 scaleFactor = 10 ** (36 + underwriteAssetDecimals - IERC20Metadata(creditPoints).decimals());
        return scaleFactor * 10 ** underwriteAssetDecimals;
    }

    function applyToCredit(bytes32 dataHash_, address receiver_) public {
        require(applicationInfo[msg.sender].applicant == address(0), CrediTalentCenter_applicationAlreadyExists());
        uint256 id = _useApplicationNumber();
        applicationInfo[msg.sender] = Application(id, msg.sender, receiver_, dataHash_, ApplicationStatus.Pending);
        emit ApplicationCreated(id, msg.sender, receiver_, dataHash_);
    }

    function setFixedRateIrms(uint256 newBorrowRate_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFixedRateIrms(newBorrowRate_);
    }

    function setUnderwriter(address underwriter_, uint256 approveLimit_) external onlyRole(DEFAULT_ADMIN_ROLE) {}

    function _setFixedRateIrms(uint256 newBorrowRate_) internal returns (FixedRateIrm) {
        require(address(fixedRateIrms[newBorrowRate_]) == address(0), CrediTalentCenter_fixedRateIrmAlreadyExists());
        FixedRateIrm firm = new FixedRateIrm(newBorrowRate_);
        fixedRateIrms[newBorrowRate_] = firm;
        emit FixedRateIrmSet(newBorrowRate_, address(firm));
        return firm;
    }

    function _useApplicationNumber() internal returns (uint256) {
        applications += 1;
        return applications;
    }
}
