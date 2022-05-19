//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface ILoot {
    struct Equipment {
        uint40 level;
        uint40 power;
        uint8 itemType;
        bool equipped;
    }

    function burnGems(address user, uint256 amount) external;

    function mintReward(
        address user,
        uint256 gold,
        uint256 gems
    ) external;

    function balanceOf(address account, uint256 id)
        external
        view
        returns (uint256);

    function equippedOn(uint256) external view returns (uint256);

    function idToEquipment(uint256) external view returns (Equipment memory);

    function equipItem(
        uint256[3] memory equippedItems,
        uint256 itemId,
        address user
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        );
}
