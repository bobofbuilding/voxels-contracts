# Voxels contracts

Ethereum mainnet contracts built with Solidity 0.8.30 and OpenZeppelin Contracts 5.6.1. This is a new deployment, not an upgrade of an existing contract. No mainnet contracts have been deployed by this change.

| Contract | Purpose |
| --- | --- |
| `Parcel` | Standard ERC-721 parcels with metadata, immutable parcel bounds, owner-editable scene URIs, and snapshot claims |
| `ParcelAuction` | Inactive-at-launch ETH auctions for unclaimed snapshot parcels |
| `Name` | ERC-721 name registry with case-insensitive uniqueness |
| `Color` | ERC-20 whole-unit balances and parcel-linked staking |
| `Collectibles` | ERC-1155 wearable editions using explicit operator approvals |
| `CollectibleDistributor` | Inventory-funded, one-per-recipient promotional distribution |

## Parcel launch

Snapshot owners may claim for **30 days from the explicit on-chain launch transaction**. Deployment does not start the clock. Old NFTs remain intact. Unclaimed parcels remain unminted until an owner explicitly activates and lists them for auction after the claim deadline. There is no owner mint, forced transfer, creator ownership override, or administrative burn in the parcel contract.

Read [the migration plan](docs/MIGRATION.md) and [deployment runbook](docs/DEPLOYMENT.md) before launch. The 30-day migration applies only to parcels. Names, Color, and collectibles have modern implementations but need separate migration and launch decisions; deploying those implementations starts fresh state.

## Development

Install Node.js 22+ and Foundry 1.7.1, then:

```sh
git submodule update --init --recursive
npm ci
npm run check
```

- `src/`: active mainnet contracts. Constructors reject chains other than chain ID 1.
- `script/`: deployment preparation; no script automatically starts claims or auctions.
- `test-solidity/`: contract tests on a local EVM configured as chain ID 1.
- `scripts/`: read-only snapshot export, proof generation, and tooling tests.
- `legacy/`: archived contracts and Truffle tooling, excluded from the active build.

ERC-721 enumerable indexes are deliberately omitted. Index `Transfer` events; `totalSupply()` tracks minted parcel count. `tokenURI()` returns the configured base URI plus the decimal token ID, which must resolve to ERC-721 JSON metadata.

The standard libraries supply token transfers, approval checks, safe receiver callbacks, and interface detection. Contracts are not proxy-based or upgradeable. Administrative ownership uses two-step transfer. The distributor can pause its distributions; regular token transfers and parcel claims cannot be paused or extended.

Snapshot tooling pins `uuid` 11.1.1 through an npm override to avoid the advisory in the Merkle-tree library's transitive dependency. The proof encoding is checked against both ethers and Solidity.

Licensed under [MIT](LICENSE). Third-party dependencies retain their own license notices.
