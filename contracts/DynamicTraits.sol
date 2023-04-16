// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC721A, IERC721A} from "erc721a/contracts/ERC721A.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OperatorFilterer} from "closedsea/src/OperatorFilterer.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ERC721ABurnable} from "erc721a/contracts/extensions/ERC721ABurnable.sol";
import {ERC721AQueryable} from "erc721a/contracts/extensions/ERC721AQueryable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "./Traits.sol";

error MintingPaused();
error MaxSupplyReached();
error WithdrawalFailed();
error WrongEtherAmount();
error InvalidMintAddress();
error ArrayLengthMismatch();
error MaxPerTransactionReached();
error MintFromContractNotAllowed();
error ZeroBalanceForTraitToken();
error InvalidTraitTokenId();
error NotOwnerOfToken();

contract DynamicTraits is
    Ownable,
    ERC721A,
    ERC2981,
    ERC721ABurnable,
    ERC721AQueryable,
    OperatorFilterer
{
    uint256 private constant MAX_SUPPLY = 9999;
    uint256 private constant MAX_PER_TRANSACTION = 6;
    uint256 private constant ADDITIONAL_MINT_PRICE = 0.009 ether;

    bool public mintPaused = true;
    bool public operatorFilteringEnabled = true;

    string tokenBaseUri = "";

    // Traits features and logic (try move into own contract)
    struct TokenTraits {
        uint16 head;
        uint16 top;
        uint16 bottom;
    }

    // Mapping a token id to the associated traits
    mapping(uint256 => TokenTraits) traits;

    // Arrays containing the ERC1155 token ids for each given trait
    mapping(uint => bool) headTokenIds;
    mapping(uint => bool) topTokenIds;
    mapping(uint => bool) bottomTokenIds;

    address private traitsAddress;

    event UpdatedTraits(
        uint256 _tokenId,
        uint _head,
        uint _top,
        uint _bottom
    );

    event TransferredToken(uint256 _tokenId);

    constructor(address deployer) ERC721A("Dynamic Traits", "DT") {
        _mint(deployer, 1);
        _transferOwnership(deployer);
        _registerForOperatorFiltering();
        _setDefaultRoyalty(deployer, 750);
    }

    function mint(uint8 quantity) external payable {
        if (mintPaused) revert MintingPaused();
        if (_totalMinted() + quantity > MAX_SUPPLY) revert MaxSupplyReached();
        if (quantity > MAX_PER_TRANSACTION) revert MaxPerTransactionReached();
        if (msg.sender != tx.origin) revert MintFromContractNotAllowed();

        uint8 payForCount = quantity;
        uint64 freeMintCount = _getAux(msg.sender);

        if (freeMintCount < 1) {
        payForCount = quantity - 1;
        _setAux(msg.sender, 1);
        }

        if (payForCount > 0) {
        if (msg.value < payForCount * ADDITIONAL_MINT_PRICE)
            revert WrongEtherAmount();
        }
        Traits traitsContract = Traits(traitsAddress);
        _mint(msg.sender, quantity);
        traitsContract.mintTraitSet(quantity, totalSupply(), msg.sender);
    }

    function batchTransferFrom(
        address[] calldata recipients,
        uint256[] calldata tokenIds
    ) external {
        uint256 tokenIdsLength = tokenIds.length;

        if (tokenIdsLength != recipients.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < tokenIdsLength; ) {
        transferFrom(msg.sender, recipients[i], tokenIds[i]);

        unchecked {
            ++i;
        }
        }
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _baseURI() internal view override returns (string memory) {
        return tokenBaseUri;
    }

    function freeMintedCount(address owner) external view returns (uint64) {
        return _getAux(owner);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721A, IERC721A, ERC2981) returns (bool) {
        return
        ERC721A.supportsInterface(interfaceId) ||
        ERC2981.supportsInterface(interfaceId);
    }

    function _operatorFilteringEnabled() internal view override returns (bool) {
        return operatorFilteringEnabled;
    }

    function _isPriorityOperator(
        address operator
    ) internal pure override returns (bool) {
        return operator == address(0x1E0049783F008A0085193E00003D00cd54003c71);
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override(ERC721A, IERC721A) onlyAllowedOperatorApproval(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    )
        public
        payable
        override(ERC721A, IERC721A)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
        emit TransferredToken(tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
        emit TransferredToken(tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(ERC721A, IERC721A) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function setTraitTokenIds(
        address operator,
        uint256 tokenId,
        uint16 headTokenId,
        uint16 topTokenId,
        uint16 bottomTokenId
    ) public onlyAllowedOperator(operator) {
        if (ownerOf(tokenId) != msg.sender) revert NotOwnerOfToken(); // ensure this works with contract call
        if (
            headTokenIds[headTokenId] == false || 
            topTokenIds[topTokenId] == false || 
            bottomTokenIds[bottomTokenId] == false
        ) revert InvalidTraitTokenId();
        Traits _traitsContract = Traits(traitsAddress);
        if (
            _traitsContract.balanceOf(operator, headTokenId) == 0 || 
            _traitsContract.balanceOf(operator, topTokenId) == 0|| 
            _traitsContract.balanceOf(operator, bottomTokenId) == 0
        ) revert ZeroBalanceForTraitToken();
        TokenTraits memory _traits = TokenTraits(headTokenId, topTokenId, bottomTokenId);
        traits[tokenId] = _traits;
        emit UpdatedTraits(tokenId, headTokenId, topTokenId, bottomTokenId);
    }

    function getTraitTokenId(uint256 tokenId) public view returns (uint16 headTokenId, uint16 topTokenId, uint16 bottomTokenId) {
        TokenTraits memory _traits = traits[tokenId];
        return (_traits.head, _traits.top, _traits.bottom);
    }

    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setOperatorFilteringEnabled(bool value) public onlyOwner {
        operatorFilteringEnabled = value;
    }

    function setTraitsContract(address _traitsAddress) external onlyOwner {
        traitsAddress = _traitsAddress;
    }

    function addHeadTokenId(uint id) external onlyOwner {
        headTokenIds[id] = true;
    }

    function addTopTokenId(uint id) external onlyOwner {
        topTokenIds[id] = true;
    }

    function addBottomTokenId(uint id) external onlyOwner {
        bottomTokenIds[id] = true;
    }

    function setBaseURI(string calldata newBaseUri) external onlyOwner {
        tokenBaseUri = newBaseUri;
    }

    function flipSale() external onlyOwner {
        mintPaused = !mintPaused;
    }

    function collectReserves(uint16 quantity) external onlyOwner {
        if (_totalMinted() + quantity > MAX_SUPPLY) revert MaxSupplyReached();

        _mint(msg.sender, quantity);
    }

    function withdraw() public onlyOwner {
        (bool success, ) = payable(owner()).call{value: address(this).balance}("");

        if (!success) {
        revert WithdrawalFailed();
        }
    }
}