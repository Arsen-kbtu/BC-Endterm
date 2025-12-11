// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract CertificateNFT is ERC721Enumerable, Ownable {
    using Strings for uint256;

    uint256 public maxSupply = 1000;
    uint256 public cost = 0.001 ether;

    // Base URI for metadata stored on IPFS
    string public baseURI = "ipfs://QmYourFolderCID/";

    // Mapping to track if an address has already claimed a certificate
    mapping(address => bool) public hasClaimed;

    event CertificateMinted(address indexed recipient, uint256 tokenId);

    // Pass initial owner to Ownable constructor
    constructor() ERC721("GraduateCertificate", "GCERT") Ownable(msg.sender) {}

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721: invalid token ID");

        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0
            ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), ".json"))
            : "";
    }

    function changeBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function safeMint(address _to) public payable {
        uint256 _currentSupply = totalSupply();
        require(_currentSupply < maxSupply, "Max supply reached");
        require(msg.value == cost, "Please add valid amount of ETH (0.001)");
        require(!hasClaimed[_to], "Address has already claimed a certificate");

        hasClaimed[_to] = true;
        _safeMint(_to, _currentSupply);
        
        emit CertificateMinted(_to, _currentSupply);
    }

    // Owner can mint without restrictions
    function ownerMint(address _to) public onlyOwner {
        uint256 _currentSupply = totalSupply();
        require(_currentSupply < maxSupply, "Max supply reached");
        
        _safeMint(_to, _currentSupply);
        emit CertificateMinted(_to, _currentSupply);
    }

    function mintBatch(address[] memory _recipients) public onlyOwner {
        for (uint256 i = 0; i < _recipients.length; i++) {
            uint256 _currentSupply = totalSupply();
            require(_currentSupply < maxSupply, "Max supply reached");
            
            _safeMint(_recipients[i], _currentSupply);
            emit CertificateMinted(_recipients[i], _currentSupply);
        }
    }

    function withdraw() public onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    function getAllTokensOfOwner(address _owner) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        
        return tokenIds;
    }
}
