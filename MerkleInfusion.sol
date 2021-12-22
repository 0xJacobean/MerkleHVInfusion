// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IMerkleDistributor.sol";
import "./HyperVIBES.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// This is an example ERC721 that will "infuse on mint"
contract StockingStuffer is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // the minting contract needs to knowaz
    // - the address of the HyperVIBES protocol
    // - the correct Realm ID
    HyperVIBES public hyperVIBES;
    uint256 public realmId;
    string private _baseURIextended;
    bytes32 public immutable merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, uint256 amount);

    constructor(bytes32 merkleRoot_) ERC721("StockingStuffer", "STUFFED") { 
        merkleRoot = merkleRoot_;
    }

    // MERKLE TREE

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, uint256 amount, address account, bytes32[] calldata merkleProof) external {
        require(!isClaimed(index), "MerkleDistributor: Drop already claimed.");
        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof.");

        // Mark it claimed and send the token.
        _setClaimed(index);
        mint(account);

        emit Claimed(index, account, amount);
    }

    // Set the pointer to the HyperVIBES protocol
    // NOTE: this function should be secure (only a privledged admin should be
    // allowed to use this)
    function setHyperVIBES(IERC20 token, uint256 realmId_, HyperVIBES hyperVIBES_) external {
      realmId = realmId_;
      hyperVIBES = hyperVIBES_;

      // we need to approve hypervibes to spend any tokens owned by this
      // contract, we'll store the tokens required for infusing in the ERC-721
      token.approve(address(hyperVIBES_), 2 ** 256 - 1);

      // dont need to store token address since its only needed to call approve initially
    }

    function mint(address _account) internal {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();

        // mint however you are normally
        _mint(_account, newItemId);

        // then infuse with hyper vibes -- the tokens will be transfered from
        // the ERC-721 address into the HyperVIBES protocol
        hyperVIBES.infuse(InfuseInput({
          // must be set to configured realm
          realmId: realmId,

          // the NFT
          collection: this,
          tokenId: newItemId,

          // if you dont want to attribute the infusion the ERC721, the address
          // that this is set to must call allowInfusionProxy with the ERC721
          // address
          infuser: address(this),

          // based on desired behavior and realm config. using ether keyword
          // here is ofc only correct if the ERC-20 being used has decimals = 18
          amount: 100000000000000000000,
          // daily rate is set on the realm config and cannot be modified

          // optional, can just be an empty string
          comment: "nice!"
        }));
    }

    function burn(uint256 _tokenId) external {
        _burn(_tokenId);
    }

    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

        // withdraw funds from the contract
    function withdraw(IERC20 token_) external onlyOwner() {
        token_.transfer(msg.sender, token_.balanceOf(address(this)));
    }

}
