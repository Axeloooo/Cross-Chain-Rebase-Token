// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";

contract TokenAndPoolDeployer is Script {}

contract VaultDeployer is Script {
    function run(address _rebaseToken) public returns (Vault) {
        vm.startBroadcast();
        Vault vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
        return vault;
    }
}
