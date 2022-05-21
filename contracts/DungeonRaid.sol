//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC1155.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

import "./IRaider.sol";
import "./ILoot.sol";

error DungeonNotGenerated();
error DungeonCleared();
error AlreadyProposed();
error TimeHasExpired();
error NotTokenOwner();
error InvalidDungeon();
error NotExecutionTime();
error DungeonNotCleared();

error TokenAlreadyRaiding();
error TokenNotInRaidParty();

// RINKEBY: 0x8Ee1245F699df20E31F4A78Bf526d8E2cF1DD04b

contract DungeonRaid is Ownable, ReentrancyGuard, VRFConsumerBaseV2 {
    enum DungeonType {
        COMMON, // 95% clear on max power, 50% on min power, reward multiplier x1, average power 10
        UNCOMMON, // 90 %, 45 // x2, average power 20
        RARE, // 85%, 40 // x4, average power 35
        EPIC, // 80 %, 35 // x8, average power 50
        LEGENDARY, // 75%, 30 // x16, average power 70
        WORLD, // 70%, 25%, x32, no average power, just a high number count
        GENERATING
    }

    enum ProposalStatus {
        NONE,
        ONGOING,
        PASSED,
        FAILED
    }

    // COMMON = basePower 50, maxPower 200, limit: 20 people -- 30% chance to be common from 71 till 100
    // UNCOMMON = basePower 100, maxPower 400, limit: 30 people -- 25% from 46 till 70
    // RARE = basePower 200, maxPower 800, limit: 40 people -- 20% from 26 till 45
    // EPIC = basePower 400, maxPower 1600, limit: 50 people -- 15% from 11 to 25
    // LEGENDARY = basePower 800, maxPower 3200, limit: 60 people -- 7% from 4 to 10
    // WORLD = basePower 1600, maxPower 6400, no limit to amount of people -- 3% from 1 to 3

    // clear % = current power / maxpower - (1 + rarity * 5)
    // 50 / 200 = 0, 5000 / 200 = 50 - (1*rarity)
    // Random number % 100 + clear%

    // Calculating clear percentage
    // power * 100 / maxPower - (1*rarity)

    // Calculating if dungeon was cleared
    // If (Random number % 100 + 1) < clearPercent = LOSE
    // Else = WIN

    struct Dungeon {
        uint32 id;
        uint40 proposalTimestamp;
        uint40 generatedTimestamp;
        uint40 executeTimestamp;
        bool cleared; // false = open, true = not availabel
        DungeonType dungeonType;
        ProposalStatus status;
        uint256 genRequestId; // Used for generation
        uint256 execRequestId; // Used for win/loss execution
        uint256 totalPower; // Of all participants in the raid
        uint256 goldReward;
        uint256 gemReward;
    }

    IRaider baseNFT;
    ILoot itemsNFT;

    uint32 public dungeonId = 1;
    uint256 public proposalId = 1;
    uint256 basePowerRequired = 50; // COMMON
    uint256 baseParticipantsLimit = 20;
    uint256 baseGoldReward = 100 ether;
    uint256 baseGemReward = 10 ether;
    uint256 expirationTime = 2 days;
    uint256 proposalTime = 5 minutes;

    mapping(uint256 => Dungeon) public dungeons;
    mapping(uint256 => mapping(uint256 => uint256))
        public dungeonParticipantPower;
    mapping(uint256 => uint256) public dungeonToProposal;

    // VRF Setup
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 public s_subscriptionId;
    address public vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab; // Rinkeby
    bytes32 public keyHash =
        0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // Rinkeby
    uint32 public callbackGasLimit = 200000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 3;
    uint256 public s_requestId;

    mapping(uint256 => uint256[]) public genRequestIdToRandomWords;
    mapping(uint256 => uint256[]) public execRequestIdToRandomWords;
    mapping(uint256 => uint32) public genRequestIdToDungeon;
    mapping(uint256 => uint32) public execRequestIdToDungeon;
    mapping(uint32 => uint256) public dungeonToGenReqId;
    mapping(uint32 => uint256) public dungeonToExecReqId;

    constructor(
        address _baseNFT,
        address _itemsNFT,
        uint16 _subscriptionId
    ) VRFConsumerBaseV2(vrfCoordinator) {
        baseNFT = IRaider(_baseNFT);
        itemsNFT = ILoot(_itemsNFT);
        s_subscriptionId = _subscriptionId;
    }

    /* ----- MOCK FUNCTIONS ----- */

    function mockGenerateDungeon() external onlyOwner returns (uint256) {
        uint32 currentId = dungeonId;
        dungeons[dungeonId++] = Dungeon(
            currentId,
            0,
            uint40(block.timestamp),
            0,
            false,
            DungeonType.COMMON,
            ProposalStatus.NONE,
            0,
            0,
            0,
            1000 ether,
            100 ether
        );
        return currentId;
    }

    function mockExecuteDungeon(uint256 _dungeonId) external onlyOwner {
        if (_dungeonId >= dungeonId) revert InvalidDungeon();
        Dungeon memory dungeon = dungeons[_dungeonId];
        if (dungeon.status != ProposalStatus.ONGOING) revert InvalidDungeon();
        if (block.timestamp < dungeon.proposalTimestamp + proposalTime)
            revert NotExecutionTime();
        uint256 basePower = basePowerRequired *
            ((10 * uint256(dungeon.dungeonType))**3) +
            basePowerRequired;
        if (dungeon.totalPower < basePower) {
            dungeon.status = ProposalStatus.FAILED;
        } else {
            dungeon.status = ProposalStatus.PASSED;
            dungeon.cleared = true;
        }
        dungeons[_dungeonId] = dungeon;
    }

    function setCallbackGasLimit(uint32 amount) public onlyOwner {
        callbackGasLimit = amount;
    }

    function setS_subscriptionId(uint64 id) public onlyOwner {
        s_subscriptionId = id;
    }

    function generateDungeon() external onlyOwner {
        uint256 requestId = requestRandomWords();
        uint32 currentId = dungeonId;
        genRequestIdToDungeon[requestId] = currentId;
        dungeonToGenReqId[currentId] = requestId;

        dungeons[dungeonId++] = Dungeon(
            currentId,
            0,
            0,
            0,
            false,
            DungeonType.GENERATING,
            ProposalStatus.NONE,
            requestId,
            0,
            0,
            0,
            0
        );
    }

    function discoverDungeon(uint32 _dungeonId) external {
        uint256 genReqId = dungeonToGenReqId[_dungeonId];
        uint256[] memory randomWords = genRequestIdToRandomWords[genReqId];
        Dungeon memory dungeon = dungeons[_dungeonId];
        Dungeon memory dungeonPost = _getRarity(randomWords, _dungeonId);

        if (dungeon.dungeonType != DungeonType.GENERATING)
            revert InvalidDungeon();
        if (_dungeonId >= dungeonId) revert InvalidDungeon();

        (uint256 goldReward, uint256 gemReward) = _getDungeonReward(
            genReqId,
            dungeon
        );
        // Set rewards
        dungeonPost.goldReward = goldReward;
        dungeonPost.gemReward = gemReward;
        dungeonPost.generatedTimestamp = uint40(block.timestamp);
        dungeons[dungeon.id] = dungeonPost;
    }

    function proposeDungeon(uint32 _dungeonId, uint256 _tokenId)
        external
        nonReentrant
    {
        if (_dungeonId >= dungeonId) revert InvalidDungeon();
        Dungeon memory dungeon = dungeons[_dungeonId];
        (
            address tokenOwner,
            uint40 tokenPower,
            bool tokenRaiding,
            bool tokenDelegated
        ) = baseNFT.getTokenInfo(_tokenId);

        if (dungeon.dungeonType == DungeonType.GENERATING)
            revert DungeonNotGenerated();
        if (dungeon.status != ProposalStatus.NONE) revert AlreadyProposed();
        if (dungeon.cleared) revert DungeonCleared();
        if (block.timestamp > dungeon.generatedTimestamp + expirationTime)
            revert TimeHasExpired();
        if (tokenOwner != msg.sender) revert NotTokenOwner();
        if (tokenRaiding) revert TokenAlreadyRaiding();

        dungeon.status = ProposalStatus.ONGOING;
        dungeon.proposalTimestamp = uint40(block.timestamp);
        dungeon.totalPower += tokenPower;
        dungeons[_dungeonId] = dungeon;

        baseNFT.joinRaid(_tokenId);
    }

    function joinDungeon(uint32 _dungeonId, uint256 _tokenId)
        external
        nonReentrant
    {
        if (_dungeonId >= dungeonId) revert InvalidDungeon();
        Dungeon memory dungeon = dungeons[_dungeonId];
        (
            address tokenOwner,
            uint40 tokenPower,
            bool tokenRaiding,
            bool tokenDelegated
        ) = baseNFT.getTokenInfo(_tokenId);
        if (dungeon.status != ProposalStatus.ONGOING) revert InvalidDungeon();
        if (block.timestamp > dungeon.proposalTimestamp + proposalTime)
            revert TimeHasExpired();
        if (tokenOwner != msg.sender) revert NotTokenOwner();
        if (tokenRaiding) revert TokenAlreadyRaiding();
        if (dungeonParticipantPower[_dungeonId][_tokenId] != 0)
            revert TokenAlreadyRaiding();

        dungeon.totalPower += tokenPower;
        dungeonParticipantPower[_dungeonId][_tokenId] = tokenPower;
        dungeons[_dungeonId] = dungeon;

        baseNFT.joinRaid(_tokenId);
    }

    function executeDungeon(uint32 _dungeonId) external nonReentrant {
        if (_dungeonId >= dungeonId) revert InvalidDungeon();
        Dungeon memory dungeon = dungeons[_dungeonId];
        if (dungeon.status != ProposalStatus.ONGOING) revert InvalidDungeon();
        if (block.timestamp < dungeon.proposalTimestamp + proposalTime)
            revert NotExecutionTime();
        uint256 basePower = basePowerRequired *
            ((10 * uint256(dungeon.dungeonType))**3) +
            basePowerRequired;

        if (dungeon.totalPower < basePower) {
            dungeon.status = ProposalStatus.FAILED;
        } else {
            uint256 requestId = requestRandomWords();
            execRequestIdToDungeon[requestId] = dungeon.id;
            dungeonToExecReqId[dungeon.id] = requestId;
            dungeon.execRequestId = requestId;
            dungeon.executeTimestamp = uint40(block.timestamp);
        }
        dungeons[_dungeonId] = dungeon;
    }

    function finishRaid(uint32 _dungeonId) external nonReentrant {
        if (_dungeonId >= dungeonId) revert InvalidDungeon();

        Dungeon memory dungeon = dungeons[_dungeonId];
        if (dungeon.status != ProposalStatus.ONGOING) revert InvalidDungeon();
        if (block.timestamp < dungeon.proposalTimestamp + proposalTime)
            revert NotExecutionTime();
        uint256 execReqId = dungeonToExecReqId[_dungeonId];
        if (execReqId == 0) revert NotExecutionTime();
        uint256[] memory randomWords = execRequestIdToRandomWords[execReqId];
        if (randomWords.length < 3) revert NotExecutionTime();

        uint256 randNumber = randomWords[0];

        uint256 maxPower = (basePowerRequired *
            ((10 * uint256(dungeon.dungeonType))**3) +
            basePowerRequired) * 4;
        if (dungeon.totalPower >= maxPower) {
            // Give max percentage
            uint256 percentage = 95 - (5 * uint256(dungeon.dungeonType));
            if (randNumber % 100 < percentage) {
                // WIN
                dungeon.status == ProposalStatus.PASSED;
                dungeon.cleared = true;
            } else {
                // LOSE
                dungeon.status == ProposalStatus.FAILED;
                dungeon.cleared = false;
            }
        } else {
            // Calculate percentage
            uint256 percentage = (dungeon.totalPower * 100) /
                maxPower -
                (5 * uint256(dungeon.dungeonType) + 5);

            if (randNumber % 100 < percentage) {
                // WIN
                dungeon.status == ProposalStatus.PASSED;
                dungeon.cleared = true;
            } else {
                // LOSE
                dungeon.status == ProposalStatus.FAILED;
                dungeon.cleared = false;
            }
        }

        dungeons[dungeon.id] = dungeon;
    }

    function claimReward(uint32 _dungeonId, uint256 _tokenId)
        external
        nonReentrant
    {
        Dungeon memory dungeon = dungeons[_dungeonId];
        if (dungeon.status != ProposalStatus.PASSED) revert DungeonNotCleared();
        if (!dungeon.cleared) revert DungeonNotCleared();
        // Require that msg.sender is token owner or delegated (if we have time to implement)
        (address tokenOwner, , , bool tokenDelegated) = baseNFT.getTokenInfo(
            _tokenId
        );
        if (tokenOwner != msg.sender) revert NotTokenOwner();
        if (dungeonParticipantPower[_dungeonId][_tokenId] == 0)
            revert TokenNotInRaidParty();

        (uint256 goldReward, uint256 gemReward) = _getParticipantReward(
            _dungeonId,
            _tokenId
        );
        dungeonParticipantPower[_dungeonId][_tokenId] = 0;
        itemsNFT.mintReward(tokenOwner, goldReward, gemReward);
        baseNFT.exitRaid(_tokenId);
    }

    function getDungeonReward(uint32 _dungeonId)
        public
        view
        returns (uint256, uint256)
    {
        Dungeon memory dungeon = dungeons[_dungeonId];
        require(
            dungeon.dungeonType != DungeonType.GENERATING,
            "Dungeon is still generating"
        );

        return (dungeon.goldReward, dungeon.gemReward);
    }

    function getParticipantReward(uint32 _dungeonId, uint256 _tokenId)
        public
        view
        returns (uint256, uint256)
    {
        return _getParticipantReward(_dungeonId, _tokenId);
    }

    function _getParticipantReward(uint32 _dungeonId, uint256 _tokenId)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 power = dungeonParticipantPower[_dungeonId][_tokenId];
        require(power > 0, "Not participant");

        Dungeon memory dungeon = dungeons[_dungeonId];
        require(
            dungeon.dungeonType != DungeonType.GENERATING,
            "Dungeon is still generating"
        );
        uint256 percentage = (power * 10000) / dungeon.totalPower;

        uint256 userGoldReward = (dungeon.goldReward * percentage) / 10000;
        uint256 userGemReward = (dungeon.gemReward * percentage) / 10000;

        return (userGoldReward, userGemReward);
    }

    function _calcReward(
        uint256 baseReward,
        uint256 multiplier,
        uint256 percentage
    ) internal pure returns (uint256) {
        return (baseReward *
            (2**multiplier) +
            ((baseReward * (2**multiplier)) * percentage) /
            10000);
    }

    function _getRarity(uint256[] memory _randomWords, uint256 _dungeonId)
        internal
        view
        returns (Dungeon memory)
    {
        uint256 number = (_randomWords[0] % 100) + 1;
        Dungeon memory dungeon = dungeons[_dungeonId];
        if (number > 45) {
            // Check the common and uncommon rarities
            if (number > 70) {
                dungeon.dungeonType = DungeonType.COMMON;
            } else {
                dungeon.dungeonType = DungeonType.UNCOMMON;
            }
        } else if (number > 10) {
            // Check rare and epic
            if (number > 25) {
                dungeon.dungeonType = DungeonType.RARE;
            } else {
                dungeon.dungeonType = DungeonType.EPIC;
            }
        } else {
            // Check legendary and world
            if (number > 3) {
                dungeon.dungeonType = DungeonType.LEGENDARY;
            } else {
                dungeon.dungeonType = DungeonType.WORLD;
            }
        }

        return dungeon;
    }

    function _getDungeonReward(uint256 _requestId, Dungeon memory dungeon)
        internal
        view
        returns (uint256, uint256)
    {
        uint256[] memory randomWords = genRequestIdToRandomWords[_requestId];
        uint256 percentageGold = ((randomWords[1] % 100) + 1) * 100;
        uint256 percentageGem = ((randomWords[2] % 100) + 1) * 100;

        uint256 goldReward = _calcReward(
            baseGoldReward,
            uint256(dungeon.dungeonType),
            percentageGold
        );
        uint256 gemReward = _calcReward(
            baseGemReward,
            uint256(dungeon.dungeonType),
            percentageGem
        );

        return (goldReward, gemReward);
    }

    function requestRandomWords() public returns (uint256) {
        // Will revert if subscription is not set and funded.
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        // Store the latest requestId
        s_requestId = requestId;

        // Return the requestId to the requester.
        return requestId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords)
        internal
        override
    {
        if (genRequestIdToDungeon[requestId] > 0) {
            genRequestIdToRandomWords[requestId] = randomWords;
        } else {
            execRequestIdToRandomWords[requestId] = randomWords;
        }
    }
}
