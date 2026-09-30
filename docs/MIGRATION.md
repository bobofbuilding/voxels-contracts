# Parcel migration plan

## Confirmed policy

- Destination: Ethereum mainnet, chain ID 1. Parcels use ERC-721.
- Eligibility: owner of each legacy parcel at one published, finalized snapshot block.
- The legacy NFT remains with its existing owner. There is no burn, lock, bridge, or automatic transfer.
- Claims open in a separate owner transaction after the website, metadata, and proof files are live.
- Claims last exactly 2,592,000 seconds. The first block with `timestamp >= claimEndsAt` rejects claims.
- Only parcels participate in this launch. Name NFTs, Color balances/stakes, and collectibles do not migrate automatically.
- Unclaimed IDs remain reserved and unminted. Auctions are a separate, explicit phase after the deadline.

## Before selecting the snapshot

Confirm the canonical legacy mainnet parcel address and deployed ABI. The archived Color deployment references `0x79986aF15539de2db9A5086382daEdA917A9CF0C`; this is a candidate reference, not a deployment input verified by this project. Choose and publish an exact finalized block number and block hash. Never use a moving `latest` snapshot.

Inventory contract-wallet holders, escrowed NFTs, custodians, wrapped tokens, lending protocols, and multisigs. Eligibility uses the on-chain owner at the snapshot; it does not infer a beneficiary behind an escrow or wrapper. A smart contract holder must be able to call `claim` itself, or an explicitly agreed treatment must be settled before the root is frozen. The contract does not accept a proof submitted by a different wallet on a holder's behalf.

Communicate that post-snapshot buyers of the old collection do not acquire the migration right. Snapshot owners keep that right even if they sell the old token. Buyers and marketplaces must see clear collection/address labels. Old and new NFTs may coexist indefinitely; application ownership must switch to the new collection deliberately.

## Snapshot and proof data

Use an archive-capable Ethereum RPC. Export every token via `totalSupply` and `tokenByIndex` at the fixed block, then read `ownerOf`, `getBoundingBox`, and `contentURI` at that same block. The exporter checks mainnet, finality, duplicate IDs, valid bounds, and the block hash again after export. It fails rather than silently skipping records. It requires the enumerable legacy ABI; a non-enumerable source needs a reviewed event-index export instead.

Review records against a second RPC/indexer, reconcile total supply and token IDs, and sample owners, coordinates, and scene content. Resolve invalid or zero-volume legacy bounds before deployment; the new contract requires increasing bounds on all three axes. Preserve large token IDs as decimal strings.

The proof generator uses OpenZeppelin `StandardMerkleTree`, double-hashed leaves, and sorted pair hashing. Each leaf binds:

```
uint256 sourceChainId (=1)
address legacyContract
uint256 snapshotBlock
uint256 tokenId
address snapshotOwner
int16 x1, y1, z1, x2, y2, z2
string contentURI
```

The root commits to owner, ID, bounds, and content. The source block hash accompanies the public manifest; it is reviewed off-chain rather than revalidated by the destination contract. There must be exactly one record per token ID. Publish the complete snapshot, tree dump, proofs, block hash, root, source/destination addresses, and file checksums in durable public storage before launch. The full claim list must remain downloadable without relying on a single claim API.

## Deployment and launch

1. Review the new bytecode and independent contract review results. Confirm the owner, treasury, metadata URI, source, and snapshot. Rehearse the entire flow on a local mainnet fork with the actual snapshot data.
2. Deploy Parcel and ParcelAuction. Neither deployment starts a timer. Configure the auction address once, before launch; it cannot be replaced later. Confirm the auction points to the correct Parcel and treasury.
3. Verify contract source and compiler settings publicly. Publish deployment addresses and metadata endpoints. Update the application to recognize chain ID 1 and the new ERC-721 ABI.
4. Release the claim UI with snapshot eligibility, proof validation, recipient selection, exact deadline, transaction status, and retry support. Include a clear warning that the old NFT remains. Audit wallet connection and chain switching.
5. Once all public files and the UI are reachable, the owner calls `openClaims(root)`. The `ClaimsOpened` event is the authoritative start/end record. Record both timestamps in UTC; do not calculate the deadline from a GitHub release or website publish time.
6. Monitor successful/failed claims, metadata availability, ownership indexing, and support queues. Announce the deadline repeatedly; claims cannot be extended or reopened by an administrator.
7. At expiry, reconcile claimed and unclaimed IDs against the published manifest. Publish the remaining inventory. No automatic transfer to treasury occurs.

## Claim behavior and application changes

The snapshot wallet submits its proof and may choose a different recipient, including another supported smart wallet. An ERC-721 receiver rejection reverts the entire claim and can be retried. The same parcel ID can mint only once, including after transfers. There is no claim fee in the contract; the sender pays Ethereum gas. Claiming does not modify the legacy NFT.

The application must remove assumptions about legacy `buy`, `setPrice`, `getPrice`, administrative `burn`, `takeOwnership`, and enumerable indexes. Keep `getBoundingBox`, `contentURI`, and owner-only `setContentURI` integration. Use ERC-721 approvals and standard transfers, and index `Transfer` events from the deployment block. Existing scene editing permissions must resolve the destination contract's owner after cutover.

Migration claims are per-token transactions. Large holders can use wallet batching; the supplied contract has no unbounded batch-claim function. Snapshot contract wallets and recipients must be rehearsed before launch.

## Auction phase

The deployed auction house remains disabled throughout claims and after expiry until the owner calls `enableAuctions`. Listing is owner-only and verifies the same snapshot proof. Claimed IDs, unknown IDs, and previously sold IDs cannot be listed. There is no arbitrary parcel minting path.

Proposed auction parameters implemented for review:

- ETH bids; positive reserve price chosen for each listing.
- Listing duration between 1 and 30 days, chosen per parcel.
- First bid must meet reserve; subsequent bids must increase by at least 5%, with a one-wei minimum increment.
- A bid in the last 15 minutes extends the end to 15 minutes after that bid.
- Each bid deposits its full value. The displaced bid becomes a withdrawable credit; bidder callbacks cannot block later bids.
- Anyone can settle after expiry. Settlement credits the fixed treasury with the winning bid.
- The winner then selects a recipient and claims the parcel, using the public snapshot proof. A rejected receiver can be retried with another recipient. Winning entitlements do not expire.
- A no-bid listing can be settled and relisted. A listing cannot be cancelled or its reserve changed after creation. Auctions cannot be paused once enabled.

These auction settings are implementation defaults, not final commercial terms. Approve them before deploying the immutable auction house. Publish reserve prices, durations, treasury, and listing schedule before activating this phase. Unlisted parcels remain unminted without any deadline.

## Other asset types

The modern Name, Color, ERC-1155 collectibles, and distributor contracts target mainnet but are excluded from the parcel deployment script. They do not import old balances or preserve old IDs automatically. The new Name registry starts at ID 1 and permits public registration; do not launch it as a replacement until legacy-name reservation is designed. Color needs an accounting plan covering liquid balances and stakes separately. Polygon collectibles need a separate source-chain snapshot and ID/edition mapping. Existing distributor inventory and claim records also need an explicit policy.

Keep their deployment step separate until those decisions are approved. Proxy/bridge infrastructure and Polygon automatic marketplace approvals are archived and are not redeployed.

## Remaining launch inputs

- Verified source address, snapshot block/hash, and complete reconciled manifest.
- Governance wallet, treasury, and production metadata endpoints.
- Final collection name/symbol (currently `Voxels Parcels` / `VOXEL`).
- Reviewed treatment of escrow/custodial holders and the UI/application cutover.
- Independent security review and a rehearsal using real snapshot proofs.
- Final auction terms before immutable deployment; auction activation remains a later action.

## Standards

See [ERC-721](https://eips.ethereum.org/EIPS/eip-721), [OpenZeppelin ERC-721](https://docs.openzeppelin.com/contracts/5.x/erc721), and [OpenZeppelin MerkleProof](https://docs.openzeppelin.com/contracts/5.x/api/utils/cryptography). These define the inherited token behavior and proof verification used here.
