// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Parcel} from "../src/Parcel.sol";
import {ParcelAuction} from "../src/ParcelAuction.sol";

contract LegacyFixture {}

abstract contract ParcelFixture is Test {
    Parcel internal parcel;
    ParcelAuction internal auction;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal treasury = address(0x777);
    address internal legacy;
    Parcel.Bounds internal bounds = Parcel.Bounds(-10, 0, -10, 10, 20, 10);
    bytes32 internal first;
    bytes32 internal second;
    bytes32 internal root;

    function setUp() public virtual {
        vm.chainId(1);
        vm.roll(100);
        vm.warp(1_000_000);
        legacy = address(new LegacyFixture());
        parcel = new Parcel(address(this), legacy, 90, "ipfs://metadata/");
        auction = new ParcelAuction(address(this), parcel, treasury);
        parcel.configureAuctionHouse(address(auction));
        first = leaf(0, alice);
        second = leaf(2, bob);
        root = first < second ? keccak256(abi.encode(first, second)) : keccak256(abi.encode(second, first));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function leaf(uint256 id, address account) internal view returns (bytes32) {
        return keccak256(
            bytes.concat(keccak256(abi.encode(uint256(1), legacy, uint256(90), id, account, bounds, "ipfs://scene")))
        );
    }

    function proof(uint256 id) internal view returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = id == 0 ? second : first;
    }

    function claimFirst() internal {
        vm.prank(alice);
        parcel.claim(0, alice, bounds, "ipfs://scene", proof(0));
    }

    function openAndEndClaims() internal {
        parcel.openClaims(root);
        vm.warp(parcel.claimEndsAt());
    }
}

contract ParcelTest is ParcelFixture {
    function testERC721MetadataAndTokenZero() public {
        assertTrue(parcel.supportsInterface(0x80ac58cd));
        assertTrue(parcel.supportsInterface(0x5b5e139f));
        assertTrue(parcel.supportsInterface(0x01ffc9a7));
        assertFalse(parcel.supportsInterface(0xffffffff));
        parcel.openClaims(root);
        claimFirst();
        assertEq(parcel.ownerOf(0), alice);
        assertEq(parcel.balanceOf(alice), 1);
        assertEq(parcel.totalSupply(), 1);
        assertEq(parcel.tokenURI(0), "ipfs://metadata/0");
        assertEq(parcel.contentURI(0), "ipfs://scene");
        (int16 x1,,,, int16 y2,) = parcel.getBoundingBox(0);
        assertEq(x1, -10);
        assertEq(y2, 20);
    }

    function testWindowStartsAtLaunchAndIsExactly30Days() public {
        vm.warp(block.timestamp + 10 days);
        assertEq(parcel.claimEndsAt(), 0);
        vm.expectRevert(Parcel.ClaimsClosed.selector);
        claimFirst();
        parcel.openClaims(root);
        assertEq(parcel.claimStartsAt(), block.timestamp);
        assertEq(parcel.claimEndsAt(), block.timestamp + 30 days);
        vm.warp(parcel.claimEndsAt() - 1);
        claimFirst();
        vm.warp(parcel.claimEndsAt());
        vm.expectRevert(Parcel.ClaimsClosed.selector);
        vm.prank(bob);
        parcel.claim(2, bob, bounds, "ipfs://scene", proof(2));
    }

    function testLaunchIsOwnerOnlyAndCannotBeReopened() public {
        vm.expectRevert();
        vm.prank(alice);
        parcel.openClaims(root);
        vm.expectRevert(Parcel.InvalidConfiguration.selector);
        parcel.openClaims(bytes32(0));
        parcel.openClaims(root);
        vm.warp(parcel.claimEndsAt());
        vm.expectRevert(Parcel.AlreadyLaunched.selector);
        parcel.openClaims(root);
    }

    function testProofBindsOwnerTokenBoundsAndContent() public {
        parcel.openClaims(root);
        vm.expectRevert(Parcel.InvalidProof.selector);
        vm.prank(bob);
        parcel.claim(0, bob, bounds, "ipfs://scene", proof(0));
        vm.startPrank(alice);
        vm.expectRevert(Parcel.InvalidProof.selector);
        parcel.claim(1, alice, bounds, "ipfs://scene", proof(0));
        vm.expectRevert(Parcel.InvalidProof.selector);
        parcel.claim(0, alice, bounds, "ipfs://different", proof(0));
        Parcel.Bounds memory changed = bounds;
        changed.x2 = 11;
        vm.expectRevert(Parcel.InvalidProof.selector);
        parcel.claim(0, alice, changed, "ipfs://scene", proof(0));
        vm.stopPrank();
    }

    function testDuplicateCannotMintAgainAfterTransfer() public {
        parcel.openClaims(root);
        claimFirst();
        vm.prank(alice);
        parcel.transferFrom(alice, bob, 0);
        vm.expectRevert();
        claimFirst();
        assertEq(parcel.totalSupply(), 1);
        assertEq(parcel.ownerOf(0), bob);
    }

    function testApprovalsTransfersAndSceneOwnership() public {
        parcel.openClaims(root);
        claimFirst();
        vm.prank(alice);
        parcel.approve(bob, 0);
        vm.expectRevert(Parcel.NotTokenOwner.selector);
        vm.prank(bob);
        parcel.setContentURI(0, "unauthorized");
        vm.prank(bob);
        parcel.safeTransferFrom(alice, bob, 0);
        assertEq(parcel.getApproved(0), address(0));
        vm.prank(bob);
        parcel.setContentURI(0, "ipfs://updated");
        assertEq(parcel.contentURI(0), "ipfs://updated");
        vm.expectRevert(Parcel.NotTokenOwner.selector);
        vm.prank(alice);
        parcel.setContentURI(0, "old owner");
    }

    function testRejectedReceiverDoesNotConsumeClaim() public {
        parcel.openClaims(root);
        vm.prank(alice);
        vm.expectRevert();
        parcel.claim(0, address(this), bounds, "ipfs://scene", proof(0));
        assertFalse(parcel.exists(0));
        assertEq(parcel.totalSupply(), 0);
        claimFirst();
    }

    function testUnknownMetadataReverts() public {
        vm.expectRevert();
        parcel.tokenURI(1);
        vm.expectRevert();
        parcel.contentURI(1);
        vm.expectRevert();
        parcel.getBoundingBox(1);
    }

    function testAdminCannotMintReservedParcelOrReplaceAuction() public {
        parcel.openClaims(root);
        vm.expectRevert(Parcel.AuctionUnavailable.selector);
        parcel.configureAuctionHouse(address(auction));
        vm.expectRevert(Parcel.AuctionUnavailable.selector);
        parcel.mintFromAuction(0, alice, alice, bounds, "ipfs://scene", proof(0));
        vm.warp(parcel.claimEndsAt());
        vm.expectRevert(Parcel.AuctionUnavailable.selector);
        parcel.mintFromAuction(0, alice, alice, bounds, "ipfs://scene", proof(0));
        assertFalse(parcel.exists(0));
    }

    function testTwoStepOwnership() public {
        parcel.transferOwnership(alice);
        assertEq(parcel.owner(), address(this));
        vm.prank(alice);
        parcel.acceptOwnership();
        assertEq(parcel.owner(), alice);
    }

    function testRejectsWrongChainAndInvalidSnapshot() public {
        vm.expectRevert(Parcel.InvalidConfiguration.selector);
        new Parcel(address(this), legacy, 100, "ipfs://m/");
        vm.chainId(137);
        vm.expectRevert(Parcel.InvalidConfiguration.selector);
        new Parcel(address(this), legacy, 90, "ipfs://m/");
    }
}

contract AuctionTest is ParcelFixture {
    function create() internal {
        auction.createAuction(0, alice, bounds, "ipfs://scene", proof(0), 1 ether, 1 days);
    }

    function endTime() internal view returns (uint256 end) {
        (,, end,,,) = auction.auctions(0);
    }

    function testAuctionDisabledUntilExplicitPostWindowActivation() public {
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        auction.enableAuctions();
        parcel.openClaims(root);
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        auction.enableAuctions();
        vm.warp(parcel.claimEndsAt());
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        create();
        vm.prank(alice);
        vm.expectRevert();
        auction.enableAuctions();
        auction.enableAuctions();
        create();
        assertTrue(auction.enabled());
    }

    function testClaimedAndUnknownParcelsCannotBeAuctioned() public {
        parcel.openClaims(root);
        claimFirst();
        vm.warp(parcel.claimEndsAt());
        auction.enableAuctions();
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        create();
        vm.expectRevert(ParcelAuction.InvalidConfiguration.selector);
        auction.createAuction(1, alice, bounds, "ipfs://scene", proof(0), 1 ether, 1 days);
    }

    function testBidsRefundsSettlementAndWinnerDelivery() public {
        openAndEndClaims();
        auction.enableAuctions();
        create();
        vm.prank(alice);
        auction.bid{value: 1 ether}(0);
        vm.prank(bob);
        vm.expectRevert(ParcelAuction.BidTooLow.selector);
        auction.bid{value: 1.01 ether}(0);
        vm.prank(bob);
        auction.bid{value: 1.05 ether}(0);
        assertEq(auction.credits(alice), 1 ether);
        vm.prank(alice);
        auction.withdrawCredit(payable(alice));
        assertEq(alice.balance, 100 ether);
        vm.warp(endTime());
        auction.settle(0);
        assertEq(auction.credits(treasury), 1.05 ether);
        vm.prank(alice);
        vm.expectRevert(ParcelAuction.NotWinner.selector);
        auction.claimWonParcel(0, alice, alice, bounds, "ipfs://scene", proof(0));
        vm.prank(bob);
        auction.claimWonParcel(0, bob, alice, bounds, "ipfs://scene", proof(0));
        assertEq(parcel.ownerOf(0), bob);
        vm.prank(treasury);
        auction.withdrawCredit(payable(treasury));
        assertEq(treasury.balance, 1.05 ether);
        assertEq(address(auction).balance, 0);
        vm.prank(bob);
        vm.expectRevert(ParcelAuction.NotWinner.selector);
        auction.claimWonParcel(0, bob, alice, bounds, "ipfs://scene", proof(0));
    }

    function testLateBidExtendsAuction() public {
        openAndEndClaims();
        auction.enableAuctions();
        create();
        uint256 originalEnd = endTime();
        vm.warp(originalEnd - 1);
        vm.prank(alice);
        auction.bid{value: 1 ether}(0);
        assertEq(endTime(), block.timestamp + 15 minutes);
        vm.warp(originalEnd);
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        auction.settle(0);
    }

    function testNoBidAuctionCanBeRelistedButSoldAuctionCannot() public {
        openAndEndClaims();
        auction.enableAuctions();
        create();
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        create();
        vm.warp(endTime());
        auction.settle(0);
        create();
        vm.prank(alice);
        auction.bid{value: 1 ether}(0);
        vm.warp(endTime());
        auction.settle(0);
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        create();
    }

    function testRejectedWinnerReceiverCanRetry() public {
        openAndEndClaims();
        auction.enableAuctions();
        create();
        vm.prank(alice);
        auction.bid{value: 1 ether}(0);
        vm.warp(endTime());
        auction.settle(0);
        vm.prank(alice);
        vm.expectRevert();
        auction.claimWonParcel(0, address(this), alice, bounds, "ipfs://scene", proof(0));
        vm.prank(alice);
        auction.claimWonParcel(0, alice, alice, bounds, "ipfs://scene", proof(0));
        assertEq(parcel.ownerOf(0), alice);
    }

    function testBidAtDeadlineAndRepeatedSettlementRevert() public {
        openAndEndClaims();
        auction.enableAuctions();
        create();
        vm.warp(endTime());
        vm.prank(alice);
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        auction.bid{value: 1 ether}(0);
        auction.settle(0);
        vm.expectRevert(ParcelAuction.Unavailable.selector);
        auction.settle(0);
    }
}
