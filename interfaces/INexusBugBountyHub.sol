// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;
interface INexusBugBountyHub {
    function fundNewBounty(bytes32 targetHash) external payable returns (uint256);
    function submitBugReport(uint256 bountyId, bytes32 reportHash) external;
}
