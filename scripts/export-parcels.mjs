import { writeFileSync } from 'node:fs';
import { Contract, JsonRpcProvider, getAddress } from 'ethers';
import { buildProofs } from './build-parcel-proofs.mjs';

const [, , sourceAddress, requestedBlock, output] = process.argv;
if (!sourceAddress || !requestedBlock || !output || !process.env.MAINNET_RPC_URL) {
  throw new Error('Usage: MAINNET_RPC_URL=... npm run snapshot:parcels -- LEGACY_ADDRESS BLOCK OUTPUT.json');
}
if (!/^[1-9][0-9]*$/.test(requestedBlock) || BigInt(requestedBlock) > BigInt(Number.MAX_SAFE_INTEGER)) {
  throw new Error('Invalid block number');
}
const provider = new JsonRpcProvider(process.env.MAINNET_RPC_URL);
try {
  if ((await provider.getNetwork()).chainId !== 1n) throw new Error('RPC must be Ethereum mainnet');
  const blockTag = Number(requestedBlock);
  const finalized = await provider.getBlock('finalized');
  const block = await provider.getBlock(blockTag);
  if (!finalized || !block || blockTag > finalized.number) throw new Error('Snapshot must be finalized');
  const legacyContract = getAddress(sourceAddress);
  const source = new Contract(legacyContract, [
    'function totalSupply() view returns (uint256)',
    'function tokenByIndex(uint256) view returns (uint256)',
    'function ownerOf(uint256) view returns (address)',
    'function getBoundingBox(uint256) view returns (int16,int16,int16,int16,int16,int16)',
    'function contentURI(uint256) view returns (string)',
  ], provider);
  const supply = await source.totalSupply({ blockTag });
  const parcels = [];
  for (let i = 0n; i < supply; ++i) {
    const tokenId = await source.tokenByIndex(i, { blockTag });
    const [owner, bounds, contentURI] = await Promise.all([
      source.ownerOf(tokenId, { blockTag }), source.getBoundingBox(tokenId, { blockTag }),
      source.contentURI(tokenId, { blockTag }),
    ]);
    parcels.push({ tokenId: tokenId.toString(), owner, bounds: Array.from(bounds, Number), contentURI });
  }
  // Re-read the hash without the provider's short response cache before publishing.
  const checked = await provider.send('eth_getBlockByNumber', ['0x' + blockTag.toString(16), false]);
  if (checked.hash !== block.hash) throw new Error('Snapshot block changed during export');
  const snapshot = { schemaVersion: 1, chainId: 1, legacyContract, snapshotBlock: requestedBlock,
    blockHash: block.hash, parcels };
  buildProofs(snapshot); // Validate every record and reject duplicate token IDs before writing.
  writeFileSync(output, JSON.stringify(snapshot, null, 2) + '\n', { flag: 'wx' });
  console.log(`Exported ${parcels.length} parcels from finalized mainnet block ${requestedBlock}`);
} finally {
  provider.destroy();
}
