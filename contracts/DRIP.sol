//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155Drip.sol";

contract DRIP is ERC1155Drip {
    string _uri;

    constructor(uint256 limit, uint256[] memory emissionRates)
        ERC1155Drip(emissionRates)
    {}

    function startDripping(
        address account,
        uint256 id,
        uint256 multiplier
    ) external {
        _startDripping(account, id, multiplier);
    }

    function stopDripping(
        address account,
        uint256 id,
        uint256 multiplier
    ) external {
        _stopDripping(account, id, multiplier);
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) external {
        _mint(account, id, amount, "");
    }

    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) external {
        _burn(account, id, amount);
    }

    function uri(uint256 id)
        public
        view
        virtual
        override
        returns (string memory)
    {
        return _uri;
    }
}
