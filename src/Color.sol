// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Mainnet} from "./Mainnet.sol";

/// @notice Whole-unit Color tokens. Staked value follows ownership of the new parcel.
contract Color is ERC20, Ownable2Step, Mainnet {
    IERC721 public immutable parcel;
    bool public mintingFinished;
    uint256 public totalStaked;
    mapping(uint256 => uint256) private stakes;

    error InvalidParcel();
    error Unauthorized();
    error MintingFinished();
    error InvalidAmount();

    event Staked(address indexed account, uint256 indexed tokenId, uint256 amount);
    event Withdrawn(address indexed account, uint256 indexed tokenId, uint256 amount);
    event MintFinished();

    constructor(address initialOwner, IERC721 collection) ERC20("Voxels Color", "COLR") Ownable(initialOwner) {
        if (address(collection).code.length == 0) revert InvalidParcel();
        parcel = collection;
    }

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function mint(address recipient, uint256 amount) external onlyOwner {
        if (mintingFinished) revert MintingFinished();
        _mint(recipient, amount);
    }

    function finishMinting() external onlyOwner {
        if (mintingFinished) revert MintingFinished();
        mintingFinished = true;
        emit MintFinished();
    }

    function getStake(uint256 tokenId) external view returns (uint256) {
        return stakes[tokenId];
    }

    function stake(address from, uint256 amount, uint256 tokenId) external {
        if (from != msg.sender) revert Unauthorized();
        if (amount == 0) revert InvalidAmount();
        parcel.ownerOf(tokenId); // Only existing parcels can hold a stake.
        _burn(from, amount);
        stakes[tokenId] += amount;
        totalStaked += amount;
        emit Staked(from, tokenId, amount);
    }

    /// @dev Returning already-staked value remains available after administrative minting closes.
    function withdraw(address recipient, uint256 amount, uint256 tokenId) external {
        if (parcel.ownerOf(tokenId) != msg.sender) revert Unauthorized();
        if (amount == 0 || amount > stakes[tokenId]) revert InvalidAmount();
        stakes[tokenId] -= amount;
        totalStaked -= amount;
        _mint(recipient, amount);
        emit Withdrawn(recipient, tokenId, amount);
    }
}
