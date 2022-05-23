// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Minimalist and gas efficient standard ERC1155 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract ERC1155Drip {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    event URI(string value, uint256 indexed id);

    /*//////////////////////////////////////////////////////////////
                            EQUIPMENT STORAGE
    //////////////////////////////////////////////////////////////*/

    /* Item Types:
     * 0 - Gold
     * 1 - Exp Gems
     * 2 - Ore
     * 3 - Skins
     * 4 - Ingots
     * 5 - Salts
     * 6 - Runes
     * from 7 on - Potions, Enchantments, Recipes, Weapons, Armor, Accessories
     */

    struct Equipment {
        uint40 level; // Level of the item, can also be used as min char level
        uint24 strength; // Increases power
        uint24 stamina; // Increases energy
        uint16 intelligence; // Increases bonuses for supports, increases success rate for potion making
        uint24 efficiency; // Decreases energy usage by a %, decrease material cost for crafting
        uint24 luck; // Increases reward distribution, Increases success rate for crafting
        uint8 boostType; // Either a pure stat boost or a % boost
        uint16 itemType; // Defines both fungible and non fungible token types
        bool equipped;
    }

    // Mapping from token ID to equipment struct
    mapping(uint256 => Equipment) public idToEquipment;

    /*//////////////////////////////////////////////////////////////
                            DRIP STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Accruer {
        uint256 multiplier;
        uint256 balance;
        uint256 accrualStartBlock;
    }

    // immutable token emission rate per block
    mapping(uint256 => uint256) public tokenEmissionRatePerBlock;

    // wallets currently getting dripped tokens
    mapping(uint256 => mapping(address => Accruer)) private _tokenAccruers;

    // these are all for calculating totalSupply()
    mapping(uint256 => uint256) private _tokenCurrAccrued;
    mapping(uint256 => uint256) private _tokenCurrEmissionBlockNum;
    mapping(uint256 => uint256) private _tokenCurrEmissionMultiple;
    uint256 private immutable dripIdLimit = 2;

    /*//////////////////////////////////////////////////////////////
                             ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(uint256 => uint256)) public balances;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    constructor(uint256[] memory emissionRates) {
        for (uint256 i; i < emissionRates.length; i++) {
            tokenEmissionRatePerBlock[i] = emissionRates[i];
        }
    }

    /*//////////////////////////////////////////////////////////////
                             METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    function uri(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                              ERC1155 LOGIC
    //////////////////////////////////////////////////////////////*/

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) public virtual {
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender],
            "NOT_AUTHORIZED"
        );

        if (id >= dripIdLimit) {
            require(
                !idToEquipment[id].equipped,
                "Can't transfer equipped item"
            );

            balances[from][id] -= amount;
            balances[to][id] += amount;
        } else {
            Accruer storage fromAccruer = _tokenAccruers[id][from];
            Accruer storage toAccruer = _tokenAccruers[id][to];

            // reverts if underflow
            fromAccruer.balance = balanceOf(from, id) - amount;

            unchecked {
                toAccruer.balance += amount;
            }

            if (fromAccruer.accrualStartBlock != 0) {
                fromAccruer.accrualStartBlock = block.number;
            }
        }

        emit TransferSingle(msg.sender, from, to, id, amount);

        require(
            to.code.length == 0
                ? to != address(0)
                : ERC1155TokenReceiver(to).onERC1155Received(
                    msg.sender,
                    from,
                    id,
                    amount,
                    data
                ) == ERC1155TokenReceiver.onERC1155Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) public virtual {
        require(ids.length == amounts.length, "LENGTH_MISMATCH");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender],
            "NOT_AUTHORIZED"
        );

        // Storing these outside the loop saves ~15 gas per iteration.
        uint256 id;
        uint256 amount;

        for (uint256 i = 0; i < ids.length; ) {
            id = ids[i];
            amount = amounts[i];

            if (id >= dripIdLimit) {
                require(
                    !idToEquipment[id].equipped,
                    "Can't transfer equipped item"
                );

                balances[from][id] -= amount;
                balances[to][id] += amount;
            } else {
                Accruer storage fromAccruer = _tokenAccruers[id][from];
                Accruer storage toAccruer = _tokenAccruers[id][to];

                // reverts if underflow
                fromAccruer.balance = balanceOf(from, id) - amount;

                unchecked {
                    toAccruer.balance += amount;
                }

                if (fromAccruer.accrualStartBlock != 0) {
                    fromAccruer.accrualStartBlock = block.number;
                }
            }

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, to, ids, amounts);

        require(
            to.code.length == 0
                ? to != address(0)
                : ERC1155TokenReceiver(to).onERC1155BatchReceived(
                    msg.sender,
                    from,
                    ids,
                    amounts,
                    data
                ) == ERC1155TokenReceiver.onERC1155BatchReceived.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id)
        public
        view
        virtual
        returns (uint256)
    {
        require(
            account != address(0),
            "ERC1155: balance query for the zero address"
        );

        if (id < dripIdLimit) {
            Accruer memory accruer = _tokenAccruers[id][account];

            if (accruer.accrualStartBlock == 0) {
                return accruer.balance;
            }

            return
                ((block.number - accruer.accrualStartBlock) *
                    tokenEmissionRatePerBlock[id]) *
                accruer.multiplier +
                accruer.balance;
        }

        return balances[account][id];
    }

    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        public
        view
        virtual
        returns (uint256[] memory batchBalances)
    {
        require(owners.length == ids.length, "LENGTH_MISMATCH");

        batchBalances = new uint256[](owners.length);

        // Unchecked because the only math done is incrementing
        // the array index counter which cannot possibly overflow.
        unchecked {
            for (uint256 i = 0; i < owners.length; ++i) {
                batchBalances[i] = balanceOf(owners[i], ids[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             DRIP LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalSupply(uint256 id) public view returns (uint256) {
        return
            _tokenCurrAccrued[id] +
            (block.number - _tokenCurrEmissionBlockNum[id]) *
            tokenEmissionRatePerBlock[id] *
            _tokenCurrEmissionMultiple[id];
    }

    function _startDripping(
        address account,
        uint256 id,
        uint256 multiplier
    ) internal virtual {
        require(id < dripIdLimit, "Token not drippable");
        Accruer storage accruer = _tokenAccruers[id][account];

        _tokenCurrAccrued[id] = totalSupply(id);
        _tokenCurrEmissionBlockNum[id] = block.number;
        accruer.accrualStartBlock = block.number;

        // should not overflow unless you have >2**256-1 items...
        unchecked {
            _tokenCurrEmissionMultiple[id] += multiplier;
            accruer.multiplier += multiplier;
        }

        // need to update the balance to start "fresh"
        // from the updated block and updated multiplier if the addr was already accruing
        if (accruer.accrualStartBlock != 0) {
            accruer.balance = balanceOf(account, id);
        }
    }

    function _stopDripping(
        address account,
        uint256 id,
        uint256 multiplier
    ) internal virtual {
        require(id < dripIdLimit, "Token not drippable");
        Accruer storage accruer = _tokenAccruers[id][account];

        // should I check for 0 multiplier too
        require(accruer.accrualStartBlock != 0, "user not accruing");

        accruer.balance = balanceOf(account, id);
        _tokenCurrAccrued[id] = totalSupply(id);
        _tokenCurrEmissionBlockNum[id] = block.number;

        // will revert if underflow occurs
        _tokenCurrEmissionMultiple[id] -= multiplier;
        accruer.multiplier -= multiplier;

        if (accruer.multiplier == 0) {
            accruer.accrualStartBlock = 0;
        } else {
            accruer.accrualStartBlock = block.number;
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xd9b67a26 || // ERC165 Interface ID for ERC1155
            interfaceId == 0x0e89341c; // ERC165 Interface ID for ERC1155MetadataURI
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual {
        if (id >= dripIdLimit) {
            balances[to][id] += amount;
        } else {
            Accruer storage accruer = _tokenAccruers[id][to];
            unchecked {
                _tokenCurrAccrued[id] += amount;
                accruer.balance += amount;
            }
        }

        emit TransferSingle(msg.sender, address(0), to, id, amount);

        require(
            to.code.length == 0
                ? to != address(0)
                : ERC1155TokenReceiver(to).onERC1155Received(
                    msg.sender,
                    address(0),
                    id,
                    amount,
                    data
                ) == ERC1155TokenReceiver.onERC1155Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function _batchMint(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual {
        uint256 idsLength = ids.length; // Saves MLOADs.

        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < idsLength; ) {
            if (ids[i] >= dripIdLimit) {
                balances[to][ids[i]] += amounts[i];
            } else {
                Accruer storage accruer = _tokenAccruers[ids[i]][to];
                unchecked {
                    _tokenCurrAccrued[ids[i]] += amounts[i];
                    accruer.balance += amounts[i];
                }
            }

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, address(0), to, ids, amounts);

        require(
            to.code.length == 0
                ? to != address(0)
                : ERC1155TokenReceiver(to).onERC1155BatchReceived(
                    msg.sender,
                    address(0),
                    ids,
                    amounts,
                    data
                ) == ERC1155TokenReceiver.onERC1155BatchReceived.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function _batchBurn(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual {
        uint256 idsLength = ids.length; // Saves MLOADs.

        require(idsLength == amounts.length, "LENGTH_MISMATCH");

        for (uint256 i = 0; i < idsLength; ) {
            if (ids[i] >= dripIdLimit) {
                Equipment memory equipment = idToEquipment[ids[i]];
                require(!equipment.equipped, "Can't transfer equipped item");
                balances[from][ids[i]] -= amounts[i];
            } else {
                Accruer storage accruer = _tokenAccruers[ids[i]][from];

                // have to update supply before burning
                _tokenCurrAccrued[ids[i]] = totalSupply(ids[i]);
                _tokenCurrEmissionBlockNum[ids[i]] = block.number;

                accruer.balance = balanceOf(from, ids[i]) - amounts[i];

                // Cannot underflow because amount can
                // never be greater than the totalSupply()
                unchecked {
                    _tokenCurrAccrued[ids[i]] -= amounts[i];
                }

                // update accruers block number if user was accruing
                if (accruer.accrualStartBlock != 0) {
                    accruer.accrualStartBlock = block.number;
                }
            }

            // An array can't have a total length
            // larger than the max uint256 value.
            unchecked {
                ++i;
            }
        }

        emit TransferBatch(msg.sender, from, address(0), ids, amounts);
    }

    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal virtual {
        if (id >= dripIdLimit) {
            Equipment memory equipment = idToEquipment[id];
            require(!equipment.equipped, "Can't transfer equipped item");
            balances[from][id] -= amount;
        } else {
            Accruer storage accruer = _tokenAccruers[id][from];

            // have to update supply before burning
            _tokenCurrAccrued[id] = totalSupply(id);
            _tokenCurrEmissionBlockNum[id] = block.number;

            accruer.balance = balanceOf(from, id) - amount;

            // Cannot underflow because amount can
            // never be greater than the totalSupply()
            unchecked {
                _tokenCurrAccrued[id] -= amount;
            }

            // update accruers block number if user was accruing
            if (accruer.accrualStartBlock != 0) {
                accruer.accrualStartBlock = block.number;
            }
        }

        emit TransferSingle(msg.sender, from, address(0), id, amount);
    }
}

/// @notice A generic interface for a contract which properly accepts ERC1155 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract ERC1155TokenReceiver {
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}
