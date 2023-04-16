// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DynamicTraits.sol";

error TokenIdInUse();
error InvalidRarity();
error InvalidTraitType();
error InvalidArraySize();
error BurnNotEnabledForToken();

contract Traits is ERC1155, Ownable {
    using Strings for uint256;
    
    address private dynamicTraitsContract;
    string private baseURI;

    struct Trait {
        uint256 id;
        uint256 rarity;
        uint256 currentSupply;
    }

    // Different potential rarity types for traits
    uint256 private constant COMMON = 0;
    uint256 private constant UNCOMMON = 1;
    uint256 private constant RARE = 2;
    uint256 private constant LEGENDARY = 3;
    uint256 private constant EPIC = 4;

    // Different potential trait types
    uint256 private constant HEAD = 0;
    uint256 private constant TOP = 1;
    uint256 private constant BOTTOM = 2;

    // The weights to be applied to different rarity types
    uint256[] private rarityWeightings = [500, 200, 100, 50, 25];

    // Array containing different traits and their details
    Trait[] private headTraits;
    Trait[] private topTraits;
    Trait[] private bottomTraits;

    // A mapping of token ids to whether they can be burned;
    mapping (uint256 => bool) private isBurnEnabled;

    // Sum of all weightings for each trait type for quick reference
    uint256 private sumHeadWeightings;
    uint256 private sumTopWeightings;
    uint256 private sumBottomWeightings;
    
    // A mapping of token ids to boolean values
    mapping(uint256 => bool) public validTokenIds;

    event SetBaseURI(string indexed _baseURI);
    event TokenTransferred(uint256 _tokenId);
    event TokenBurned(uint256 _tokenId);

    constructor(string memory _baseURI) ERC1155(_baseURI) {
        baseURI = _baseURI;
        emit SetBaseURI(baseURI);
    }

    function mintBatch(uint256[] memory ids, uint256[] memory amounts)
        external
        onlyOwner
    {
        _mintBatch(owner(), ids, amounts, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override(ERC1155) {
        super.safeTransferFrom(from, to, id, amount, data);
        emit TokenTransferred(id);
        // TODO: Handle removing trait from ERC721 token ://
    }

    function initialiseTrait(uint256 id, uint256 rarity, uint256 tokenType) external onlyOwner {
        // Initialise a new trait and populate relevant mappings and arrays
        if (rarity > 4 || rarity < 0) revert InvalidRarity();
        if (tokenType > 2 || tokenType < 0) revert InvalidTraitType();
        if (validTokenIds[id] == true) revert TokenIdInUse();
        Trait memory _trait = Trait(id, rarity, 0);
        if (tokenType == HEAD) {
            headTraits.push(_trait);
            appendWeightingSum(_trait, HEAD);
        } else if (tokenType == TOP) {
            topTraits.push(_trait);
            appendWeightingSum(_trait, TOP);
        } else if (tokenType == BOTTOM) {
            bottomTraits.push(_trait);
            appendWeightingSum(_trait, BOTTOM);
        }
        validTokenIds[id] = true;
    }

    // Called by the main ERC721 contract to mint traits after tokens have been minted.
    function mintTraitSet(uint8 quantity, uint256 currentSupply, address _to) external onlyContract {
        // For quantity, mint a head, body and bottom token using VRF randomness?
        // If currentSupply of tokenId >= maxSupply -> re-roll?
        for (uint i = 0; i < quantity; i++) {
            uint[] memory _ids = new uint[](3);
            uint[] memory _amounts = new uint[](3);

            // Head token
            uint head_rand = uint(keccak256(abi.encodePacked(HEAD, currentSupply, block.timestamp))) % sumHeadWeightings;
            uint head_id = getIdForNumber(HEAD, head_rand);
            _ids[HEAD] = head_id;
            _amounts[HEAD] = 1;

            // Top token
            uint top_rand = uint(keccak256(abi.encodePacked(TOP, currentSupply, block.timestamp))) % sumTopWeightings;
            uint top_id = getIdForNumber(TOP, top_rand);
            _ids[TOP] = top_id;
            _amounts[TOP] = 1;

            // Bottom token
            uint bottom_rand = uint(keccak256(abi.encodePacked(BOTTOM, currentSupply, block.timestamp))) % sumBottomWeightings;
            uint bottom_id = getIdForNumber(BOTTOM, bottom_rand);
            _ids[BOTTOM] = bottom_id;
            _amounts[BOTTOM] = 1;

            _mintBatch(_to, _ids, _amounts, "");

            // Once mint is called, update supply and base token traits
            headTraits[head_id].currentSupply += 1;
            topTraits[top_id].currentSupply += 1;
            bottomTraits[bottom_id].currentSupply += 1;

            uint tokenId = currentSupply - (quantity - i);
            DynamicTraits _dynamicTraits = DynamicTraits(dynamicTraitsContract);
            _dynamicTraits.setTraitTokenIds(
                tx.origin, 
                tokenId, 
                uint16(head_id), 
                uint16(top_id), 
                uint16(bottom_id)
            );
        }
    }

    function getIdForNumber(uint256 _type, uint256 rand) private view returns (uint _id) {
        uint sumRarity = 0;
        if (_type == HEAD) {
            for (uint i = 0; i < headTraits.length; i++) {
                uint prevSum = sumRarity;
                sumRarity += rarityWeightings[headTraits[i].rarity];
                if (rand >= prevSum && rand < sumRarity) {
                    return headTraits[i].id;
                }
            }
        }
        if (_type == TOP) {
            for (uint i = 0; i < topTraits.length; i++) {
                uint prevSum = sumRarity;
                sumRarity += rarityWeightings[topTraits[i].rarity];
                if (rand >= prevSum && rand < sumRarity) {
                    return topTraits[i].id;
                }
            }
        }
        if (_type == BOTTOM) {
            for (uint i = 0; i < bottomTraits.length; i++) {
                uint prevSum = sumRarity;
                sumRarity += rarityWeightings[bottomTraits[i].rarity];
                if (rand >= prevSum && rand < sumRarity) {
                    return bottomTraits[i].id;
                }
            }
        }
    }

    function appendWeightingSum(Trait memory _trait, uint256 _type) private {
        if (_type < 0 || _type > 2) revert InvalidTraitType();
        if (_type == HEAD) {
            sumHeadWeightings += rarityWeightings[_trait.rarity];
        } else if (_type == TOP) {
            sumTopWeightings += rarityWeightings[_trait.rarity];
        } else if (_type == BOTTOM) {
            sumBottomWeightings += rarityWeightings[_trait.rarity];
        }
    }

    function setDynamicTraitsContractAddress(address dynamicTraitsContractAddress)
        external
        onlyOwner
    {
        dynamicTraitsContract = dynamicTraitsContractAddress;
    }

    function setRarityWeightings(uint256[] memory _rarityWeightings) external {
        if (_rarityWeightings.length != 5) revert InvalidArraySize();
        rarityWeightings = _rarityWeightings;
        // TODO: - Re-calculate sum of weightings?
    }

    function burnTraitForAddress(uint256 tokenId, address burnTokenAddress) external {
        if (!isBurnEnabled[tokenId]) revert BurnNotEnabledForToken();
        _burn(burnTokenAddress, tokenId, 1);
        emit TokenBurned(tokenId);
        // TODO: Handle removing trait from main contract
    }

    function updateIsBurnEnabledForIds(uint[] memory _ids, bool[] memory _isEnabled) public onlyOwner {
        if (_ids.length != _isEnabled.length) revert InvalidArraySize();
        for (uint i = 0; i < _ids.length; i++) {
            isBurnEnabled[_ids[i]] = _isEnabled[i];
        }
    }

    function updateBaseUri(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
        emit SetBaseURI(baseURI);
    }

    function uri(uint256 id)
        public
        view                
        override
        returns (string memory)
    {
        require(
            validTokenIds[id],
            "URI requested for invalid token"
        );
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, id.toString()))
                : baseURI;
    }

    modifier onlyContract {
        require(msg.sender == dynamicTraitsContract, "Function must be called from the original contract");
        _;
    }
}