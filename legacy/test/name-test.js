/* globals web3, artifacts, contract, beforeEach, describe, it, assert */

const Name = artifacts.require('Name')

contract('mint test', async (accounts) => {
  let recipient = accounts[1]

  it('should have name', async () => {
    let instance = await Name.deployed()
    let name = await instance.name.call()
    assert.equal(name.valueOf(), 'Cryptovoxels Name')
  })

  it('should have symbol', async () => {
    let instance = await Name.deployed()
    let name = await instance.symbol.call()
    assert.equal(name.valueOf(), 'NAME')
  })

  it('should have tokens', async () => {
    let instance = await Name.deployed()
    let balance = await instance.totalSupply.call()
    assert(balance.valueOf() > 0)
  })

  describe('mint', async () => {
    let instance = await Name.deployed()

    it('returns token by owner', async () => {
      await instance.mint(recipient, 'alice', { from: recipient })

      let r = await instance.totalSupply.call()
      let i = parseInt(await r.valueOf(), 10)
      assert.equal(i, 1)

      const token = await instance.tokenOfOwnerByIndex(recipient, 0)
      assert.equal(token.valueOf(), i)

      let result = await instance.tokenURI(i)
      assert.equal(result.valueOf(), `https://www.cryptovoxels.com/n/${i}`)

      let name = await instance.getName(i)
      assert.equal(name.valueOf(), 'alice')
    })

    it('should increase token id', async () => {
      await instance.mint(recipient, 'abc', { from: recipient })

      let r = await instance.totalSupply.call()
      let i = parseInt(await r.valueOf(), 10)
      assert(i > 0)

      await instance.mint(recipient, 'bcd', { from: recipient })
      r = await instance.totalSupply.call()
      let j = parseInt(r.valueOf(), 10)
      assert.equal(i + 1, j)

      await instance.mint(recipient, 'cde', { from: recipient })
      r = await instance.totalSupply.call()
      let k = parseInt(r.valueOf(), 10)
      assert.equal(j + 1, k)
    })

    it('should fail for reuse of name', async function () {
      await instance.mint.call(recipient, 'SomeMadThing', { from: recipient })

      try {
        await instance.mint.call(recipient, 'alice', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, 'ALICE', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, 'AlIce', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }
    })

    it('should fail for invalid names', async function () {
      try {
        await instance.mint.call(recipient, '😃', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, 'SUCKS LOTS', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, '-_-', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, 'xx-', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, '--xxxxxx', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, '', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, 'ab', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }

      try {
        await instance.mint.call(recipient, 'abaregaergaergaergaergaergaerg', { from: recipient })
        assert.fail('Expected to throw')
      } catch (e) {
        assert(true)
      }
    })
  })
})
