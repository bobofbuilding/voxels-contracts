// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Name} from "../src/Name.sol";
import {Color} from "../src/Color.sol";
import {Collectibles} from "../src/Collectibles.sol";
import {CollectibleDistributor} from "../src/CollectibleDistributor.sol";
import {Mainnet} from "../src/Mainnet.sol";

contract ParcelMock is ERC721 {
    constructor() ERC721("Mock", "MOCK") {}

    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}

contract NameTest is Test {
    Name internal names;
    address internal alice = address(0xA11CE);

    function setUp() public {
        vm.chainId(1);
        names = new Name("ipfs://names/");
    }

    function testNamesAreStandard721AndPreserveDisplayCase() public {
        assertTrue(names.supportsInterface(0x80ac58cd));
        uint256 id = names.mint(alice, "Alice_123");
        assertEq(id, 1);
        assertEq(names.getName(id), "Alice_123");
        assertEq(names.tokenIdForName("ALICE_123"), id);
        assertEq(names.tokenURI(id), "ipfs://names/1");
        vm.prank(alice);
        names.transferFrom(alice, address(2), id);
        assertEq(names.ownerOf(id), address(2));
    }

    function testCaseInsensitiveUniquenessSurvivesTransfer() public {
        names.mint(alice, "Alice");
        vm.prank(alice);
        names.transferFrom(alice, address(2), 1);
        vm.expectRevert(Name.NameTaken.selector);
        names.mint(alice, "aLiCe");
    }

    function testInvalidNamesRejected() public {
        string[8] memory invalid =
            ["ab", "abcdefghijklmnopqrstu", "-abc", "abc_", "a b", "hello!", "", unicode"alice😃"];
        for (uint256 i; i < invalid.length; ++i) {
            vm.expectRevert(Name.InvalidName.selector);
            names.mint(alice, invalid[i]);
        }
    }

    function testRejectedReceiverDoesNotReserveNameOrConsumeId() public {
        vm.expectRevert();
        names.mint(address(this), "Alice");
        assertEq(names.totalSupply(), 0);
        assertEq(names.mint(alice, "alice"), 1);
    }

    function testUnknownNameMetadataReverts() public {
        vm.expectRevert();
        names.getName(1);
        vm.expectRevert();
        names.tokenURI(1);
    }

    function testMainnetOnly() public {
        vm.chainId(137);
        vm.expectRevert(Mainnet.UnsupportedChain.selector);
        new Name("ipfs://names/");
    }
}

contract ColorTest is Test {
    Color internal color;
    ParcelMock internal parcel;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.chainId(1);
        parcel = new ParcelMock();
        color = new Color(address(this), IERC721(address(parcel)));
        parcel.mint(alice, 1);
        color.mint(alice, 100);
    }

    function testWholeUnitsAndStandardTransferAllowance() public {
        assertEq(color.decimals(), 0);
        vm.prank(alice);
        color.approve(bob, 10);
        vm.prank(bob);
        assertTrue(color.transferFrom(alice, bob, 10));
        assertEq(color.balanceOf(bob), 10);
        assertEq(color.allowance(alice, bob), 0);
    }

    function testStakedValueFollowsParcelAndWithdrawalSurvivesMintClosure() public {
        vm.prank(alice);
        color.stake(alice, 70, 1);
        assertEq(color.totalSupply(), 30);
        assertEq(color.totalStaked(), 70);
        assertEq(color.getStake(1), 70);
        vm.prank(alice);
        parcel.transferFrom(alice, bob, 1);
        vm.prank(alice);
        vm.expectRevert(Color.Unauthorized.selector);
        color.withdraw(alice, 1, 1);
        color.finishMinting();
        vm.expectRevert(Color.MintingFinished.selector);
        color.mint(alice, 1);
        vm.prank(bob);
        color.withdraw(bob, 70, 1);
        assertEq(color.balanceOf(bob), 70);
        assertEq(color.totalStaked(), 0);
        assertEq(color.totalSupply(), 100);
    }

    function testStakeCannotBurnAnotherWalletOrUnknownParcel() public {
        vm.prank(bob);
        vm.expectRevert(Color.Unauthorized.selector);
        color.stake(alice, 1, 1);
        vm.prank(alice);
        vm.expectRevert();
        color.stake(alice, 1, 99);
        assertEq(color.balanceOf(alice), 100);
    }

    function testMintOwnerOnlyAndWithdrawCannotOverdraw() public {
        vm.prank(alice);
        vm.expectRevert();
        color.mint(alice, 1);
        vm.prank(alice);
        color.stake(alice, 10, 1);
        vm.prank(alice);
        vm.expectRevert(Color.InvalidAmount.selector);
        color.withdraw(alice, 11, 1);
        vm.prank(alice);
        vm.expectRevert();
        color.withdraw(address(0), 1, 1);
        assertEq(color.getStake(1), 10);
    }
}

contract CollectiblesTest is Test, ERC1155Holder {
    Collectibles internal collectibles;
    CollectibleDistributor internal distributor;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vm.chainId(1);
        collectibles = new Collectibles(address(this), "ipfs://wearables/{id}.json");
        distributor = new CollectibleDistributor(address(this), IERC1155(address(collectibles)));
    }

    function testStandard1155AndNoImplicitMarketplaceApproval() public {
        assertTrue(collectibles.supportsInterface(0xd9b67a26));
        assertTrue(collectibles.supportsInterface(0x0e89341c));
        uint256 id = collectibles.mint(alice, 10, "");
        assertEq(collectibles.totalSupply(id), 10);
        address oldProxy = 0x207Fa8Df3a17D96Ca7EA4f2893fcdCb78a304101;
        assertFalse(collectibles.isApprovedForAll(alice, oldProxy));
        vm.prank(bob);
        vm.expectRevert();
        collectibles.safeTransferFrom(alice, bob, id, 1, "");
        vm.prank(alice);
        collectibles.setApprovalForAll(bob, true);
        vm.prank(bob);
        collectibles.safeTransferFrom(alice, bob, id, 1, "");
        assertEq(collectibles.balanceOf(bob, id), 1);
    }

    function testMintAndMetadataAreOwnerOnly() public {
        vm.prank(alice);
        vm.expectRevert();
        collectibles.mint(alice, 1, "");
        vm.prank(alice);
        vm.expectRevert();
        collectibles.setURI("ipfs://other/");
        vm.expectRevert(Collectibles.InvalidEdition.selector);
        collectibles.mint(alice, 0, "");
    }

    function testDistributionOncePerRecipientAndPause() public {
        uint256 id = collectibles.mint(address(distributor), 2, "");
        distributor.sendFreeWearable(alice, id);
        assertTrue(distributor.hasClaimed(alice));
        vm.expectRevert(CollectibleDistributor.AlreadyClaimed.selector);
        distributor.sendFreeWearable(alice, id);
        distributor.pause();
        vm.expectRevert();
        distributor.sendFreeWearable(bob, id);
        distributor.unpause();
        distributor.sendFreeWearable(bob, id);
        assertEq(collectibles.balanceOf(bob, id), 1);
    }

    function testDistributionFailureDoesNotConsumeEligibility() public {
        vm.expectRevert();
        distributor.sendFreeWearable(alice, 1);
        assertFalse(distributor.hasClaimed(alice));
        collectibles.mint(address(distributor), 1, "");
        vm.prank(alice);
        vm.expectRevert();
        distributor.sendFreeWearable(alice, 1);
        distributor.sendFreeWearable(alice, 1);
        assertTrue(distributor.hasClaimed(alice));
    }
}
