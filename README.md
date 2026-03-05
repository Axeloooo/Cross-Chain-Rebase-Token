# Cross-Chain Rebase Token

1. A protocol that allows users to deposit into a vault and in return, receive rebase tokens that represent their underlying balance.
2. Rebase token -> balanceOf function is dynamic to show the increasing balance over time.
   - Balance increases linearly over time.
   - Mint tokens to users every time they perform an action (minting, burning, transferring, or bridging).
3. Interest rate
   - Individually set an interest rate of each user based on some global interest rate of the protocol at the time the user deposits into the vault.
   - This global interest rate can only decrease to incentivize/reward early adopters.
   - Increase token adoption.
