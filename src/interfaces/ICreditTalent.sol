// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMorpho} from "@morpho/contracts/interfaces/IMorpho.sol";

enum ApplicationStatus {
    None,
    Pending,
    Approved,
    Rejected
}

struct Underwriter {
    address underwriter;
    uint256 approvalAmount;
    address[] approvedApplicants;
}

struct Application {
    uint256 id;
    address applicant;
    bytes32 dataHash;
    address underwriter;
    ApplicationStatus status;
    address irm;
}

interface ICreditTalent {
    /// Events
    event ApplicationCreated(uint256 id, address indexed applicant, bytes32 dataHash);
    event ApplicationApproved(
        uint256 id, address indexed applicant, address indexed underwriter, uint256 amount, uint256 interestRate
    );
    event ApplicationRejected(uint256 id, address indexed applicant, address indexed underwriter, string reason);
    event UnderwriterSet(address indexed account, uint256 approvalPower);
    event FixedRateIrmSet(uint256 indexed interestRate, address irm);

    /// Custom errors
    error CrediTalentCenter_zeroAddress();
    error CrediTalentCenter_applicationAlreadyExists();
    error CrediTalentCenter_fixedRateIrmAlreadyExists();
    error CreditTalentCenter_invalidApplicationId();
    error CreditTalentCenter_applicationNotPending();
    error CreditTalentCenter_insufficientUnderwritingPower();
    error CreditTalentCenter_invalidInterestRate();

    /// View
    function underwritingAsset() external view returns (address);
    function creditPoints() external view returns (address);
    function DEFAULT_LLTV() external view returns (uint256);
    function adpativeIrm() external view returns (address);
    function morpho() external view returns (IMorpho);
    function applicationInfo(address user) external view returns (Application memory);
    function creditShares(address underwriter) external view returns (uint256);
}
