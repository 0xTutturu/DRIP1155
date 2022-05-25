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

error InvalidCaller();

error TokenAlreadyRaiding();
error TokenNotInRaidParty();

// RINKEBY: 0x732393257F1cAC5FB91DBb8d31b6a7a858e26130

contract DungeonRaid is Ownable, ReentrancyGuard, VRFConsumerBaseV2 {
    enum DungeonRarity {
        COMMON, // 95% clear on max power, 50% on min power, reward multiplier x1, average power 10
        UNCOMMON, // 90 %, 45 // x2, average power 20
        RARE, // 85%, 40 // x4, average power 35
        EPIC, // 80 %, 35 // x8, average power 50
        LEGENDARY, // 75%, 30 // x16, average power 70
        WORLD, // 70%, 25%, x32, no average power, just a high number count
        GENERATING
    }

    enum DungeonType {
        GOLEM,
        FAIRY,
        BEAST,
        NONE,
        GENERATING
    }

    enum ProposalStatus {
        NONE,
        ONGOING,
        PASSED,
        FAILED
    }

    struct Dungeon {
        uint32 id;
        uint40 proposalTimestamp;
        uint40 generatedTimestamp;
        uint40 executeTimestamp;
        bool cleared; // false = open, true = not availabel
        bool solo;
        DungeonRarity dungeonRarity;
        DungeonType dungeonType;
        ProposalStatus status;
        uint256 genRequestId; // Used for generation
        uint256 execRequestId; // Used for win/loss execution
        uint256 totalPower; // Of all participants in the raid
    }

    /* Ores - 0, Runes - 1, Salts - 2, Magic dust - 3, Skins - 4, Herbs - 5, Ingots - 6, Leathers - 7, Gold - 8, Gems - 9 */

    IRaider baseNFT;
    ILoot itemsNFT;

    uint32 public dungeonId = 1;
    uint256 public proposalId = 1;
    uint256 public basePowerRequired = 50; // COMMON
    uint256 public baseParticipantsLimit = 20;
    uint256 public expirationTime = 2 days;
    uint256 public proposalTime = 5 minutes;

    mapping(uint256 => Dungeon) public dungeons;
    mapping(uint256 => uint256[]) public dungeonRewards;
    mapping(DungeonType => uint256[]) public dungeonRewardTypes;
    mapping(uint256 => uint256) public baseRewards;
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

    // Could use one mapping
    mapping(uint256 => uint256[]) public genRequestIdToRandomWords;
    mapping(uint256 => uint256[]) public execRequestIdToRandomWords;

    mapping(uint256 => uint32) public genRequestIdToDungeon;
    mapping(uint256 => uint32) public execRequestIdToDungeon;

    mapping(uint32 => uint256) public dungeonToGenReqId;
    mapping(uint32 => uint256) public dungeonToExecReqId;

    constructor(
        address _baseNFT,
        address _itemsNFT,
        uint16 _subscriptionId,
        uint256[] memory _baseRewards,
        uint256[][] memory _rewardTypes
    ) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        baseNFT = IRaider(_baseNFT);
        itemsNFT = ILoot(_itemsNFT);
        s_subscriptionId = _subscriptionId;
        for (uint256 i; i < _baseRewards.length; i++) {
            baseRewards[i] = _baseRewards[i];
        }
        for (uint256 i; i < _rewardTypes.length; i++) {
            dungeonRewardTypes[DungeonType(i)] = _rewardTypes[i];
        }
    }

    // TODO: Implement solo raids
    // TODO: Implement fetch for all active/proposed dungeons

    /* ----- MOCK FUNCTIONS ----- */

    /*     function mockGenerateDungeon() external onlyOwner returns (uint256) {
        uint32 currentId = dungeonId;
        dungeons[dungeonId++] = Dungeon(
            currentId,
            0,
            uint40(block.timestamp),
            0,
            false,
            DungeonRarity.COMMON,
            DungeonType.GOLEM,
            ProposalStatus.NONE,
            0,
            0,
            0
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
            ((10 * uint256(dungeon.dungeonRarity))**3) +
            basePowerRequired;
        if (dungeon.totalPower < basePower) {
            dungeon.status = ProposalStatus.FAILED;
        } else {
            dungeon.status = ProposalStatus.PASSED;
            dungeon.cleared = true;
        }
        dungeons[_dungeonId] = dungeon;
    } */

    function generateDungeon(bool solo) external onlyOwner {
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
            solo,
            DungeonRarity.GENERATING,
            DungeonType.GENERATING,
            ProposalStatus.NONE,
            requestId,
            0,
            0
        );
    }

    function discoverDungeon(uint32 _dungeonId) external {
        uint256 genReqId = dungeonToGenReqId[_dungeonId];
        uint256[] memory randomWords = genRequestIdToRandomWords[genReqId];
        Dungeon memory dungeon = dungeons[_dungeonId];
        Dungeon memory dungeonPost = _getRarity(randomWords, _dungeonId);

        if (dungeon.dungeonRarity != DungeonRarity.GENERATING)
            revert InvalidDungeon();
        if (_dungeonId >= dungeonId) revert InvalidDungeon();

        uint256[] memory rewards = _getDungeonReward(genReqId, dungeon);
        // Set rewards
        dungeonRewards[_dungeonId] = rewards;
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

        if (dungeon.dungeonRarity == DungeonRarity.GENERATING)
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
            ((10 * uint256(dungeon.dungeonRarity))**3) +
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
        uint256[] memory randomWords = execRequestIdToRandomWords[execReqId];
        if (randomWords.length < 3) revert NotExecutionTime();

        uint256 randNumber = randomWords[0];

        uint256 maxPower = (basePowerRequired *
            ((10 * uint256(dungeon.dungeonRarity))**3) +
            basePowerRequired) * 4;
        if (dungeon.totalPower >= maxPower) {
            // Give max percentage
            uint256 percentage = 95 - (5 * uint256(dungeon.dungeonRarity));
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
                (5 * uint256(dungeon.dungeonRarity) + 5);

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

    function exitDungeon(uint32 _dungeonId, uint256 _tokenId) external {
        if (_dungeonId >= dungeonId) revert InvalidDungeon();
        Dungeon memory dungeon = dungeons[_dungeonId];
        if (dungeon.status != ProposalStatus.FAILED) revert InvalidDungeon();
        (address tokenOwner, , , bool tokenDelegated) = baseNFT.getTokenInfo(
            _tokenId
        );
        if (tokenOwner != msg.sender) revert NotTokenOwner();
        if (dungeonParticipantPower[_dungeonId][_tokenId] == 0)
            revert TokenNotInRaidParty();
        dungeonParticipantPower[_dungeonId][_tokenId] = 0;

        baseNFT.exitRaid(_tokenId);
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

        (
            uint256[] memory rewardTypes,
            uint256[] memory rewardAmounts
        ) = _getParticipantReward(_dungeonId, _tokenId);

        dungeonParticipantPower[_dungeonId][_tokenId] = 0;
        itemsNFT.mintReward(tokenOwner, rewardTypes, rewardAmounts);
        baseNFT.exitRaid(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW
    //////////////////////////////////////////////////////////////*/

    function getDungeonReward(uint32 _dungeonId)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        Dungeon memory dungeon = dungeons[_dungeonId];
        require(
            dungeon.dungeonRarity != DungeonRarity.GENERATING,
            "Dungeon is still generating"
        );

        return (
            dungeonRewardTypes[dungeon.dungeonType],
            dungeonRewards[_dungeonId]
        );
    }

    function getParticipantReward(uint32 _dungeonId, uint256 _tokenId)
        public
        view
        returns (uint256[] memory, uint256[] memory)
    {
        return _getParticipantReward(_dungeonId, _tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                             INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _getParticipantReward(uint32 _dungeonId, uint256 _tokenId)
        internal
        view
        returns (uint256[] memory, uint256[] memory)
    {
        uint256 power = dungeonParticipantPower[_dungeonId][_tokenId];
        require(power > 0, "Not participant");

        Dungeon memory dungeon = dungeons[_dungeonId];
        require(
            dungeon.dungeonRarity != DungeonRarity.GENERATING,
            "Dungeon is still generating"
        );
        uint256 percentage = (power * 10000) / dungeon.totalPower;
        uint256[] memory rewards = dungeonRewards[_dungeonId];
        uint256[] memory userRewards;

        for (uint256 i; i < rewards.length; ) {
            userRewards[i] = (rewards[i] * percentage) / 10000;
            unchecked {
                ++i;
            }
        }

        return (dungeonRewardTypes[dungeon.dungeonType], userRewards);
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
        dungeon.dungeonType = DungeonType(number % 4);
        if (number > 45) {
            // Check the common and uncommon rarities
            if (number > 70) {
                dungeon.dungeonRarity = DungeonRarity.COMMON;
            } else {
                dungeon.dungeonRarity = DungeonRarity.UNCOMMON;
            }
        } else if (number > 10) {
            // Check rare and epic
            if (number > 25) {
                dungeon.dungeonRarity = DungeonRarity.RARE;
            } else {
                dungeon.dungeonRarity = DungeonRarity.EPIC;
            }
        } else {
            // Check legendary and world
            if (number > 3) {
                dungeon.dungeonRarity = DungeonRarity.LEGENDARY;
            } else {
                dungeon.dungeonRarity = DungeonRarity.WORLD;
            }
        }

        return dungeon;
    }

    function _getDungeonReward(uint256 _requestId, Dungeon memory dungeon)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory randomWords = genRequestIdToRandomWords[_requestId];
        uint256[] memory rewardTypes = dungeonRewardTypes[dungeon.dungeonType];
        uint256[] memory rewards;

        for (uint256 i; i < rewardTypes.length; ) {
            uint256 bonusPerc = ((uint256(
                keccak256(abi.encode(randomWords[0], rewardTypes[i]))
            ) % 100) + 1) * 100;
            rewards[i] = _calcReward(
                baseRewards[rewardTypes[i]],
                uint256(dungeon.dungeonRarity),
                bonusPerc
            );

            unchecked {
                ++i;
            }
        }

        return rewards;
    }

    /*//////////////////////////////////////////////////////////////
                             VRF
    //////////////////////////////////////////////////////////////*/

    function setCallbackGasLimit(uint32 amount) external onlyOwner {
        callbackGasLimit = amount;
    }

    function setS_subscriptionId(uint64 id) external onlyOwner {
        s_subscriptionId = id;
    }

    function setVRFCoordinator(address coordinator) external onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(coordinator);
    }

    function setKeyhash(bytes32 keyhash) external onlyOwner {
        keyHash = keyhash;
    }

    function setReqConfirmations(uint16 amount) external onlyOwner {
        requestConfirmations = amount;
    }

    function setNumWords(uint32 num) external onlyOwner {
        numWords = num;
    }

    // TESTING ONLY
    function req() public returns (uint256) {
        return requestRandomWords();
    }

    function requestRandomWords() internal returns (uint256) {
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

    // EDGE CASE -> ReqId can be 0, I need a different way of determining if it's generating or not
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
