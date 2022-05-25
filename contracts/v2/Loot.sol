//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../solmate/ERC1155Drip.sol";
import "./IRaider.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

error InvalidId();
error NotOwner();
error MintLimitReached();
error NotApprovedContract();
error ArraysNotEqualLength();
error ValueTooLow();
error InvalidType();
error ItemIsEquipped();
error CharacterIsInRaid();
error InvalidMaterial();

// RINKEBY: 0xdCa2A3dF61dC8D526D48872aD49a5D047D751aC9

contract Loot is ERC1155Drip, ReentrancyGuard, Ownable {
    using Strings for uint256;

    /* Ores - 0, Runes - 1, Salts - 2, Magic dust - 3, Skins - 4, Herbs - 5, Ingots - 6, Leathers - 7, Gold - 8, Gems - 9 */
    /* 
        itemTypes:
        10 - Accessory
        11 - Armor
        12 - Weapon
     */

    // Ingots and leathers are required for item creation, giving the base stats
    //

    uint256 startIndex = 10;
    uint256 public totalSupply;
    string public _uri;

    address dungeonRaidContract;
    IRaider raiderContract;

    mapping(uint256 => Equipment) equipments;
    mapping(address => mapping(uint256 => uint256)) public userMintedOfType;
    mapping(uint256 => uint256) public equippedOn;

    constructor(uint256[] memory emissionRates_) ERC1155Drip(emissionRates_) {}

    /* ----- User interaction ----- */

    function createItem(
        uint24[6] memory stats,
        uint256 _type,
        string memory _name
    ) external {
        if (_type < 10 || _type > 12) revert InvalidType();
    }

    function brewPotions() external {}

    function enchantItem() external {}

    function processMaterial(uint256 id, uint256 amount) external {
        if (id != 0 && id != 4) revert InvalidMaterial();
        uint256 resultMaterial = id == 0 ? 6 : 7;
        _burn(msg.sender, id, amount * 3);
        _mint(msg.sender, resultMaterial, amount, "");
    }

    /* @notice Used by users to enhance their items power/level
     * @dev
     * TODO: Check if the NFT is equipped on a character, check if the character is in a raid
     */
    function enhanceItem(uint256 itemId, uint40 levels) external {
        Equipment memory equipment = idToEquipment[itemId];
        if (itemId >= startIndex + totalSupply) revert InvalidId();
        if (balanceOf(msg.sender, itemId) == 0) revert NotOwner();

        // !!! Check if the NFT that has this item equipped is in a raid right now
        uint256 id = equippedOn[itemId];
        if (id != 0) {
            (, , bool raiding, ) = raiderContract.getTokenInfo(id);
            if (raiding) revert CharacterIsInRaid();
        }

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
        //equipment.power += uint40(totalPowerIncrease);
        idToEquipment[itemId] = equipment;
        _burn(msg.sender, 0, totalReqGold);
    }

    /* ----- Raider contract only ----- */

    function equipItem(
        uint256[3] memory equippedItems,
        uint256 itemId,
        address user,
        uint256 raiderId
    )
        external
        returns (
            uint256,
            uint256,
            uint256 oldPower
        )
    {
        if (itemId < 2 || itemId >= startIndex + totalSupply)
            revert InvalidId();
        Equipment memory newEquipment = idToEquipment[itemId];

        if (newEquipment.equipped) revert ItemIsEquipped();
        if (balanceOf(user, itemId) == 0) revert NotOwner();
        if (msg.sender != address(raiderContract)) revert NotApprovedContract();

        uint256 itemType = uint256(newEquipment.itemType);
        uint256 oldItemId = equippedItems[itemType - 2];
        if (oldItemId != 0) {
            Equipment memory oldEquipment = idToEquipment[oldItemId];

            oldEquipment.equipped = false;
            idToEquipment[oldItemId] = oldEquipment;
            oldPower = oldEquipment.power;
            equippedOn[oldItemId] = 0;
        } else {
            oldPower = 0;
        }

        equippedOn[itemId] = raiderId;
        newEquipment.equipped = true;
        idToEquipment[itemId] = newEquipment;

        return (itemType - 2, newEquipment.power, oldPower);
    }

    /* @notice Burns gems as Exp to level up the character
     * @dev Only callable by raider contract
     */
    function burnGems(address user, uint256 amount) external {
        if (msg.sender != address(raiderContract)) revert NotApprovedContract();
        _burn(user, 1, amount);
    }

    /* ----- Dungeon Raid Contract only ----- */

    /* @notice Mints gold and gems to a user through the dungeon raid contract
     * @dev Arrays need to be of equal length. Only callable by dungeon raid contract
     */
    function mintReward(
        address user,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external {
        if (msg.sender != dungeonRaidContract) revert NotApprovedContract();
        _batchMint(user, ids, amounts, "");
    }

    /* ----- Owner only ----- */

    function setDungeonContract(address dungeon) external onlyOwner {
        dungeonRaidContract = dungeon;
    }

    function setRaiderContract(address raider) external onlyOwner {
        raiderContract = IRaider(raider);
    }

    /* ----- View ----- */

    function uri(uint256 id)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return
            bytes(_uri).length > 0
                ? string(abi.encodePacked(_uri, id.toString(), ".json"))
                : "";
    }

    function getEnhancementInfo(uint256 itemId, uint40 levels)
        external
        view
        returns (uint256, uint256)
    {
        Equipment memory equipment = idToEquipment[itemId];
        if (itemId >= startIndex + totalSupply) revert InvalidId();

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

    function _calcCreationCost(uint24[6] memory stats, uint256 _type)
        internal
        pure
        returns (Equipment memory, uint256 reqMaterials)
    {
        // Weapons require 3 ingots and 2 leathers
        // Armor requires 2 ingots and 2 leathers
        // Accessory requires 2 ingots and 1 leather
        // Every 3 stat points it increases the level req
        (uint256 baseIngots, uint256 baseLeathers) = _getBaseMaterialCost(
            _type
        );
        uint256 totalStats;
        for (uint256 i; i < stats.length; ) {
            totalStats += stats[i];
            unchecked {
                ++i;
            }
        }
        uint256 level = totalStats / 3;
    }

    function _getBaseMaterialCost(uint256 _type)
        internal
        pure
        returns (uint256, uint256)
    {
        if (_type == 10) {
            return (3, 2);
        } else if (_type == 11) {
            return (2, 2);
        } else if (_type == 12) {
            return (2, 1);
        } else {
            revert InvalidType();
        }
    }

    function _getReqMaterials(
        uint256 level,
        uint256 ingots,
        uint256 leathers
    ) internal pure returns (uint256, uint256) {
        uint256 baseIngots = (1 * (level ^ 3) + 80 * (level ^ 2) + 20 * 4) /
            100 +
            ingots;
        uint256 baseLeathers = (1 * (level ^ 3) + 80 * (level ^ 2) + 20 * 4) /
            100 +
            leathers;
    }

    function _calcEnhancement(uint256 level, uint16 itemType)
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
