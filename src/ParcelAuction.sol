// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Parcel} from "./Parcel.sol";

/// @notice ETH ascending auctions for unclaimed snapshot parcels. Disabled at deployment.
contract ParcelAuction is Ownable2Step, ReentrancyGuard {
    struct Auction {
        uint256 reservePrice;
        uint256 highestBid;
        uint256 endsAt;
        address highestBidder;
        bool settled;
        bool delivered;
    }

    Parcel public immutable parcel;
    address public immutable treasury;
    bool public enabled;
    uint256 public constant EXTENSION = 15 minutes;
    mapping(uint256 => Auction) public auctions;
    mapping(address => uint256) public credits;

    error InvalidConfiguration();
    error Unavailable();
    error BidTooLow();
    error NotWinner();
    error TransferFailed();

    event AuctionsEnabled();
    event AuctionCreated(uint256 indexed tokenId, uint256 reservePrice, uint256 endsAt);
    event BidPlaced(uint256 indexed tokenId, address indexed bidder, uint256 amount, uint256 endsAt);
    event AuctionSettled(uint256 indexed tokenId, address indexed winner, uint256 amount);
    event ParcelDelivered(uint256 indexed tokenId, address indexed recipient);
    event CreditWithdrawn(address indexed account, address indexed recipient, uint256 amount);

    constructor(address initialOwner, Parcel collection, address proceedsRecipient) Ownable(initialOwner) {
        if (block.chainid != 1 || address(collection).code.length == 0 || proceedsRecipient == address(0)) {
            revert InvalidConfiguration();
        }
        parcel = collection;
        treasury = proceedsRecipient;
    }

    function enableAuctions() external onlyOwner {
        if (
            enabled || parcel.claimEndsAt() == 0 || block.timestamp < parcel.claimEndsAt()
                || parcel.auctionHouse() != address(this)
        ) revert Unavailable();
        enabled = true;
        emit AuctionsEnabled();
    }

    /// @notice A no-bid auction can be relisted after settlement. A sold parcel cannot.
    function createAuction(
        uint256 tokenId,
        address snapshotOwner,
        Parcel.Bounds calldata bounds,
        string calldata sceneURI,
        bytes32[] calldata proof,
        uint256 reservePrice,
        uint256 duration
    ) external onlyOwner {
        Auction storage previous = auctions[tokenId];
        if (
            !enabled || parcel.exists(tokenId)
                || (previous.endsAt != 0 && (!previous.settled || previous.highestBidder != address(0)))
        ) revert Unavailable();
        if (reservePrice == 0 || duration < 1 days || duration > 30 days) revert InvalidConfiguration();
        if (!parcel.verifyParcel(tokenId, snapshotOwner, bounds, sceneURI, proof)) revert InvalidConfiguration();
        uint256 end = block.timestamp + duration;
        auctions[tokenId] = Auction(reservePrice, 0, end, address(0), false, false);
        emit AuctionCreated(tokenId, reservePrice, end);
    }

    /// @notice Every bid deposits its full value; displaced bids become withdrawable credits.
    function bid(uint256 tokenId) external payable nonReentrant {
        Auction storage a = auctions[tokenId];
        if (a.endsAt == 0 || a.settled || block.timestamp >= a.endsAt) revert Unavailable();
        uint256 increment = a.highestBid / 20;
        if (increment == 0) increment = 1;
        uint256 minimum = a.highestBidder == address(0) ? a.reservePrice : a.highestBid + increment;
        if (msg.value < minimum) revert BidTooLow();
        if (a.highestBidder != address(0)) credits[a.highestBidder] += a.highestBid;
        a.highestBidder = msg.sender;
        a.highestBid = msg.value;
        if (a.endsAt - block.timestamp < EXTENSION) a.endsAt = block.timestamp + EXTENSION;
        emit BidPlaced(tokenId, msg.sender, msg.value, a.endsAt);
    }

    function settle(uint256 tokenId) external {
        Auction storage a = auctions[tokenId];
        if (a.endsAt == 0 || a.settled || block.timestamp < a.endsAt) revert Unavailable();
        a.settled = true;
        credits[treasury] += a.highestBid;
        emit AuctionSettled(tokenId, a.highestBidder, a.highestBid);
    }

    /// @notice Winner selects a receiving wallet; failed receiver callbacks can be retried.
    function claimWonParcel(
        uint256 tokenId,
        address recipient,
        address snapshotOwner,
        Parcel.Bounds calldata bounds,
        string calldata sceneURI,
        bytes32[] calldata proof
    ) external nonReentrant {
        Auction storage a = auctions[tokenId];
        if (!a.settled || a.delivered || msg.sender != a.highestBidder) revert NotWinner();
        a.delivered = true;
        parcel.mintFromAuction(tokenId, snapshotOwner, recipient, bounds, sceneURI, proof);
        emit ParcelDelivered(tokenId, recipient);
    }

    function withdrawCredit(address payable recipient) external nonReentrant {
        uint256 amount = credits[msg.sender];
        if (amount == 0 || recipient == address(0)) revert Unavailable();
        credits[msg.sender] = 0;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit CreditWithdrawn(msg.sender, recipient, amount);
    }
}
