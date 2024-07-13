// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Varonve is ERC721URIStorage, Ownable, ReentrancyGuard{

    using Strings for uint256;

    constructor() ERC721("Varonve", "VRV") Ownable(msg.sender)
    {
    }

    bytes32 public root; 
    bytes4 private constant ERC2981_INTERFACE_ID = bytes4(0x2a55205a);

    uint constant maxSupply = 5555;
    uint constant publicMintLimit = 5;
    uint constant whitelistMintLimit = 2;
    uint constant publicPrice = 8000000000000000 wei;  
    uint constant whitelistPrice = 6000000000000000 wei;

    uint private royalty = 500;
    uint private denominator = 10000;
    uint private currentMint = 1;
    uint private whitelistStartTime = 1719144000;
    uint private publicStartTime = 	1719154800;
    
    string revealedURI;
    string unrevealedURI;

    bool public isPublicMintActive=false;
    bool public isWhitelistMintActive=false;
    bool public immediateStop=false;
    bool public revealStatus=false;

    address royaltyTaker = 0x4FbFeD565e9316BB0CC628Aa7E87E900C29eb217;
    address withdrawAddress = 0xc654d125E34F246297f6c8Bf73822750166d9939;

    mapping (address => uint) publicMinted;
    mapping (address => uint) whitelistMinted;  



    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
    _;
  }


    // MINT SETTINGS

    function togglePublicMint() public onlyOwner{
        isPublicMintActive = !isPublicMintActive;
    }  

    function toggleWhitelistMint() public onlyOwner{
        isWhitelistMintActive = !isWhitelistMintActive;
    }

    function toggleImmediateStop() public onlyOwner{
        immediateStop = !immediateStop;
    }

    function setRoot(bytes32 _merkleRoot) public onlyOwner{
        root = _merkleRoot;
    }

    // URI MODIFICATIONS AND REVEAL

    function toggleReveal() public onlyOwner{
        revealStatus = !revealStatus;
    }


    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory baseURI = _baseURI();

        if((revealStatus==false)){
            return baseURI;
        }else{
            return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString(), ".json") : "";
        }
    }

    function _baseURI() internal view override  returns (string memory) {
        if(revealStatus){
            return revealedURI;
        }else{
            return unrevealedURI;
        }
    }

    function setBaseURI(string memory _newURI) public onlyOwner{
        revealedURI = _newURI;
    }

    function setUnrevealedURI(string memory _newUnrevealedURI) public onlyOwner{
        unrevealedURI = _newUnrevealedURI;
    }


    // INFO

    function totalSupply() public view returns (uint) {
        return currentMint -1;
    }


    // MINT FUNCTIONS

    function publicMint(uint _mintAmount) public payable callerIsUser{
        require((block.timestamp >= publicStartTime) || isPublicMintActive, "Public minting is not active");
        require(immediateStop==false, "Mint is stopped.");
        require((publicMinted[msg.sender] + _mintAmount) <= publicMintLimit, "You have reached the mint limit");
        require(_mintAmount + currentMint <= maxSupply, "Amount exceeds max supply");
        require(msg.value >= _mintAmount*publicPrice, "Balance is not enough");
        for(uint i=0; i<_mintAmount; i++){
            _safeMint(msg.sender, currentMint+i); 
            }
        publicMinted[msg.sender] += _mintAmount;
        currentMint += _mintAmount;
    }


    function WhitelistMint(uint _mintAmount, bytes32[] calldata _merkleProof) public payable callerIsUser{
        require((block.timestamp >= whitelistStartTime) || isWhitelistMintActive, "Whitelist minting is not active");
        require(immediateStop==false, "Mint is stopped");
        require(_mintAmount + currentMint <= maxSupply, "Amount exceeds max supply");
        require(whitelistMinted[msg.sender] + _mintAmount <= whitelistMintLimit, "You have reached the mint limit for presale");
        require(msg.value >= _mintAmount*whitelistPrice, "Balance is not enough");
        require(isWhitelisted(_merkleProof,getLeaf(msg.sender)), "You are not whitelisted");

        for(uint i=0; i<_mintAmount; i++){
            _safeMint(msg.sender, currentMint+i);
            }
        whitelistMinted[msg.sender] += _mintAmount;     
        currentMint += _mintAmount;
    }


    function teamMint(uint _mintAmount) public onlyOwner{
        require(_mintAmount + currentMint <= maxSupply, "Amount exceeds max supply");
        for(uint i=0; i<_mintAmount; i++){
            _safeMint(msg.sender, currentMint+i); 
            }   
        currentMint += _mintAmount;
    }

    // ROYALTY

    function setRoyaltyAmount(uint _royaltyAmount) public onlyOwner{
        require(_royaltyAmount<= denominator, "Royalty cannot be bigger than the price");
        royalty = _royaltyAmount;
    }

    function setRoyaltyTaker(address _royaltyTaker) public onlyOwner{
        royaltyTaker = _royaltyTaker;
    }

    function royaltyInfo(uint256 _tokenId,uint256 _salePrice
    ) external view returns (
        address receiver,
        uint256 royaltyAmount
    ){
        return(royaltyTaker, (_salePrice * royalty) / denominator);
    }


    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721URIStorage) returns (bool)
    {
        return interfaceId == ERC2981_INTERFACE_ID || super.supportsInterface(interfaceId);
    }

    // MERKLE TREE

    function getLeaf(address _address)internal pure returns (bytes32)
    {
        return keccak256(bytes.concat(keccak256(abi.encode(_address))));
    }

    function isWhitelisted(bytes32[] memory _merkleProof, bytes32 _leaf) public view returns(bool){
        return MerkleProof.verify(_merkleProof, root, _leaf);
    }


    // WITHDRAWAL

    function withdrawFunds() public onlyOwner nonReentrant {
        address _address = withdrawAddress;
        (bool success, ) = _address.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
  }



}