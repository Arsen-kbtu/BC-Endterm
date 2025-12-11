// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title DocumentSignature
 * @dev Smart contract for document signature with whitelist and NFT minting
 * Features:
 * - Whitelist management using Merkle Tree
 * - Document signing functionality
 * - ERC721 token minting upon signature
 */
contract DocumentSignature is ERC721, Ownable {
    // Document structure
    struct Document {
        string documentHash;
        uint256 createdAt;
        uint256 signaturesCount;
        mapping(address => bool) hasSigned;
        address[] signers;
    }

    // State variables
    mapping(uint256 => Document) public documents;
    uint256 public documentCount;
    uint256 private _tokenIdCounter;
    
    // Merkle root for whitelist verification
    bytes32 public merkleRoot;
    
    // Mapping to track if address has been whitelisted (for simple whitelist mode)
    mapping(address => bool) public isWhitelisted;
    bool public useMerkleTree;

    // Events
    event DocumentCreated(uint256 indexed documentId, string documentHash);
    event DocumentSigned(uint256 indexed documentId, address indexed signer, uint256 tokenId);
    event WhitelistUpdated(address indexed account, bool status);
    event MerkleRootUpdated(bytes32 newMerkleRoot);

    constructor() ERC721("DocumentSignatureNFT", "DSNFT") Ownable(msg.sender) {
        useMerkleTree = false;
    }

    /**
     * @dev Add address to whitelist (simple mode)
     */
    function addToWhitelist(address account) external onlyOwner {
        require(!useMerkleTree, "Using Merkle Tree mode");
        require(account != address(0), "Invalid address");
        isWhitelisted[account] = true;
        emit WhitelistUpdated(account, true);
    }

    /**
     * @dev Add multiple addresses to whitelist (simple mode)
     */
    function addMultipleToWhitelist(address[] calldata accounts) external onlyOwner {
        require(!useMerkleTree, "Using Merkle Tree mode");
        for (uint256 i = 0; i < accounts.length; i++) {
            require(accounts[i] != address(0), "Invalid address");
            isWhitelisted[accounts[i]] = true;
            emit WhitelistUpdated(accounts[i], true);
        }
    }

    /**
     * @dev Remove address from whitelist (simple mode)
     */
    function removeFromWhitelist(address account) external onlyOwner {
        require(!useMerkleTree, "Using Merkle Tree mode");
        isWhitelisted[account] = false;
        emit WhitelistUpdated(account, false);
    }

    /**
     * @dev Set Merkle root for optimized whitelist
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        useMerkleTree = true;
        emit MerkleRootUpdated(_merkleRoot);
    }

    /**
     * @dev Switch between Merkle Tree and simple whitelist mode
     */
    function setUseMerkleTree(bool _useMerkleTree) external onlyOwner {
        useMerkleTree = _useMerkleTree;
    }

    /**
     * @dev Verify if address is whitelisted using Merkle proof
     */
    function verifyWhitelist(address account, bytes32[] calldata merkleProof) 
        public 
        view 
        returns (bool) 
    {
        if (!useMerkleTree) {
            return isWhitelisted[account];
        }
        
        bytes32 leaf = keccak256(abi.encodePacked(account));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    /**
     * @dev Create a new document
     */
    function createDocument(string memory documentHash) external onlyOwner returns (uint256) {
        uint256 documentId = documentCount++;
        Document storage doc = documents[documentId];
        doc.documentHash = documentHash;
        doc.createdAt = block.timestamp;
        doc.signaturesCount = 0;
        
        emit DocumentCreated(documentId, documentHash);
        return documentId;
    }

    /**
     * @dev Sign a document (simple whitelist mode)
     */
    function sign(uint256 documentId) external {
        require(!useMerkleTree, "Use signWithProof for Merkle Tree mode");
        require(isWhitelisted[msg.sender], "Not whitelisted");
        _signDocument(documentId);
    }

    /**
     * @dev Sign a document with Merkle proof (Merkle Tree mode)
     */
    function signWithProof(uint256 documentId, bytes32[] calldata merkleProof) external {
        require(useMerkleTree, "Use sign for simple whitelist mode");
        require(verifyWhitelist(msg.sender, merkleProof), "Invalid Merkle proof");
        _signDocument(documentId);
    }

    /**
     * @dev Internal function to handle document signing
     */
    function _signDocument(uint256 documentId) internal {
        require(documentId < documentCount, "Document does not exist");
        Document storage doc = documents[documentId];
        require(!doc.hasSigned[msg.sender], "Already signed");

        // Mark as signed
        doc.hasSigned[msg.sender] = true;
        doc.signers.push(msg.sender);
        doc.signaturesCount++;

        // Mint unique NFT token to the signer
        uint256 tokenId = _tokenIdCounter++;
        _safeMint(msg.sender, tokenId);

        emit DocumentSigned(documentId, msg.sender, tokenId);
    }

    /**
     * @dev Check if an address has signed a document
     */
    function hasSigned(uint256 documentId, address signer) 
        external 
        view 
        returns (bool) 
    {
        require(documentId < documentCount, "Document does not exist");
        return documents[documentId].hasSigned[signer];
    }

    /**
     * @dev Get all signers of a document
     */
    function getSigners(uint256 documentId) 
        external 
        view 
        returns (address[] memory) 
    {
        require(documentId < documentCount, "Document does not exist");
        return documents[documentId].signers;
    }

    /**
     * @dev Get document details
     */
    function getDocumentInfo(uint256 documentId) 
        external 
        view 
        returns (
            string memory documentHash,
            uint256 createdAt,
            uint256 signaturesCount
        ) 
    {
        require(documentId < documentCount, "Document does not exist");
        Document storage doc = documents[documentId];
        return (doc.documentHash, doc.createdAt, doc.signaturesCount);
    }

    /**
     * @dev Get total number of tokens minted
     */
    function totalMinted() external view returns (uint256) {
        return _tokenIdCounter;
    }
}
