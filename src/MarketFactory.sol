// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {Ownable} from "solady/auth/Ownable.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibCall} from "solady/utils/LibCall.sol";

/// @title MarketFactory
/// @author Lora Finance
/// @notice A factory contract for deploying Market proxies
contract MarketFactory is Ownable {
    using LibClone for address;
    using LibCall for address;

    address public implementation;

    constructor(address implementation_, address owner_) {
        implementation = implementation_;

        _initializeOwner(owner_);
    }

    /// @notice Set the Market implementation address
    /// @param newImplementation_ The new implementation address
    function setImplementation(address newImplementation_) external onlyOwner {
        implementation = newImplementation_;
    }

    /// @notice Deploy a new Market proxy
    /// @param immutableArgs_ The immutable arguments for the Market proxy
    /// @param initializerData_ The initializer data for the Market proxy
    /// @return The address of the deployed Market proxy
    function deployMarket(bytes calldata immutableArgs_, bytes calldata initializerData_)
        external
        onlyOwner
        returns (address)
    {
        address proxy = implementation.deployERC1967(immutableArgs_);
        proxy.callContract(initializerData_);

        return proxy;
    }
}
