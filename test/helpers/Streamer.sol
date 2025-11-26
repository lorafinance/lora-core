// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import {ISuperToken} from "superfluid/interfaces/superfluid/ISuperfluid.sol";
import {SuperTokenV1Library} from "superfluid/apps/SuperTokenV1Library.sol";

contract Streamer {
    using SuperTokenV1Library for ISuperToken;

    ISuperToken public superToken;

    constructor(ISuperToken superToken_) {
        superToken = superToken_;
    }

    function createStream(int96 flowRate_, address receiver_) external {
        createStream(flowRate_, receiver_, new bytes(0));
    }

    function createStream(int96 flowRate_, address receiver_, bytes memory userData) public {
        superToken.createFlow(receiver_, flowRate_, userData);
    }

    function updateStream(int96 flowRate_, address receiver_) external {
        updateStream(flowRate_, receiver_, new bytes(0));
    }

    function updateStream(int96 flowRate_, address receiver_, bytes memory userData) public {
        superToken.updateFlow(receiver_, flowRate_, userData);
    }

    function deleteStream(address sender_, address receiver_) external {
        deleteStream(sender_, receiver_, new bytes(0));
    }

    function deleteStream(address sender_, address receiver_, bytes memory userData) public {
        superToken.deleteFlow(sender_, receiver_, userData);
    }

    function getStreamRate(address receiver_) external view returns (int96) {
        return superToken.getFlowRate(address(this), receiver_);
    }
}
