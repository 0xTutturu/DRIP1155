//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155M.sol";

contract DRIPM is ERC1155M {
    string _uri;

    constructor(uint256 limit, uint256[] memory emissionRates)
        ERC1155M(emissionRates)
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

    function getAccruer(address account, uint256 id)
        public
        view
        returns (Accruer memory)
    {
        return _tokenAccruers[id][account];
    }

    function getStartBlock(address account, uint256 id)
        public
        view
        returns (uint256)
    {
        return _tokenAccruers[id][account].accrualStartBlock;
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
