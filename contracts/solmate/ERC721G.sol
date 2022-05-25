// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

error IncorrectOwner();
error NonexistentToken();
error QueryForZeroAddress();

error LockedInRaid();
error AlreadyMinted();
error MintToZeroAddress();

error CallerNotOwnerNorApproved();
error CallerNotOwner();

error ApprovalToCaller();
error ApproveToCurrentOwner();

error TransferFromIncorrectOwner();
error TransferToNonERC721ReceiverImplementer();
error TransferToZeroAddress();

error InvalidType();

/// @notice Modern, minimalist, and gas efficient ERC-721 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721G {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id
    );

    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    uint256 public totalSupply;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                         CHARACTER STORAGE
    //////////////////////////////////////////////////////////////*/

    enum Class {
        RAIDER,
        SUPPORT,
        CRAFTER,
        ALCHEMIST
    }

    struct Character {
        uint24 level;
        uint32 power;
        uint24 strength;
        uint24 stamina;
        uint24 intelligence;
        uint24 efficiency;
        uint24 luck;
        uint24 statPoints;
        Class class;
        string name;
    }

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    struct TokenData {
        address owner;
        bool raiding;
        bool delegated;
        Character character;
    }

    struct UserData {
        uint40 balance;
        uint40 minted;
        uint40 raiding;
    }

    mapping(uint256 => TokenData) internal _tokenData;
    mapping(address => UserData) internal _userData;
    mapping(uint256 => uint256[3]) internal _equippedItems;

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        TokenData memory tokenData = _tokenData[id];
        if ((tokenData.owner == address(0))) revert NonexistentToken();

        return tokenData.raiding ? address(this) : tokenData.owner;
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        if (owner == address(0)) revert QueryForZeroAddress();

        return _userData[owner].balance;
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = _tokenData[id].owner;

        if (msg.sender != owner && !isApprovedForAll[owner][msg.sender])
            revert CallerNotOwnerNorApproved();

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        TokenData memory tokenData = _tokenData[id];
        if (from != tokenData.owner) revert TransferFromIncorrectOwner();
        if (tokenData.raiding) revert LockedInRaid();
        if (to == address(0)) revert TransferToZeroAddress();

        if (
            msg.sender != from &&
            !isApprovedForAll[from][msg.sender] &&
            msg.sender != getApproved[id]
        ) revert CallerNotOwnerNorApproved();

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _userData[from].balance--;

            _userData[to].balance++;
        }

        _tokenData[id].owner = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            ERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                from,
                id,
                ""
            ) !=
            ERC721TokenReceiver.onERC721Received.selector
        ) revert TransferToNonERC721ReceiverImplementer();
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            ERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                from,
                id,
                data
            ) !=
            ERC721TokenReceiver.onERC721Received.selector
        ) revert TransferToNonERC721ReceiverImplementer();
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
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL CHARACTER LOGIC
    //////////////////////////////////////////////////////////////*/

    function useExpGems(uint256 id, uint16 levels) external virtual;

    function equipItems(uint256 itemId, uint256 equipmentId) external virtual;

    function drinkPotion(uint256 id, uint256 itemId) external virtual;

    /*//////////////////////////////////////////////////////////////
                              INTERNAL CHARACTER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _getChar(Class class, string memory _name)
        internal
        pure
        returns (Character memory)
    {
        uint256 classNum = uint256(class);
        if (classNum > 1) {
            if (classNum == 2) {
                // crafter
                return
                    Character(
                        1,
                        2,
                        2, // str
                        7, // stm
                        4, // int
                        5, // eff
                        5, // luck
                        0,
                        class,
                        _name
                    );
            } else {
                // set stats to alchemist
                return
                    Character(
                        1,
                        1,
                        2, // str
                        4, // stm
                        10, // int
                        5, // eff
                        3, // luck
                        0,
                        class,
                        _name
                    );
            }
        } else {
            if (classNum == 0) {
                // set stats to Raider
                return
                    Character(
                        1,
                        10,
                        5, // str
                        5, // stm
                        1, // int
                        2, // eff
                        2, // luck
                        0,
                        class,
                        _name
                    );
            } else {
                // set stats to Support
                return
                    Character(
                        1,
                        5,
                        2, // str
                        3, // stm
                        7, // int
                        4, // eff
                        4, // luck
                        0,
                        class,
                        _name
                    );
            }
        }
    }

    function _levelUpInfo(uint256 level)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 exp = (4 * (level**3) + 90 * (level**2) + 2 * 4) / 100;
        uint256 power = (4 * (level**3) + 80 * (level**2) + 20 * 4) / 100;
        return (exp, power);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(
        address to,
        uint256 id,
        Class class,
        string memory _name
    ) internal virtual {
        if (to == address(0)) revert MintToZeroAddress();
        if (_tokenData[id].owner != address(0)) revert AlreadyMinted();

        Character memory char = _getChar(class, _name);

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _userData[to].balance++;
            _userData[to].minted++;
            totalSupply++;
        }

        _tokenData[id] = TokenData(to, false, false, char);

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _tokenData[id].owner;

        if (owner == address(0)) revert NonexistentToken();

        // Ownership check above ensures no underflow.
        unchecked {
            _userData[owner].balance--;
        }

        delete _tokenData[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _safeMint(
        address to,
        uint256 id,
        Class class,
        string memory _name
    ) internal virtual {
        _mint(to, id, class, _name);

        if (
            to.code.length != 0 &&
            ERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                address(0),
                id,
                ""
            ) !=
            ERC721TokenReceiver.onERC721Received.selector
        ) revert TransferToNonERC721ReceiverImplementer();
    }

    function _safeMint(
        address to,
        uint256 id,
        Class class,
        string memory _name,
        bytes memory data
    ) internal virtual {
        _mint(to, id, class, _name);

        if (
            to.code.length != 0 &&
            ERC721TokenReceiver(to).onERC721Received(
                msg.sender,
                address(0),
                id,
                data
            ) !=
            ERC721TokenReceiver.onERC721Received.selector
        ) revert TransferToNonERC721ReceiverImplementer();
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}
