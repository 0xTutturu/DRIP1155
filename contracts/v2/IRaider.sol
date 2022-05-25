//SDPX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IRaider {
    struct TokenData {
        address owner;
        uint16 level;
        uint40 power;
        bool raiding;
        bool delegated;
        bool nextTokenDataSet;
    }

    function ownerOf(uint256 tokenId) external view returns (address);

    function _tokenDataOf(uint256 tokenId)
        external
        view
        returns (TokenData memory tokenData);

    function getTokenInfo(uint256 id)
        external
        view
        returns (
            address,
            uint40,
            bool,
            bool
        );

    function joinRaid(uint256 tokenId) external;

    function exitRaid(uint256 tokenId) external;
}
