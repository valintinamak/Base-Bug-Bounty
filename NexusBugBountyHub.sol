// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

contract NexusBugBountyHub {
    struct Bounty {
        address payable sponsor;
        uint256 rewardPoolWei;
        uint256 reportCount;
        bool isActive;
        bytes32 targetHash;
    }

    address payable public immutable hubAdmin;
    string public hubDescriptor;
    uint256 public platformFeeBps; // 250 = 2.5%
    uint256 public bountyCounter;
    uint256 public accumulatedFees;
    bool public isHubHalted;

    mapping(address => bool) public verifiedHackers;
    mapping(uint256 => Bounty) public bounties;

    event HackerVerified(address indexed hacker);
    event HackerBanned(address indexed hacker);
    event BountyCanceled(uint256 indexed bountyId, uint256 refundAmount);
    event TreasuryDeposited(address indexed funder, uint256 amount);
    event ReservesEmptied(address indexed admin, uint256 amount);
    event BountyFunded(uint256 indexed bountyId, address indexed sponsor, uint256 amount);
    event FeesGathered(address indexed admin, uint256 amount);
    event HubHaltToggled(bool isHalted);
    event RewardIncreased(uint256 indexed bountyId, uint256 addedAmount);
    event BugReportResolved(uint256 indexed bountyId, address indexed hacker, uint256 payout);
    event BugReportSubmitted(uint256 indexed bountyId, address indexed hacker, bytes32 reportHash);
    event DescriptorUpdated(string newDescriptor);

    modifier onlyAdmin() {
        require(msg.sender == hubAdmin, "NexusBounty: Access denied");
        _;
    }

    modifier whenNotHalted() {
        require(!isHubHalted, "NexusBounty: Hub is halted");
        _;
    }

    constructor() {
        hubAdmin = payable(msg.sender);
        hubDescriptor = "Nexus Base Bug Bounty Hub v1";
        platformFeeBps = 250; // 2.5%
        isHubHalted = false;
        verifiedHackers[msg.sender] = true;
    }

    // 1. addVerifiedHacker
    function addVerifiedHacker(address hacker) external onlyAdmin {
        require(!verifiedHackers[hacker], "NexusBounty: Already verified");
        verifiedHackers[hacker] = true;
        emit HackerVerified(hacker);
    }

    // 2. banMaliciousHacker
    function banMaliciousHacker(address hacker) external onlyAdmin {
        require(verifiedHackers[hacker], "NexusBounty: Not a verified hacker");
        require(hacker != msg.sender, "NexusBounty: Cannot ban self");
        verifiedHackers[hacker] = false;
        emit HackerBanned(hacker);
    }

    // 3. cancelBountyOffer
    function cancelBountyOffer(uint256 bountyId) external {
        Bounty storage b = bounties[bountyId];
        require(bountyId > 0 && bountyId <= bountyCounter, "NexusBounty: Invalid ID");
        require(msg.sender == b.sponsor || msg.sender == hubAdmin, "NexusBounty: Unauthorized");
        require(b.isActive, "NexusBounty: Already inactive");

        b.isActive = false;
        uint256 refund = b.rewardPoolWei;
        b.rewardPoolWei = 0;

        if (refund > 0) {
            (bool sent, ) = b.sponsor.call{value: refund}("");
            require(sent, "NexusBounty: Refund failed");
        }

        emit BountyCanceled(bountyId, refund);
    }

    // 4. depositHubTreasury
    function depositHubTreasury() external payable whenNotHalted {
        require(msg.value > 0, "NexusBounty: Zero deposit");
        accumulatedFees += msg.value;
        emit TreasuryDeposited(msg.sender, msg.value);
    }

    // 5. emptyHubReserves
    function emptyHubReserves() external onlyAdmin {
        uint256 balance = address(this).balance;
        require(balance > 0, "NexusBounty: Zero balance");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: balance}("");
        require(sent, "NexusBounty: Sweep failed");

        emit ReservesEmptied(hubAdmin, balance);
    }

    // 6. fundNewBounty
    function fundNewBounty(bytes32 targetHash) external payable whenNotHalted returns (uint256) {
        require(msg.value > 0, "NexusBounty: Zero reward pool");

        bountyCounter++;
        bounties[bountyCounter] = Bounty({
            sponsor: payable(msg.sender),
            rewardPoolWei: msg.value,
            reportCount: 0,
            isActive: true,
            targetHash: targetHash
        });

        emit BountyFunded(bountyCounter, msg.sender, msg.value);
        return bountyCounter;
    }

    // 7. gatherPlatformFees
    function gatherPlatformFees() external onlyAdmin {
        uint256 amount = accumulatedFees;
        require(amount > 0, "NexusBounty: Zero fees");

        accumulatedFees = 0;
        (bool sent, ) = hubAdmin.call{value: amount}("");
        require(sent, "NexusBounty: Harvest failed");

        emit FeesGathered(hubAdmin, amount);
    }

    // 8. haltBountyHub
    function haltBountyHub(bool isHalted) external onlyAdmin {
        isHubHalted = isHalted;
        emit HubHaltToggled(isHalted);
    }

    // 9. increaseBountyReward
    function increaseBountyReward(uint256 bountyId) external payable whenNotHalted {
        Bounty storage b = bounties[bountyId];
        require(bountyId > 0 && bountyId <= bountyCounter, "NexusBounty: Invalid ID");
        require(msg.sender == b.sponsor, "NexusBounty: Not the sponsor");
        require(b.isActive, "NexusBounty: Not active");
        require(msg.value > 0, "NexusBounty: Zero addition");

        b.rewardPoolWei += msg.value;
        emit RewardIncreased(bountyId, msg.value);
    }

    // 10. resolveBugReport
    function resolveBugReport(uint256 bountyId, address payable hacker) external {
        Bounty storage b = bounties[bountyId];
        require(bountyId > 0 && bountyId <= bountyCounter, "NexusBounty: Invalid ID");
        require(msg.sender == b.sponsor || msg.sender == hubAdmin, "NexusBounty: Unauthorized");
        require(b.isActive, "NexusBounty: Bounty inactive");
        require(verifiedHackers[hacker], "NexusBounty: Hacker not verified");

        b.isActive = false; // Закрываем баунти после успешного нахождения бага
        
        uint256 fee = (b.rewardPoolWei * platformFeeBps) / 10000;
        uint256 payout = b.rewardPoolWei - fee;
        
        accumulatedFees += fee;
        b.rewardPoolWei = 0;

        if (payout > 0) {
            (bool sent, ) = hacker.call{value: payout}("");
            require(sent, "NexusBounty: Payout failed");
        }

        emit BugReportResolved(bountyId, hacker, payout);
    }

    // 11. submitBugReport
    function submitBugReport(uint256 bountyId, bytes32 reportHash) external whenNotHalted {
        Bounty storage b = bounties[bountyId];
        require(bountyId > 0 && bountyId <= bountyCounter, "NexusBounty: Invalid ID");
        require(b.isActive, "NexusBounty: Bounty inactive");
        require(verifiedHackers[msg.sender], "NexusBounty: Not a verified hacker");

        b.reportCount++;
        emit BugReportSubmitted(bountyId, msg.sender, reportHash);
    }

    // 12. updateHubDescriptor
    function updateHubDescriptor(string calldata newDescriptor) external onlyAdmin {
        require(bytes(newDescriptor).length > 0, "NexusBounty: Empty string");
        hubDescriptor = newDescriptor;
        emit DescriptorUpdated(newDescriptor);
    }
}