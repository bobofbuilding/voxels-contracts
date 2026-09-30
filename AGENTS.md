# Working on Voxels contracts

- Active Ethereum mainnet code lives in `src/`; `legacy/` is reference material excluded from the build.
- Use pinned OpenZeppelin implementations for standard token and access-control behavior.
- Preserve snapshot ownership, token IDs, proof encoding, and the fixed claim deadline. Explain changes to these guarantees.
- Keep parcel deployment, claim launch, and auction activation separate. Other asset migrations require their own plan.
- Never store private keys or RPC credentials in the repository. Do not broadcast transactions without explicit authorization.
- Run `npm run check` after changes. Cover authorization, deadline boundaries, callbacks, duplicate claims, and ETH accounting.
- Keep migration documentation and deployment scripts consistent with contract behavior. Record outstanding launch decisions.
