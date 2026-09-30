// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Mainnet} from "./Mainnet.sol";

/// @notice Fresh mainnet name registry. Legacy names require a separate migration plan.
contract Name is ERC721, Mainnet {
    uint256 public totalSupply;
    mapping(bytes32 => uint256) private canonicalNames;
    mapping(uint256 => string) private names;
    string private metadataBaseURI;

    error InvalidName();
    error NameTaken();
    error EmptyMetadataURI();

    constructor(string memory baseURI) ERC721("Voxels Names", "VNAME") {
        if (bytes(baseURI).length == 0) revert EmptyMetadataURI();
        metadataBaseURI = baseURI;
    }

    function mint(address recipient, string calldata value) external returns (uint256 tokenId) {
        bytes32 key = _canonicalKey(value);
        if (canonicalNames[key] != 0) revert NameTaken();
        tokenId = ++totalSupply;
        canonicalNames[key] = tokenId;
        names[tokenId] = value;
        _safeMint(recipient, tokenId);
    }

    function getName(uint256 tokenId) external view returns (string memory) {
        _requireOwned(tokenId);
        return names[tokenId];
    }

    function tokenIdForName(string calldata value) external view returns (uint256) {
        return canonicalNames[_canonicalKey(value)];
    }

    function _canonicalKey(string memory value) private pure returns (bytes32) {
        bytes memory text = bytes(value);
        if (text.length < 3 || text.length > 20) revert InvalidName();
        for (uint256 i; i < text.length; ++i) {
            uint8 c = uint8(text[i]);
            if (c >= 65 && c <= 90) {
                text[i] = bytes1(c + 32);
            } else if (!((c >= 97 && c <= 122) || (c >= 48 && c <= 57)
                        || ((c == 45 || c == 95) && i != 0 && i != text.length - 1))) {
                revert InvalidName();
            }
        }
        return keccak256(text);
    }

    function _baseURI() internal view override returns (string memory) {
        return metadataBaseURI;
    }
}
