// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

struct CrediPointsStorage {
    uint8 decimals;
    address underWritingAsset;
    mapping(address => bool) approvedReceivers;
}

/// @custom:security-contact security@xocolatl.xyz
contract CreditPoints is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{
    /// Events
    event ApprovedTransactorSet(address indexed transactor, bool approved);

    /// Custom errors
    error CreditPoints_zeroAddress();
    error CreditPoints_zeroAmount();

    // cast keccak CrediPointsStorageLocation
    bytes32 private constant CrediPointsStorageLocation =
        0x37b77679eebf72087edeb9170a4792ec9f98e048226456d4588b7620b481c4fc;

    function _getCrediPointsStorage() private pure returns (CrediPointsStorage storage $) {
        assembly {
            $.slot := CrediPointsStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint8 decimals_, address initialOwner, address underWritingAsset_) public initializer {
        CrediPointsStorage storage $ = _getCrediPointsStorage();
        require(underWritingAsset_ != address(0), CreditPoints_zeroAddress());
        require(decimals_ > 0, CreditPoints_zeroAmount());
        $.underWritingAsset = underWritingAsset_;
        $.decimals = decimals_;

        string memory name = string(abi.encodePacked("Credit Points - ", ERC20Upgradeable.name()));
        string memory symbol = string(abi.encodePacked("cp-", ERC20Upgradeable.symbol()));

        __ERC20_init(name, symbol);
        __Ownable_init(initialOwner);
        __ERC20Permit_init(name);
        __UUPSUpgradeable_init();
        _setApprovedReceiver(initialOwner, true);
    }

    function decimals() public view override returns (uint8) {
        CrediPointsStorage storage $ = _getCrediPointsStorage();
        return $.decimals;
    }

    function setApprovedReceiver(address receiver_, bool approved_) public onlyOwner {
        _setApprovedReceiver(receiver_, approved_);
    }

    function isApprovedReceiver(address receiver_) public view returns (bool) {
        CrediPointsStorage storage $ = _getCrediPointsStorage();
        return $.approvedReceivers[receiver_];
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            require(isApprovedReceiver(to), "CrediPoints: transfer not approved");
        }
        super._update(from, to, value);
    }

    function _setApprovedReceiver(address receiver_, bool approved_) internal {
        CrediPointsStorage storage $ = _getCrediPointsStorage();
        $.approvedReceivers[receiver_] = approved_;
        emit ApprovedTransactorSet(receiver_, approved_);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
