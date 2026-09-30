// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Mainnet} from "./Mainnet.sol";

/// @notice One promotional wearable per recipient, funded with an explicit inventory transfer.
contract CollectibleDistributor is ERC1155Holder, Ownable2Step, Pausable, Mainnet {
    IERC1155 public immutable collectibles;
    mapping(address => bool) public hasClaimed;
    error InvalidCollection();
    error AlreadyClaimed();
    event WearableDistributed(address indexed recipient, uint256 indexed tokenId);

    constructor(address initialOwner, IERC1155 collection) Ownable(initialOwner) {
        if (address(collection).code.length == 0) revert InvalidCollection();
        collectibles = collection;
    }

    function sendFreeWearable(address recipient, uint256 tokenId) external onlyOwner whenNotPaused {
        if (hasClaimed[recipient]) revert AlreadyClaimed();
        hasClaimed[recipient] = true;
        collectibles.safeTransferFrom(address(this), recipient, tokenId, 1, "");
        emit WearableDistributed(recipient, tokenId);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
