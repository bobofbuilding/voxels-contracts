// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {Name} from "../src/Name.sol";
import {Color} from "../src/Color.sol";
import {Collectibles} from "../src/Collectibles.sol";
import {CollectibleDistributor} from "../src/CollectibleDistributor.sol";

/// @notice Separate from parcel launch. Does not migrate any legacy balances or names.
contract DeployOtherAssets is Script {
    function run()
        external
        returns (Name names, Color color, Collectibles collectibles, CollectibleDistributor distributor)
    {
        require(block.chainid == 1, "Ethereum mainnet only");
        require(vm.envBool("ACKNOWLEDGE_FRESH_ASSET_REGISTRIES"), "Separate asset launch decision required");
        address owner = vm.envAddress("CONTRACT_OWNER");
        IERC721 parcel = IERC721(vm.envAddress("PARCEL_ADDRESS"));
        string memory nameURI = vm.envString("NAME_METADATA_BASE_URI");
        string memory collectibleURI = vm.envString("COLLECTIBLE_METADATA_URI");
        vm.startBroadcast();
        names = new Name(nameURI);
        color = new Color(owner, parcel);
        collectibles = new Collectibles(owner, collectibleURI);
        distributor = new CollectibleDistributor(owner, IERC1155(address(collectibles)));
        vm.stopBroadcast();
    }
}
