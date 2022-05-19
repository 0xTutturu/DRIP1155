//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./libs/ERC1155G.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

error InvalidId();
error NotOwner();
error MintLimitReached();
error NotApprovedContract();
error ArraysNotEqualLength();
error ValueTooLow();
error InvalidType();
error ItemIsEquipped();

contract Loot is ERC1155G, ReentrancyGuard, Ownable {
    /* 
        IDs:
        0 - Gold
        1 - Gems
        2 ... - Items

        itemTypes:
        2 - Accessory
        3 - Armor
        4 - Weapon
     */

    uint256 startIndex = 2;
    uint256 public totalSupplyItems;
    uint256 mintLimit = 1;
    uint256 price = 0.01 ether;

    address dungeonRaidContract;
    // NFT INTERFACE NEEDED

    mapping(address => mapping(uint256 => uint256)) public userMintedOfType;

    constructor(string memory uri, address raidContract) ERC1155G(uri) {
        dungeonRaidContract = raidContract;
    }

    /* ----- User interaction ----- */

    /* @notice Mints a single item to the caller
     * @dev
     * TODO: Check if the data of _mint should be empty
     */
    function mintItem(uint8 itemType) external payable nonReentrant {
        if (itemType > 4 || itemType < 2) revert InvalidType();
        if (userMintedOfType[msg.sender][itemType] >= mintLimit)
            revert MintLimitReached();
        if (msg.value < price) revert ValueTooLow();
        uint256 index = startIndex + totalSupplyItems;
        totalSupplyItems += 1;
        idToEquipment[index] = Equipment(uint40(1), uint40(5), itemType, false);
        _mint(msg.sender, index, 1, "");
    }

    /* @notice Used by users to enhance their items power/level
     * @dev
     * TODO: Check if the NFT is equipped on a character, check if the character is in a raid
     */
    function enhanceItem(uint256 itemId, uint40 levels) external {
        Equipment memory equipment = idToEquipment[itemId];
        if (itemId >= startIndex + totalSupplyItems) revert InvalidId();
        if (balanceOf(msg.sender, itemId) == 0) revert NotOwner();

        // !!! Check if the NFT that has this item equipped is in a raid right now

        uint256 totalReqGold;
        uint256 totalPowerIncrease;

        for (uint256 i; i < levels; i++) {
            (uint256 reqGold, uint256 powerIncrease) = _calcEnhancement(
                uint256(equipment.level),
                equipment.itemType
            );
            totalReqGold += reqGold;
            totalPowerIncrease += powerIncrease;
        }

        equipment.level += levels;
        equipment.power += uint40(totalPowerIncrease);
        idToEquipment[itemId] = equipment;
        _burn(msg.sender, 0, totalReqGold);
    }

    /* ----- Raider contract only ----- */

    function equipItem(
        uint256[3] memory equippedItems,
        uint256 itemId,
        address user
    )
        external
        returns (
            uint256,
            uint256,
            uint256 oldPower
        )
    {
        if (itemId < 2 || itemId >= startIndex + totalSupplyItems)
            revert InvalidId();
        Equipment memory newEquipment = idToEquipment[itemId];

        if (newEquipment.equipped) revert ItemIsEquipped();
        if (balanceOf(user, itemId) == 0) revert NotOwner();

        uint256 itemType = uint256(newEquipment.itemType);
        uint256 oldItemId = equippedItems[itemType - 2];
        if (oldItemId != 0) {
            Equipment memory oldEquipment = idToEquipment[oldItemId];

            oldEquipment.equipped = false;
            idToEquipment[oldItemId] = oldEquipment;
            oldPower = oldEquipment.power;
        } else {
            oldPower = 0;
        }

        newEquipment.equipped = true;
        idToEquipment[itemId] = newEquipment;

        return (itemType - 2, newEquipment.power, oldPower);
    }

    /* ----- Dungeon Raid Contract only ----- */

    /* @notice Mints gold and gems to a user through the dungeon raid contract
     * @dev Arrays need to be of equal length. Only callable by dungeon raid contract
     */
    function mintReward(
        address user,
        uint256 gold,
        uint256 gems
    ) external {
        if (msg.sender != dungeonRaidContract) revert NotApprovedContract();
        _mint(user, 0, gold, "");
        _mint(user, 1, gems, "");
    }

    /* @notice Burns gems as Exp to level up the character
     * @dev Only callable by dungeon raid contract
     */
    function burnGems(address user, uint256 amount) external {
        if (msg.sender != dungeonRaidContract) revert NotApprovedContract();
        _burn(user, 1, amount);
    }

    /* ----- Owner only ----- */

    /* ----- View ----- */

    function getEnhancementInfo(uint256 itemId, uint40 levels)
        external
        view
        returns (uint256, uint256)
    {
        Equipment memory equipment = idToEquipment[itemId];
        if (itemId >= startIndex + totalSupplyItems) revert InvalidId();

        uint256 totalReqGold;
        uint256 totalPowerIncrease;

        // Check how much gold needs to be burned
        for (uint256 i; i < levels; i++) {
            (uint256 reqGold, uint256 powerIncrease) = _calcEnhancement(
                uint256(equipment.level),
                equipment.itemType
            );
            totalReqGold += reqGold;
            totalPowerIncrease += powerIncrease;
        }

        return (totalReqGold, totalPowerIncrease);
    }

    /* ----- Internal ----- */

    function _calcEnhancement(uint256 level, uint8 itemType)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 growthRate = uint256(itemType) * 1000;
        uint256 reqGold = (4 * (level**3) + 80 * (level**2) + 2 * 4) / 100;
        uint256 powerIncrease = ((20 * (level**3)) +
            (20 * (level**3) * growthRate) /
            10000) / 1000;
        return (reqGold, powerIncrease);
    }
}
