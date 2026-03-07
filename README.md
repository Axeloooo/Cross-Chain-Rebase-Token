# Cross-Chain Rebase Token

[![CI](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/actions/workflows/test.yml/badge.svg)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/actions/workflows/test.yml)
[![Release](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/actions/workflows/release.yml/badge.svg)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/actions/workflows/release.yml)
[![Latest Tag](https://img.shields.io/github/v/tag/Axeloooo/Cross-Chain-Rebase-Token)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/tags)
[![License](https://img.shields.io/github/license/Axeloooo/Cross-Chain-Rebase-Token)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/blob/main/LICENSE)
[![Repo Size](https://img.shields.io/github/repo-size/Axeloooo/Cross-Chain-Rebase-Token)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token)
[![Issues](https://img.shields.io/github/issues/Axeloooo/Cross-Chain-Rebase-Token)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/issues)
[![Pull Requests](https://img.shields.io/github/issues-pr/Axeloooo/Cross-Chain-Rebase-Token)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/pulls)
[![Contributors](https://img.shields.io/github/contributors/Axeloooo/Cross-Chain-Rebase-Token)](https://github.com/Axeloooo/Cross-Chain-Rebase-Token/graphs/contributors)

A Foundry-based Solidity project that mints yield-bearing rebase tokens for ETH deposits and bridges them across chains with Chainlink CCIP while preserving each user's accrued-interest rate.

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Tech Stack](#tech-stack)
- [Repository Layout](#repository-layout)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [Commands](#commands)
- [CI and Releases](#ci-and-releases)

## Overview

This protocol lets users deposit ETH into a vault and receive a rebase token that represents their underlying position plus linearly accrued interest over time.

The design centers on three ideas:

- `Vault` accepts ETH deposits and redemptions.
- `RebaseToken` tracks principal balances and lazily realizes accrued interest during user actions.
- `RebaseTokenPool` integrates Chainlink CCIP so balances can move cross-chain without losing the user's assigned interest rate.

## How It Works

1. A user deposits ETH into `Vault`.
2. The vault mints `RebaseToken` to the depositor using the protocol's current global interest rate.
3. Each account keeps its own interest rate snapshot from the moment it enters the system.
4. The token balance grows linearly over time and accrued interest is minted when the user interacts with the token.
5. When tokens are bridged with CCIP, the pool encodes the user's interest rate in the cross-chain payload and restores it on the destination chain.

## Tech Stack

- Solidity `0.8.24`
- [Foundry](https://book.getfoundry.sh/) for build, test, scripting, and formatting
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) for ERC-20, ownership, and access control primitives
- [Chainlink CCIP](https://docs.chain.link/ccip) and `CCIPLocalSimulatorFork` for cross-chain token pool logic and fork-based testing
- GitHub Actions for CI and automated releases with `semantic-release`

## Repository Layout

- `src/RebaseToken.sol`: Core rebase token with user-specific interest rates and lazy interest realization
- `src/Vault.sol`: ETH vault that mints and redeems the rebase token
- `src/RebaseTokenPool.sol`: Chainlink CCIP token pool used to burn, mint, and preserve interest-rate state across chains
- `src/interfaces/IRebaseToken.sol`: Shared interface used by the vault and pool
- `test/RebaseToken.t.sol`: Unit tests for deposit, redeem, transfer, and interest-rate behavior
- `test/CrossChain.t.sol`: Fork-based cross-chain bridging tests using Sepolia and Arbitrum Sepolia RPC endpoints
- `script/Deployer.s.sol`: Deployment helpers for token, pool, vault, and token admin configuration
- `script/ConfigurePool.s.sol`: Script for applying remote chain pool configuration
- `script/BridgeTokens.s.sol`: Script for sending tokens through the CCIP router

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git with submodule support

### Install Dependencies

Clone with submodules:

```bash
git clone --recurse-submodules git@github.com:Axeloooo/Cross-Chain-Rebase-Token.git
```

If the repository is already cloned:

```bash
git submodule update --init --recursive
```

## Environment Variables

Cross-chain tests use live RPC endpoints for Sepolia and Arbitrum Sepolia forks:

```bash
export SEPOLIA_RPC_URL="<your-sepolia-rpc-url>"
export ARBITRUM_SEPOLIA_RPC_URL="<your-arbitrum-sepolia-rpc-url>"
```

When broadcasting deployment scripts, provide the usual Foundry CLI flags such as `--rpc-url`, `--private-key`, or `--account`.

## Commands

### Build and Format

```bash
forge build
forge fmt
forge fmt --check
```

### Run Tests

Run the full test suite:

```bash
forge test -vvv
```

Run only unit tests:

```bash
forge test --match-path test/RebaseToken.t.sol -vvv
```

Run the cross-chain fork test:

```bash
SEPOLIA_RPC_URL="$SEPOLIA_RPC_URL" \
ARBITRUM_SEPOLIA_RPC_URL="$ARBITRUM_SEPOLIA_RPC_URL" \
forge test --match-path test/CrossChain.t.sol -vvv
```

### Run Scripts

Deploy token and pool:

```bash
forge script script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```

Deploy the vault:

```bash
forge script script/Deployer.s.sol:VaultDeployer --rpc-url "$SEPOLIA_RPC_URL" --broadcast --sig "run(address)" <REBASE_TOKEN_ADDRESS>
```

Configure a remote pool:

```bash
forge script script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```

Bridge tokens with CCIP:

```bash
forge script script/BridgeTokens.s.sol:BridgeTokenScript --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```

## CI and Releases

- `.github/workflows/test.yml` runs formatting checks, builds the contracts, and executes tests in CI.
- `.github/workflows/release.yml` runs `semantic-release` on pushes to `main`.
- The release workflow now fetches full git history and tags so semantic-release can compute versions from the complete commit and tag graph.
