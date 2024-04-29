// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IVoter {
    function isGauge(address) external view returns (bool);

    function feeDistributors(address) external view returns (address);
}

error NotWarden();
error NotAllowed();
error ConversionsDisabled();
error InsufficientBalance();

contract NuriPetals is ERC20("Nuri Petals", "PTL") {
    address public warden;
    uint256 public snapshottedPetals;
    uint256 public nuriAllocated;
    uint256 public constant PRECISION = 100;
    IERC20 public Nuri;
    IVoter public voter;

    bool public conversions;

    event Converted(address, uint256);

    mapping(address => bool) allowed;
    mapping(address => uint256) convertedAmount;

    modifier onlyWarden() {
        if (msg.sender != warden) revert NotWarden();
        _;
    }

    constructor(address _warden, address _voter) {
        warden = _warden;
        voter = IVoter(_voter);
    }

    ///@dev overriden _update to check for WL'd status prior to transfer
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override {
        if (!isAllowed(from)) revert NotAllowed();
        super._update(from, to, value);
    }

    ///@notice set a warden address
    function setWarden(address _newWarden) external onlyWarden {
        warden = _newWarden;
    }

    ///@notice allows the warden to declare an address as WL'd
    function setAllowed(address _wallet, bool _status) external onlyWarden {
        allowed[_wallet] = _status;
    }

    ///@notice permissioned mint function gated by the warden address
    function mintPetals(uint256 _petals) external onlyWarden {
        _mint(msg.sender, _petals);
    }

    ///@notice permissioned burn function gated by the warden address
    function burnPetalsOf(address _wallet, uint256 _petals)
        external
        onlyWarden
    {
        if (_petals == 0) {
            _burn(_wallet, balanceOf(_wallet));
            return;
        }
        _burn(_wallet, _petals);
        return;
    }

    ///@notice enable conversions from Petals into Tokens, and if Nuri is uninitialized, define the address
    function enableConversions(address _nuri) external onlyWarden {
        if (address(Nuri) == address(0)) Nuri = IERC20(_nuri);
        snapshottedPetals = totalSupply();
        conversions = true;
    }

    ///@notice disable conversions from Petals into Tokens
    function disableConversions() external onlyWarden {
        conversions = false;
    }

    ///@notice if the snapshotted amount is incorrect for some reason, redefine
    function forceSnapshot() external onlyWarden {
        snapshottedPetals = totalSupply();
    }

    ///@notice after the Nuri token is live, users can convert Nuri Petals to Nuri Tokens
    function convert(uint256 _amount) external {
        if (!conversions) revert ConversionsDisabled();
        if (!(balanceOf(msg.sender) >= _amount)) revert InsufficientBalance();
        _burn(msg.sender, _amount);
        Nuri.transfer(msg.sender, getConversionOf(_amount));
        convertedAmount[msg.sender] += _amount;
        emit Converted(msg.sender, _amount);
    }

    ///@notice returns a boolean if the "from" address in a transfer is WL'd
    function isAllowed(address _wallet) public view returns (bool) {
        if (!allowed[_wallet] && _wallet != address(0)) {
            if (voter.isGauge(_wallet)) return true;
            return false;
        }
        return true;
    }

    ///@notice returns the expected amount of Nuri claimable post conversion
    function getConversionOf(uint256 _petals) public view returns (uint256) {
        return ((((nuriAllocated * PRECISION) / snapshottedPetals) * _petals) /
            PRECISION);
    }
}
