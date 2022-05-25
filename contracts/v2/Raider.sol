//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../solmate/ERC721G.sol";
import "../ILoot.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

error ValueTooLow();
error WrongCaller();
error MaxSupplyReached();
error MaxMintReached();

// RINKEBY: 0x387ED53DeedB64F8667aA2300665074D0bFb4861

contract Raider is ERC721G, ReentrancyGuard, Ownable {
    using Strings for uint256;

    string public baseURI;
    uint256 public price = 0.02 ether;
    uint256 public maxSupply;
    uint256 public startingIndex;
    uint256 public maxMint;

    ILoot public lootContract;
    address dungeonRaidContract;

    constructor(
        address lootContract_,
        uint256 startingIndex_,
        uint256 maxSupply_
    ) ERC721G("Raiders", "RAID") {
        startingIndex = startingIndex_;
        maxSupply = maxSupply_;
        lootContract = ILoot(lootContract_);
    }

    /* ------------- User interaction ------------- */

    function mint(Class class, string memory name_)
        external
        payable
        nonReentrant
    {
        if (msg.value < price) revert ValueTooLow();
        if (totalSupply > maxSupply) revert MaxSupplyReached();
        if (_userData[msg.sender].minted >= maxMint) revert MaxMintReached();

        uint256 id = startingIndex + totalSupply;

        _mint(msg.sender, id, class, name_);
    }

    function useExpGems(uint256 id, uint16 levels)
        external
        override
        nonReentrant
    {
        TokenData memory token = _tokenData[id];
        if (token.owner != msg.sender) revert IncorrectOwner();
        if (token.raiding) revert LockedInRaid();
        uint256 totalReqExp;
        uint256 totalPowerIncrease;
        for (uint256 i; i < levels; i++) {
            (uint256 reqExp, uint256 powerIncrease) = _levelUpInfo(
                token.character.level + i
            );
            totalReqExp += reqExp;
            totalPowerIncrease += powerIncrease;
        }

        token.character.power += uint32(totalPowerIncrease);
        token.character.level += levels;
        token.character.statPoints += levels * 5;
        _tokenData[id] = token;
        lootContract.burnGems(msg.sender, totalReqExp);
    }

    function equipItems(uint256 id, uint256 equipmentId)
        external
        override
        nonReentrant
    {
        TokenData memory token = _tokenData[id];
        if (token.raiding) revert LockedInRaid();
        if (token.owner != msg.sender) revert IncorrectOwner();

        // Check if user owns the items is done in the loot contract
        (uint256 index, uint256 newPower, uint256 oldPower) = lootContract
            .equipItem(_equippedItems[id], equipmentId, msg.sender, id);
        token.character.power -= uint32(oldPower);
        token.character.power += uint32(newPower);
        _equippedItems[id][index] = equipmentId;
        _tokenData[id] = token;
    }

    function drinkPotion(uint256 id, uint256 itemId)
        external
        virtual
        override
    {}

    function joinRaid(uint256 id) external {
        if (msg.sender != dungeonRaidContract) revert WrongCaller();
        TokenData memory token = _tokenData[id];
        token.raiding = true;
        _tokenData[id] = token;
    }

    function exitRaid(uint256 id) external {
        if (msg.sender != dungeonRaidContract) revert WrongCaller();
        TokenData memory token = _tokenData[id];
        token.raiding = false;
        _tokenData[id] = token;
    }

    /* ------------- View ------------- */

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_tokenData[id].owner == address(0)) revert NonexistentToken();

        bytes(baseURI).length > 0
            ? string(abi.encodePacked(baseURI, id.toString(), ".json"))
            : "";
    }

    function levelUpInfo(uint256 id, uint256 levels)
        external
        view
        returns (uint256, uint256)
    {
        Character memory char = _tokenData[id].character;
        uint256 totalReqGems;
        uint256 totalPowerIncrease;
        for (uint256 i; i < levels; i++) {
            (uint256 reqGems, uint256 powerIncrease) = _levelUpInfo(
                char.level + i
            );
            totalReqGems += reqGems;
            totalPowerIncrease += powerIncrease;
        }

        return (totalReqGems, totalPowerIncrease);
    }

    function getCharStats(uint256 id) external view returns (Character memory) {
        require(_tokenData[id].owner != address(0), "DOESN'T_EXIST");
        return _tokenData[id].character;
    }

    function isRaiding(uint256 id) external view returns (bool) {
        return _tokenData[id].raiding;
    }

    function numRaiding(address user) external view returns (uint256) {
        return _userData[user].raiding;
    }

    function numOwned(address user) external view returns (uint256) {
        UserData memory userData = _userData[user];
        return userData.balance + userData.raiding;
    }

    function numMinted(address user) external view returns (uint256) {
        return _userData[user].minted;
    }

    function totalNumRaiding() external view returns (uint256) {
        unchecked {
            uint256 count;
            for (
                uint256 i = startingIndex;
                i < startingIndex + totalSupply;
                ++i
            ) {
                if (_tokenData[i].raiding) ++count;
            }
            return count;
        }
    }

    /* ------------- Only Owner ------------- */

    function setPrice(uint256 amount) external onlyOwner {
        price = amount;
    }

    function setLootContract(address loot) external onlyOwner {
        lootContract = ILoot(loot);
    }

    function setDungeonContract(address dungeon) external onlyOwner {
        dungeonRaidContract = dungeon;
    }

    function setBaseURI(string memory uri) external onlyOwner {
        baseURI = uri;
    }
}
