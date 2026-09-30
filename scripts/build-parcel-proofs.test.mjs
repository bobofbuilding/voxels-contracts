import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { AbiCoder, keccak256 } from 'ethers';
import { StandardMerkleTree } from '@openzeppelin/merkle-tree';
import { buildProofs, types } from './build-parcel-proofs.mjs';

const snapshot = {
  chainId: 1, legacyContract: '0x0000000000000000000000000000000000000123',
  snapshotBlock: '90', blockHash: '0x' + 'ab'.repeat(32),
  parcels: [
    { tokenId: '0', owner: '0x00000000000000000000000000000000000a11ce', bounds: [-10,0,-10,10,20,10], contentURI: 'ipfs://scene' },
    { tokenId: '2', owner: '0x0000000000000000000000000000000000000b0b', bounds: [-10,0,-10,10,20,10], contentURI: '' },
  ],
};

test('proofs verify using Solidity-equivalent ABI hashing, including token zero', () => {
  const result = buildProofs(snapshot);
  const tree = StandardMerkleTree.load(result.tree);
  for (const [i, value] of tree.entries()) {
    assert.ok(StandardMerkleTree.verify(result.root, types, value, tree.getProof(i)));
    const hash = keccak256(keccak256(AbiCoder.defaultAbiCoder().encode(types, value)));
    assert.equal(hash, tree.leafHash(value));
  }
  assert.equal(result.claims[0].tokenId, '0');
  assert.equal(result.claims[1].contentURI, '');
});

test('proof root is deterministic across input order', () => {
  assert.equal(buildProofs(snapshot).root, buildProofs({ ...snapshot, parcels: [...snapshot.parcels].reverse() }).root);
});

test('duplicate IDs, zero owners, wrong chains, unsafe IDs, and invalid bounds fail', () => {
  const mutations = [
    s => s.parcels.push(s.parcels[0]), s => s.chainId = 137,
    s => s.parcels[0].owner = '0x' + '00'.repeat(20), s => s.parcels[0].tokenId = 9007199254740992,
    s => s.parcels[0].bounds[0] = 11, s => s.parcels[0].bounds[0] = -32769,
    s => s.parcels[0].bounds[0] = 0.5, s => s.snapshotBlock = '0', s => s.blockHash = '0x123',
  ];
  for (const mutate of mutations) { const s = structuredClone(snapshot); mutate(s); assert.throws(() => buildProofs(s)); }
});

test('committed cross-language fixture matches generated proof data', () => {
  const expected = JSON.parse(readFileSync(new URL('../test-solidity/fixtures/claims.json', import.meta.url)));
  assert.deepEqual(buildProofs(snapshot), expected);
});
