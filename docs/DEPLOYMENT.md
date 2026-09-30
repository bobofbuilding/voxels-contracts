# Ethereum mainnet deployment runbook

Deployment and launch are distinct actions. All commands below are preparation examples; no deployment address or snapshot root is supplied by this repository.

## Prepare and verify data

Install the pinned dependencies and copy `.env.example` to a local `.env`. Keep credentials out of Git. Supply an archive-capable `MAINNET_RPC_URL` through the environment. Confirm the legacy address and block, then:

```sh
npm ci
git submodule update --init --recursive
npm run check
npm run snapshot:parcels -- "$LEGACY_PARCEL_ADDRESS" "$SNAPSHOT_BLOCK" snapshot.json
npm run proofs:parcels -- snapshot.json claims.json
shasum -a 256 snapshot.json claims.json
```

The output commands refuse to overwrite existing files. Check the generated root, independently reconcile ownership data, and publish both files durably. Do not use the small test fixture as production data.

Fill in `CONTRACT_OWNER`, `AUCTION_TREASURY`, and `PARCEL_METADATA_BASE_URI`. The metadata base must include its intended trailing slash and resolve `${baseURI}${tokenId}` to JSON. The base URI is fixed in the contract. Confirm the previously supplied wallet separately for this contract deployment; no address is silently assumed.

## Rehearse without broadcasting

Use a local fork of Ethereum mainnet configured with chain ID 1. Run deployment and owner actions against that fork, then exercise actual snapshot-owner wallets through impersonation. Verify the exact deadline, proof files, alternate recipients, old/new NFT coexistence, and a complete auction with refund/settlement/delivery. Unit tests alone do not replace this snapshot rehearsal.

Simulate deployment against the intended mainnet RPC:

```sh
forge script script/DeployParcels.s.sol:DeployParcels --rpc-url mainnet --account DEPLOYER_ACCOUNT
```

Without `--broadcast`, Foundry simulates. Inspect the sender, chain ID, constructor arguments, code sizes, and estimated gas. The deployer need not be the final contract owner.

## Deploy, then configure

After deployment approval, execute the same command with `--broadcast --verify` and the explorer credentials needed for verification. Record both returned addresses, deployment transactions, compiler/optimizer settings, and the deployed source revision. Read back `owner`, `legacyContract`, `snapshotBlock`, `claimStartsAt`, `claimEndsAt`, auction `parcel`, `treasury`, and `enabled`. Initially the timestamps are zero and auctions are disabled.

The owner must call:

```text
Parcel.configureAuctionHouse(PARCEL_AUCTION_ADDRESS)
```

This is a one-time binding. Verify the selected house before sending the transaction. No claims can open until it is configured. Use the owner wallet or its multisig transaction interface; deploying with a different wallet does not grant that wallet ownership.

## Launch claims

Publish the claim site, metadata, and full claim files first. Check the root in `claims.json` against the reviewed snapshot manifest. Then, through the owner wallet, call:

```text
Parcel.openClaims(REVIEWED_MERKLE_ROOT)
```

This starts the 30-day timer immediately. Check the event and contract getters, publish the exact UTC start/end, and confirm a real authorized claim. There is no extension, pause, root replacement, or early close function. Do not call this during contract deployment or source verification.

## Later auctions

After `claimEndsAt` and inventory reconciliation, the auction owner can call `enableAuctions()`. It is not part of launch. `createAuction` requires the parcel's original proof data, reserve in wei, and duration in seconds. Publish terms before listing. Bidders use `bid(tokenId)` with ETH; outbid wallets call `withdrawCredit(recipient)`. After the end, call `settle(tokenId)`. The winning wallet calls `claimWonParcel` with a supported recipient and the public proof data. The treasury withdraws its credited proceeds separately.

## Other contracts

`DeployOtherAssets.s.sol` deploys fresh Name, Color, collectibles, and distributor instances. It is deliberately separate and requires `ACKNOWLEDGE_FRESH_ASSET_REGISTRIES=true`. Do not broadcast it as a migration of legacy assets: it contains no balance/ownership import. Resolve the separate plans described in `MIGRATION.md` first.
