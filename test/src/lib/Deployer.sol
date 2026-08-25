// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

/// @title Deployer
/// Deploys arbitrary creation code from its own address so tests can deploy
/// identical creation code from distinct deployer addresses and call paths.
contract Deployer {
    function deployCreate(bytes memory creationCode) external returns (address dataContract) {
        assembly ("memory-safe") {
            dataContract := create(0, add(creationCode, 0x20), mload(creationCode))
        }
    }

    function deployCreate2(bytes memory creationCode, bytes32 salt) external returns (address dataContract) {
        assembly ("memory-safe") {
            dataContract := create2(0, add(creationCode, 0x20), mload(creationCode), salt)
        }
    }
}
