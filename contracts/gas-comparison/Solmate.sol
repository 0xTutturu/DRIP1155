//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155.sol";

contract SOL is ERC1155 {
    string _uri;

    constructor() ERC1155() {}

    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) external {
        _mint(account, id, amount, "");
    }

    function batchMint(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external {
        _batchMint(account, ids, amounts, "");
    }

    function burn(
        address account,
        uint256 id,
        uint256 amount
    ) external {
        _burn(account, id, amount);
    }

    function batchBurn(
        address account,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external {
        _batchBurn(account, ids, amounts);
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
