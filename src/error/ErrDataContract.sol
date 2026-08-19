// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown if writing the data by creating the contract fails somehow.
error WriteError();

/// Thrown when reading an address with no code, or a slice extending past
/// the end of the data.
error ReadError();
