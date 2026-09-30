// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

abstract contract Mainnet {
    error UnsupportedChain();

    constructor() {
        if (block.chainid != 1) revert UnsupportedChain();
    }
}
