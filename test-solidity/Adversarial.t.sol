// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Parcel} from "../src/Parcel.sol";
import {ParcelAuction} from "../src/ParcelAuction.sol";
import {ParcelFixture} from "./Parcel.t.sol";

contract RecursiveReceiver is IERC721Receiver {
    Parcel private parcel;
    bool public duplicateRejected;
    bool public metadataInitialized;
    Parcel.Bounds private bounds;

    constructor(Parcel collection, Parcel.Bounds memory b) {
        parcel = collection;
        bounds = b;
    }

    function claim() external {
        parcel.claim(0, address(this), bounds, "ipfs://scene", new bytes32[](0));
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        metadataInitialized = keccak256(bytes(parcel.contentURI(0))) == keccak256("ipfs://scene")
            && parcel.ownerOf(0) == address(this) && parcel.totalSupply() == 1;
        try parcel.claim(0, address(this), bounds, "ipfs://scene", new bytes32[](0)) {
            duplicateRejected = false;
        } catch {
            duplicateRejected = true;
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract RefundReceiver {
    ParcelAuction private auction;
    bool public reject;
    bool public reentryRejected;

    constructor(ParcelAuction house) {
        auction = house;
    }

    function placeBid() external payable {
        auction.bid{value: msg.value}(0);
    }

    function withdraw(bool rejecting) external {
        reject = rejecting;
        auction.withdrawCredit(payable(address(this)));
    }

    receive() external payable {
        require(!reject, "reject refund");
        try auction.withdrawCredit(payable(address(this))) {
            reentryRejected = false;
        } catch {
            reentryRejected = true;
        }
    }
}

contract AdversarialTest is ParcelFixture {
    function testReceiverSeesInitializedDataAndCannotDuplicateClaim() public {
        RecursiveReceiver receiver = new RecursiveReceiver(parcel, bounds);
        parcel.openClaims(leaf(0, address(receiver)));
        receiver.claim();
        assertTrue(receiver.duplicateRejected());
        assertTrue(receiver.metadataInitialized());
        assertEq(parcel.totalSupply(), 1);
    }

    function testRefundRejectionAndReentryPreserveEscrow() public {
        openAndEndClaims();
        auction.enableAuctions();
        auction.createAuction(0, alice, bounds, "ipfs://scene", proof(0), 1 ether, 1 days);
        RefundReceiver bidder = new RefundReceiver(auction);
        vm.deal(address(this), 1 ether);
        bidder.placeBid{value: 1 ether}();
        vm.prank(alice);
        auction.bid{value: 1.05 ether}(0);
        vm.expectRevert(ParcelAuction.TransferFailed.selector);
        bidder.withdraw(true);
        assertEq(auction.credits(address(bidder)), 1 ether);
        assertEq(address(auction).balance, 2.05 ether);
        bidder.withdraw(false);
        assertTrue(bidder.reentryRejected());
        assertEq(auction.credits(address(bidder)), 0);
        assertEq(address(auction).balance, 1.05 ether);
    }

    function testMalformedBoundsEvenWithValidRootCannotMint() public {
        bounds.x2 = bounds.x1;
        parcel.openClaims(leaf(0, alice));
        vm.prank(alice);
        vm.expectRevert(Parcel.InvalidProof.selector);
        parcel.claim(0, alice, bounds, "ipfs://scene", new bytes32[](0));
        assertEq(parcel.totalSupply(), 0);
        vm.warp(parcel.claimEndsAt());
        auction.enableAuctions();
        vm.expectRevert(ParcelAuction.InvalidConfiguration.selector);
        auction.createAuction(0, alice, bounds, "ipfs://scene", new bytes32[](0), 1 ether, 1 days);
    }

    function testLaunchRequiresAuctionBindingAndBindingIsOneTime() public {
        Parcel unconfigured = new Parcel(address(this), legacy, 90, "ipfs://m/");
        vm.expectRevert(Parcel.InvalidConfiguration.selector);
        unconfigured.openClaims(root);
        vm.expectRevert(Parcel.AuctionUnavailable.selector);
        unconfigured.configureAuctionHouse(address(auction));
        ParcelAuction house = new ParcelAuction(address(this), unconfigured, treasury);
        unconfigured.configureAuctionHouse(address(house));
        vm.expectRevert(Parcel.AuctionUnavailable.selector);
        unconfigured.configureAuctionHouse(address(house));
    }

    function testInvalidAuctionTermsAndProofsCannotList() public {
        openAndEndClaims();
        auction.enableAuctions();
        vm.expectRevert(ParcelAuction.InvalidConfiguration.selector);
        auction.createAuction(0, alice, bounds, "ipfs://scene", proof(0), 0, 1 days);
        vm.expectRevert(ParcelAuction.InvalidConfiguration.selector);
        auction.createAuction(0, alice, bounds, "ipfs://scene", proof(0), 1, 31 days);
        vm.expectRevert(ParcelAuction.InvalidConfiguration.selector);
        auction.createAuction(0, bob, bounds, "ipfs://scene", proof(0), 1, 1 days);
        vm.prank(alice);
        vm.expectRevert();
        auction.createAuction(0, alice, bounds, "ipfs://scene", proof(0), 1, 1 days);
    }
}

contract ProofCompatibilityTest is Test {
    function testJavascriptProofFixtureClaimsSuccessfullyInSolidity() public {
        vm.chainId(1);
        vm.roll(100);
        vm.warp(1_000_000);
        string memory fixture = vm.readFile("test-solidity/fixtures/claims.json");
        address source = vm.parseJsonAddress(fixture, ".legacyContract");
        vm.etch(source, hex"00");
        Parcel parcel = new Parcel(address(this), source, 90, "ipfs://m/");
        ParcelAuction auction = new ParcelAuction(address(this), parcel, address(0x777));
        parcel.configureAuctionHouse(address(auction));
        parcel.openClaims(vm.parseJsonBytes32(fixture, ".root"));
        address owner = vm.parseJsonAddress(fixture, ".claims[0].owner");
        bytes32[] memory proof = vm.parseJsonBytes32Array(fixture, ".claims[0].proof");
        Parcel.Bounds memory bounds = Parcel.Bounds(-10, 0, -10, 10, 20, 10);
        vm.prank(owner);
        parcel.claim(0, owner, bounds, "ipfs://scene", proof);
        assertEq(parcel.ownerOf(0), owner);
        owner = vm.parseJsonAddress(fixture, ".claims[1].owner");
        proof = vm.parseJsonBytes32Array(fixture, ".claims[1].proof");
        vm.prank(owner);
        parcel.claim(2, owner, bounds, "", proof);
        assertEq(parcel.ownerOf(2), owner);
        assertEq(parcel.totalSupply(), 2);
    }
}
