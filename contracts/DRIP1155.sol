// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Minimalist and gas efficient standard ERC1155 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC1155.sol)
abstract contract DRIP1155 {
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
                            DRIP STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Accruer {
        uint256 balance;
        uint40 multiplier;
        uint40 accrualStartBlock;
    }

    struct Emissions {
        uint256 _currAccrued;
        uint168 emissionRatePerBlock;
        uint40 _currEmissionBlockNum;
        uint40 _currEmissionMultiple;
    }

    // wallets currently getting dripped tokens
    mapping(uint256 => mapping(address => Accruer)) public _tokenAccruers;

    mapping(uint256 => Emissions) private emissions;

    // these are all for calculating totalSupply()
    uint256 private immutable dripIdLimit = 2;

    /*//////////////////////////////////////////////////////////////
                             ERC1155 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(uint256 => uint256)) public balances;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    constructor(uint168[] memory emissionRates) {
        uint256 length = emissionRates.length;
        for (uint256 i; i < length; ) {
            emissions[i].emissionRatePerBlock = emissionRates[i];
            unchecked {
                ++i;
            }
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
                fromAccruer.accrualStartBlock = uint40(block.number);
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

        uint256 id;
        uint256 amount;

        for (uint256 i = 0; i < ids.length; ) {
            id = ids[i];
            amount = amounts[i];

            if (id >= dripIdLimit) {
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
                    fromAccruer.accrualStartBlock = uint40(block.number);
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
            Emissions memory emission = emissions[id];

            if (accruer.accrualStartBlock == 0) {
                return accruer.balance;
            }

            return
                ((block.number - accruer.accrualStartBlock) *
                    uint256(emission.emissionRatePerBlock)) *
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
        Emissions memory emission = emissions[id];
        return
            emission._currAccrued +
            (block.number - uint256(emission._currEmissionBlockNum)) *
            uint256(emission.emissionRatePerBlock) *
            uint256(emission._currEmissionMultiple);
    }

    function _startDripping(
        address account,
        uint256 id,
        uint256 multiplier
    ) internal virtual {
        require(id < dripIdLimit, "Token not drippable");
        Accruer storage accruer = _tokenAccruers[id][account];
        Emissions storage emission = emissions[id];

        // need to update the balance to start "fresh"
        // from the updated block and updated multiplier if the addr was already accruing
        if (accruer.accrualStartBlock != 0) {
            accruer.balance = balanceOf(account, id);
        }

        emission._currAccrued = totalSupply(id);
        emission._currEmissionBlockNum = uint40(block.number);
        accruer.accrualStartBlock = uint40(block.number);

        // should not overflow unless you have >2**256-1 items...
        unchecked {
            emission._currEmissionMultiple += uint40(multiplier);
            accruer.multiplier += uint40(multiplier);
        }
    }

    function _stopDripping(
        address account,
        uint256 id,
        uint256 multiplier
    ) internal virtual {
        require(id < dripIdLimit, "Token not drippable");
        Accruer storage accruer = _tokenAccruers[id][account];
        Emissions storage emission = emissions[id];

        // should I check for 0 multiplier too
        require(accruer.accrualStartBlock != 0, "user not accruing");

        accruer.balance = balanceOf(account, id);
        emission._currAccrued = totalSupply(id);
        emission._currEmissionBlockNum = uint40(block.number);

        // will revert if underflow occurs
        emission._currEmissionMultiple -= uint40(multiplier);
        accruer.multiplier -= uint40(multiplier);

        if (accruer.multiplier == 0) {
            accruer.accrualStartBlock = 0;
        } else {
            accruer.accrualStartBlock = uint40(block.number);
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
                emissions[id]._currAccrued += amount;
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
                    emissions[ids[i]]._currAccrued += amounts[i];
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
                balances[from][ids[i]] -= amounts[i];
            } else {
                Accruer storage accruer = _tokenAccruers[ids[i]][from];
                Emissions storage emission = emissions[ids[i]];

                // have to update supply before burning
                emission._currAccrued = totalSupply(ids[i]);
                emission._currEmissionBlockNum = uint40(block.number);

                accruer.balance = balanceOf(from, ids[i]) - amounts[i];

                unchecked {
                    emission._currAccrued -= amounts[i];
                }

                // update accruers block number if user was accruing
                if (accruer.accrualStartBlock != 0) {
                    accruer.accrualStartBlock = uint40(block.number);
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
            balances[from][id] -= amount;
        } else {
            Accruer storage accruer = _tokenAccruers[id][from];
            Emissions storage emission = emissions[id];

            // have to update supply before burning
            emission._currAccrued = totalSupply(id);
            emission._currEmissionBlockNum = uint40(block.number);

            accruer.balance = balanceOf(from, id) - amount;

            unchecked {
                emission._currAccrued -= amount;
            }

            // update accruers block number if user was accruing
            if (accruer.accrualStartBlock != 0) {
                accruer.accrualStartBlock = uint40(block.number);
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
