// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown when reading an address with no code, or a slice extending past
/// the end of the data.
error ReadError();

/// Thrown when data is too large to build data contract creation code for.
/// The creation code embeds `data.length + 1` as the PUSH2 code length
/// (the deployed data contract prepends a `0x00` byte), so any
/// `data.length >= type(uint16).max` reverts.
/// @param dataLength The length of the data that was attempted to create a
/// contract with.
error DataTooLarge(uint256 dataLength);
