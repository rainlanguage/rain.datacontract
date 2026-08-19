// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown if writing the data by creating the contract fails somehow.
error WriteError();

/// Thrown if reading a zero length address.
error ReadError();

/// Thrown when trying to write data that is too large to fit in uint16.
/// @param dataLength The length of the data that was attempted to create a
/// contract with.
error DataTooLarge(uint256 dataLength);
