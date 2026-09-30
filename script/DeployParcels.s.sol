// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Parcel} from "../src/Parcel.sol";
import {ParcelAuction} from "../src/ParcelAuction.sol";

/// @notice Deploys without opening claims or enabling auctions.
contract DeployParcels is Script {
    function run() external returns (Parcel parcel, ParcelAuction auction) {
        require(block.chainid == 1, "Ethereum mainnet only");
        address owner = vm.envAddress("CONTRACT_OWNER");
        address treasury = vm.envAddress("AUCTION_TREASURY");
        address source = vm.envAddress("LEGACY_PARCEL_ADDRESS");
        uint256 snapshot = vm.envUint("SNAPSHOT_BLOCK");
        string memory metadata = vm.envString("PARCEL_METADATA_BASE_URI");
        vm.startBroadcast();
        parcel = new Parcel(owner, source, snapshot, metadata);
        auction = new ParcelAuction(owner, parcel, treasury);
        vm.stopBroadcast();
    }
}
