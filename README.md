# Cross-Chain Rebase Token

1. A protocol that allows users to deposit into a vaukt and in return, receiver rebase tokens that represent their underlying balance.
2. Rebase token -> balanceOf function is dynamic to show the incresing balance over time.
   - Balance increses linearly over time.
   - Mint tokens to users every time theyperform an action (minting, burningl transfering, or bridging).
3. Interest rate
   - Individually set an interest rate of each user basedon some global interest rate of the protocol at the time the user deposits into the vault.
   - This global interest rate can only decrease to incetivize/reward early adopters.
   - Increase token adoption.
