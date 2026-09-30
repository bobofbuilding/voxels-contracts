// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Mainnet} from "./Mainnet.sol";

/// @notice Each new wearable ID has a fixed initial edition size; no privileged operator approvals.
contract Collectibles is ERC1155Supply, Ownable2Step, Mainnet {
    string public constant name = "Voxels Collectibles";
    uint256 public latestTokenId;
    error InvalidEdition();
    error EmptyMetadataURI();
    event MetadataURIUpdated(string uri);

    constructor(address initialOwner, string memory metadataURI) ERC1155(metadataURI) Ownable(initialOwner) {
        if (bytes(metadataURI).length == 0) revert EmptyMetadataURI();
    }

    function mint(address recipient, uint256 quantity, bytes calldata data) external onlyOwner returns (uint256 id) {
        if (quantity == 0) revert InvalidEdition();
        id = ++latestTokenId;
        _mint(recipient, id, quantity, data);
    }

    function setURI(string calldata metadataURI) external onlyOwner {
        if (bytes(metadataURI).length == 0) revert EmptyMetadataURI();
        _setURI(metadataURI);
        emit MetadataURIUpdated(metadataURI);
    }
}
