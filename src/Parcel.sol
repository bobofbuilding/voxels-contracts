// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice Mainnet parcels with a one-time, 30-day snapshot migration.
/// @dev Snapshot owners claim; unclaimed IDs remain reserved for the configured auction house.
contract Parcel is ERC721, Ownable2Step {
    struct Bounds {
        int16 x1;
        int16 y1;
        int16 z1;
        int16 x2;
        int16 y2;
        int16 z2;
    }

    uint256 public constant CLAIM_DURATION = 30 days;
    address public immutable legacyContract;
    uint256 public immutable snapshotBlock;
    bytes32 public merkleRoot;
    uint256 public claimStartsAt;
    uint256 public claimEndsAt;
    uint256 public totalSupply;
    string private metadataBaseURI;
    address public auctionHouse;
    mapping(uint256 => Bounds) private bounds;
    mapping(uint256 => string) private contentURIs;

    error InvalidConfiguration();
    error AlreadyLaunched();
    error ClaimsClosed();
    error InvalidProof();
    error NotTokenOwner();
    error AuctionUnavailable();

    event AuctionHouseConfigured(address indexed auctionHouse);
    event ClaimsOpened(bytes32 indexed root, uint256 startsAt, uint256 endsAt);
    event ParcelClaimed(uint256 indexed tokenId, address indexed snapshotOwner, address indexed recipient);
    event ContentURIUpdated(uint256 indexed tokenId, string uri);

    constructor(address initialOwner, address source, uint256 snapshot, string memory baseURI)
        ERC721("Voxels Parcels", "VOXEL")
        Ownable(initialOwner)
    {
        if (
            block.chainid != 1 || source == address(0) || source.code.length == 0 || snapshot == 0
                || snapshot >= block.number || bytes(baseURI).length == 0
        ) {
            revert InvalidConfiguration();
        }
        legacyContract = source;
        snapshotBlock = snapshot;
        metadataBaseURI = baseURI;
    }

    /// @notice Call once, only when the public claim site and proof files are ready.
    function openClaims(bytes32 root) external onlyOwner {
        if (claimStartsAt != 0) revert AlreadyLaunched();
        if (root == bytes32(0) || auctionHouse == address(0)) revert InvalidConfiguration();
        merkleRoot = root;
        claimStartsAt = block.timestamp;
        claimEndsAt = block.timestamp + CLAIM_DURATION;
        emit ClaimsOpened(root, claimStartsAt, claimEndsAt);
    }

    /// @notice Only the snapshot owner may claim, including to another receiving wallet.
    /// @dev StandardMerkleTree double-hashed leaf. Bounds and scene URI are bound into the proof.
    function claim(
        uint256 tokenId,
        address recipient,
        Bounds calldata parcelBounds,
        string calldata sceneURI,
        bytes32[] calldata proof
    ) external {
        if (claimStartsAt == 0 || block.timestamp >= claimEndsAt) revert ClaimsClosed();
        if (!verifyParcel(tokenId, msg.sender, parcelBounds, sceneURI, proof)) revert InvalidProof();
        _mintParcel(tokenId, recipient, parcelBounds, sceneURI);
        emit ParcelClaimed(tokenId, msg.sender, recipient);
    }

    /// @notice Fix the auction house before launch. It cannot later be replaced.
    function configureAuctionHouse(address house) external onlyOwner {
        if (
            claimStartsAt != 0 || auctionHouse != address(0) || house.code.length == 0
                || address(IParcelAuction(house).parcel()) != address(this)
        ) revert AuctionUnavailable();
        auctionHouse = house;
        emit AuctionHouseConfigured(house);
    }

    function mintFromAuction(
        uint256 tokenId,
        address snapshotOwner,
        address recipient,
        Bounds calldata parcelBounds,
        string calldata sceneURI,
        bytes32[] calldata proof
    ) external {
        if (msg.sender != auctionHouse || claimStartsAt == 0 || block.timestamp < claimEndsAt) {
            revert AuctionUnavailable();
        }
        if (!verifyParcel(tokenId, snapshotOwner, parcelBounds, sceneURI, proof)) revert InvalidProof();
        _mintParcel(tokenId, recipient, parcelBounds, sceneURI);
    }

    function verifyParcel(
        uint256 tokenId,
        address snapshotOwner,
        Bounds calldata parcelBounds,
        string calldata sceneURI,
        bytes32[] calldata proof
    ) public view returns (bool) {
        if (
            snapshotOwner == address(0) || parcelBounds.x1 >= parcelBounds.x2 || parcelBounds.y1 >= parcelBounds.y2
                || parcelBounds.z1 >= parcelBounds.z2
        ) return false;
        bytes32 leaf = keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        uint256(1), legacyContract, snapshotBlock, tokenId, snapshotOwner, parcelBounds, sceneURI
                    )
                )
            )
        );
        return MerkleProof.verifyCalldata(proof, merkleRoot, leaf);
    }

    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function _mintParcel(uint256 tokenId, address recipient, Bounds calldata parcelBounds, string calldata sceneURI)
        private
    {
        // Initialize parcel data before the ERC-721 receiver callback.
        bounds[tokenId] = parcelBounds;
        contentURIs[tokenId] = sceneURI;
        totalSupply += 1;
        _safeMint(recipient, tokenId);
    }

    function getBoundingBox(uint256 tokenId) external view returns (int16, int16, int16, int16, int16, int16) {
        _requireOwned(tokenId);
        Bounds memory b = bounds[tokenId];
        return (b.x1, b.y1, b.z1, b.x2, b.y2, b.z2);
    }

    function setContentURI(uint256 tokenId, string calldata uri) external {
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        contentURIs[tokenId] = uri;
        emit ContentURIUpdated(tokenId, uri);
    }

    function contentURI(uint256 tokenId) external view returns (string memory) {
        _requireOwned(tokenId);
        return contentURIs[tokenId];
    }

    function _baseURI() internal view override returns (string memory) {
        return metadataBaseURI;
    }
}

interface IParcelAuction {
    function parcel() external view returns (Parcel);
}
