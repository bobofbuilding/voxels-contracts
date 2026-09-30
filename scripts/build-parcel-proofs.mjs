import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { getAddress, ZeroAddress } from 'ethers';
import { StandardMerkleTree } from '@openzeppelin/merkle-tree';

export const types = ['uint256', 'address', 'uint256', 'uint256', 'address',
  'int16', 'int16', 'int16', 'int16', 'int16', 'int16', 'string'];
const uint = (value, label) => {
  if (typeof value !== 'string' || !/^(0|[1-9][0-9]*)$/.test(value)
      || BigInt(value) >= 2n ** 256n) throw new Error(`${label} must be a uint256 decimal string`);
  return value;
};
const address = (value) => {
  const result = getAddress(value);
  if (result === ZeroAddress) throw new Error('Zero address is not eligible');
  return result;
};

export function buildProofs(snapshot) {
  if (snapshot.chainId !== 1) throw new Error('Snapshot must be Ethereum mainnet');
  const source = address(snapshot.legacyContract);
  const block = uint(snapshot.snapshotBlock, 'snapshotBlock');
  if (block === '0' || !/^0x[0-9a-fA-F]{64}$/.test(snapshot.blockHash)) throw new Error('Invalid snapshot block');
  if (!Array.isArray(snapshot.parcels) || snapshot.parcels.length === 0) throw new Error('Empty snapshot');
  const seen = new Set();
  const parcels = snapshot.parcels.map((p) => {
    const tokenId = uint(p.tokenId, 'tokenId');
    if (seen.has(tokenId)) throw new Error(`Duplicate token ID ${tokenId}`);
    seen.add(tokenId);
    const owner = address(p.owner);
    if (!Array.isArray(p.bounds) || p.bounds.length !== 6 || p.bounds.some(
      n => !Number.isInteger(n) || n < -32768 || n > 32767)) throw new Error(`Invalid int16 bounds for ${tokenId}`);
    if (p.bounds.slice(0, 3).some((n, i) => n >= p.bounds[i + 3])) throw new Error(`Invalid bounds for ${tokenId}`);
    if (typeof p.contentURI !== 'string') throw new Error('Missing content URI');
    return { tokenId, owner, bounds: p.bounds, contentURI: p.contentURI };
  }).sort((a, b) => BigInt(a.tokenId) < BigInt(b.tokenId) ? -1 : 1);
  const values = parcels.map(p => ['1', source, block, p.tokenId, p.owner, ...p.bounds, p.contentURI]);
  const tree = StandardMerkleTree.of(values, types);
  const claims = parcels.map((p, i) => ({ ...p, proof: tree.getProof(i) }));
  return { schemaVersion: 1, chainId: 1, legacyContract: source, snapshotBlock: block,
    blockHash: snapshot.blockHash, parcelCount: claims.length, root: tree.root,
    leafTypes: types, claims, tree: tree.dump() };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , input, output] = process.argv;
  if (!input || !output) throw new Error('Usage: node scripts/build-parcel-proofs.mjs snapshot.json claims.json');
  const result = buildProofs(JSON.parse(readFileSync(input, 'utf8')));
  writeFileSync(output, JSON.stringify(result, null, 2) + '\n', { flag: 'wx' });
  console.log(`Wrote ${result.parcelCount} parcel claims; root ${result.root}`);
}
