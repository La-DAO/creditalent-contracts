// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICreditTalent, Application, ApplicationStatus, Underwriter} from "../interfaces/ICreditTalent.sol";
import {CreditPoints} from "../CreditPoints.sol";
import {FixedRateIrm} from "../FixedRateIrm.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MarketParamsLib} from "@morpho/contracts/libraries/MarketParamsLib.sol";
import {SharesMathLib} from "@morpho/contracts/libraries/SharesMathLib.sol";
import {IMorpho, Id, MarketParams, Market, Position} from "@morpho/contracts/interfaces/IMorpho.sol";
import {IIrm} from "@morpho/contracts/interfaces/IIrm.sol";
import {IOracle} from "@morpho/contracts/interfaces/IOracle.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract CreditTalentCenterUpgradeable is
    ICreditTalent,
    Initializable,
    IOracle,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    using MarketParamsLib for MarketParams;
    using SharesMathLib for uint256;
    using SafeERC20 for IERC20;

    // cast keccak 'UNDERWRITER_ROLE'
    bytes32 public constant UNDERWRITER_ROLE = 0xf63acc52fa4ad8a2695e14522f3df504db5c225cdd3d3a5acd3569b444572187;
    uint256 public constant DEFAULT_LLTV = 0.98e18;
    uint256 public constant FLOATING_RATE = type(uint256).max;

    address public underwritingAsset;
    address public creditPoints;
    IMorpho public morpho;
    address public adpativeIrm;

    uint256 public applications;
    uint256 public totalcreditShares;

    mapping(address => uint256) public creditShares;
    mapping(uint256 => FixedRateIrm) public fixedRateIrms; // InterestRate (in WAD) => IIrm address
    mapping(address => Underwriter) public underwriters;
    mapping(address => Application) internal _applicationInfo; // User address => Application

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address underwritingAsset_,
        CreditPoints creditPointsImpl_,
        IMorpho morpho_,
        address adaptiveIrm_
    ) external initializer {
        _checkZeroAddress(underwritingAsset_);
        _checkZeroAddress(address(creditPointsImpl_));
        _checkZeroAddress(address(morpho_));
        _checkZeroAddress(adaptiveIrm_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UNDERWRITER_ROLE, msg.sender);
        underwritingAsset = underwritingAsset_;
        bytes memory initData = abi.encodeWithSelector(
            CreditPoints.initialize.selector,
            IERC20Metadata(underwritingAsset_).decimals(),
            address(this),
            underwritingAsset_
        );
        creditPoints = address(new ERC1967Proxy(address(creditPointsImpl_), initData));
        morpho = morpho_;
        adpativeIrm = adaptiveIrm_;
        MarketParams memory marketParams =
            MarketParams(underwritingAsset_, creditPoints, address(this), address(adaptiveIrm_), DEFAULT_LLTV);
        morpho.createMarket(marketParams);
        CreditPoints(creditPoints).setApprovedReceiver(address(morpho_), true);
    }

    /// View functions
    function applicationInfo(address user_)
        external
        view
        override
        returns (
            uint256 id,
            address applicant,
            bytes32 dataHash,
            address underwriter,
            ApplicationStatus status,
            address irm
        )
    {
        return (
            _applicationInfo[user_].id,
            _applicationInfo[user_].applicant,
            _applicationInfo[user_].dataHash,
            _applicationInfo[user_].underwriter,
            _applicationInfo[user_].status,
            _applicationInfo[user_].irm
        );
    }

    /// @inheritdoc IOracle
    function price() external view returns (uint256) {
        uint256 underwriteAssetDecimals = IERC20Metadata(underwritingAsset).decimals();
        uint256 scaleFactor = 10 ** (36 + underwriteAssetDecimals - IERC20Metadata(creditPoints).decimals());
        return scaleFactor * 10 ** underwriteAssetDecimals;
    }

    /// Core functions

    /**
     * @notice Apply for credit
     * @param dataHash_  TBD identifier for the data verification
     */
    function applyToCredit(bytes32 dataHash_) public {
        // TODO: Add signature verification
        require(_applicationInfo[msg.sender].applicant == address(0), CrediTalentCenter_applicationAlreadyExists());
        uint256 id = _useApplicationNumber();
        _applicationInfo[msg.sender] =
            Application(id, msg.sender, dataHash_, address(0), ApplicationStatus.Pending, address(0));
        emit ApplicationCreated(id, msg.sender, dataHash_);
    }

    /**
     * @notice Apply for underwriting power (requires approval of the underwriting asset)
     * @param amount_ Amount of underwriting power to apply
     */
    function applyToUnderwrite(uint256 amount_) external {
        SafeERC20.safeTransferFrom(IERC20(underwritingAsset), msg.sender, address(this), amount_);
        underwriters[msg.sender] = Underwriter(msg.sender, amount_, new address[](0));
        _grantRole(UNDERWRITER_ROLE, msg.sender);
        CreditPoints(creditPoints).mint(address(this), amount_);
        emit UnderwriterSet(msg.sender, amount_);
    }

    /**
     * @notice Approve credit application (called by underwriter)
     * @param user_ User address
     * @param applicationId_ Application ID
     * @param amount_ Amount of credit to approve
     * @param iRateWad_ pass type(uint256).max for adaptive interest rate, or interest rate in WAD for fixed rate
     */
    function approveCredit(address user_, uint256 applicationId_, uint256 amount_, uint256 iRateWad_)
        external
        onlyRole(UNDERWRITER_ROLE)
    {
        require(_applicationInfo[user_].id == applicationId_, CreditTalentCenter_invalidApplicationId());
        require(_applicationInfo[user_].status == ApplicationStatus.Pending, CreditTalentCenter_applicationNotPending());
        require(underwriters[msg.sender].approvalAmount >= amount_, CreditTalentCenter_insufficientUnderwritingPower());

        address rateModel = iRateWad_ == FLOATING_RATE ? adpativeIrm : address(fixedRateIrms[iRateWad_]);
        if (rateModel == address(0)) revert CreditTalentCenter_invalidInterestRate();

        underwriters[msg.sender].approvalAmount -= amount_;
        creditShares[msg.sender] += amount_;
        totalcreditShares += amount_;

        _applicationInfo[user_].status = ApplicationStatus.Approved;
        _applicationInfo[user_].underwriter = msg.sender;
        _applicationInfo[user_].irm = rateModel;

        underwriters[msg.sender].approvedApplicants.push(user_);

        MarketParams memory marketParams =
            MarketParams(underwritingAsset, creditPoints, address(this), rateModel, DEFAULT_LLTV);
        IERC20(creditPoints).approve(address(morpho), amount_);
        morpho.supplyCollateral(marketParams, amount_, user_, "");
        IERC20(underwritingAsset).approve(address(morpho), amount_);
        morpho.supply(marketParams, amount_, 0, address(this), "");
        emit ApplicationApproved(applicationId_, user_, msg.sender, amount_, iRateWad_);
    }

    function rejectCredit(address user_, uint256 applicationId_, string memory reason_)
        external
        onlyRole(UNDERWRITER_ROLE)
    {
        require(_applicationInfo[user_].id == applicationId_, CreditTalentCenter_invalidApplicationId());
        require(_applicationInfo[user_].status == ApplicationStatus.Pending, CreditTalentCenter_applicationNotPending());
        _applicationInfo[user_].status = ApplicationStatus.Rejected;
        emit ApplicationRejected(applicationId_, user_, msg.sender, reason_);
    }

    function setFixedRateIrms(uint256 newBorrowRate_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFixedRateIrms(newBorrowRate_);
    }

    function _setFixedRateIrms(uint256 newBorrowRate_) internal returns (FixedRateIrm) {
        require(address(fixedRateIrms[newBorrowRate_]) == address(0), CrediTalentCenter_fixedRateIrmAlreadyExists());
        FixedRateIrm firm = new FixedRateIrm(newBorrowRate_);
        fixedRateIrms[newBorrowRate_] = firm;
        emit FixedRateIrmSet(newBorrowRate_, address(firm));
        return firm;
    }

    function _checkZeroAddress(address addr_) internal pure {
        if (addr_ == address(0)) {
            revert CrediTalentCenter_zeroAddress();
        }
    }

    function _useApplicationNumber() internal returns (uint256) {
        applications += 1;
        return applications;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
