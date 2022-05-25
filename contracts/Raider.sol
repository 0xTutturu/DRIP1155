//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./libs/ERC721G.sol";
import "./ILoot.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

error ValueTooLow();
error WrongCaller();

// RINKEBY: 0x387ED53DeedB64F8667aA2300665074D0bFb4861

contract Raider is ERC721G, ReentrancyGuard, Ownable {
    using Strings for uint256;

    string baseURI;
    uint256 price = 0.02 ether;
    ILoot public lootContract;
    address dungeonRaidContract;

    constructor(address lootContract_) ERC721G("Raiders", "RAID", 1, 10000, 3) {
        lootContract = ILoot(lootContract_);
    }

    /* ------------- User interaction ------------- */

    function mint(uint256 quantity) external payable nonReentrant {
        if (msg.value < price * quantity) revert ValueTooLow();
        _mint(msg.sender, quantity);
    }

    // This function is only used to simplify the frontend work
    // Would not be the way I would do it in production
    function mintWithItems() external payable nonReentrant {
        if (msg.value < price) revert ValueTooLow();
        uint256 id = startingIndex + totalSupply;
        uint256 itemId = 2 + lootContract.totalSupply();
        uint256[3] memory equipped;
        _mint(msg.sender, 1);
        TokenData memory token = _tokenDataOf(id);

        for (uint256 i; i < 3; i++) {
            lootContract.mintItemFor(msg.sender, uint8(2 + i));
            (uint256 index, uint256 newPower, uint256 oldPower) = lootContract
                .equipItem(equippedItems[id], itemId, msg.sender, id);

            token.power -= uint40(oldPower);
            token.power += uint40(newPower);
            equipped[index] = itemId;
            itemId++;
        }
        _tokenData[id] = token;
        equippedItems[id] = equipped;
    }

    function useExpGems(uint256 tokenId, uint16 levels)
        external
        override
        nonReentrant
    {
        TokenData memory token = _tokenDataOf(tokenId);
        if (token.owner != msg.sender) revert IncorrectOwner();
        if (token.raiding) revert TokenIdRaiding();
        uint256 totalReqExp;
        uint256 totalPowerIncrease;
        for (uint256 i; i < levels; i++) {
            (uint256 reqExp, uint256 powerIncrease) = _levelUpInfo(
                token.level + i
            );
            totalReqExp += reqExp;
            totalPowerIncrease += powerIncrease;
        }

        token.power += uint40(totalPowerIncrease);
        token.level += levels;
        _tokenData[tokenId] = token;
        lootContract.burnGems(msg.sender, totalReqExp);
    }

    function equipItems(uint256 tokenId, uint256 equipmentId)
        external
        override
        nonReentrant
    {
        TokenData memory token = _tokenDataOf(tokenId);
        if (token.raiding) revert TokenIdRaiding();
        if (token.owner != msg.sender) revert IncorrectOwner();

        // Check if user owns the items is done in the loot contract
        (uint256 index, uint256 newPower, uint256 oldPower) = lootContract
            .equipItem(
                equippedItems[tokenId],
                equipmentId,
                msg.sender,
                tokenId
            );
        token.power -= uint40(oldPower);
        token.power += uint40(newPower);
        equippedItems[tokenId][index] = equipmentId;
        _tokenData[tokenId] = token;
    }

    // function drinkPotion() external nonReentrant {}

    function joinRaid(uint256 tokenId) external {
        if (msg.sender != dungeonRaidContract) revert WrongCaller();
        TokenData memory token = _tokenDataOf(tokenId);
        token.raiding = true;
        _tokenData[tokenId] = token;
    }

    function exitRaid(uint256 tokenId) external {
        if (msg.sender != dungeonRaidContract) revert WrongCaller();
        TokenData memory token = _tokenDataOf(tokenId);
        token.raiding = false;
        _tokenData[tokenId] = token;
    }

    /* ------------- View ------------- */

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (!_exists(id)) revert NonexistentToken();

        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, id.toString(), ".json"))
                : "";
    }

    function getTokenInfo(uint256 id)
        external
        view
        returns (
            address,
            uint40,
            bool,
            bool
        )
    {
        TokenData memory token = _tokenDataOf(id);
        return (token.owner, token.power, token.raiding, token.delegated);
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
