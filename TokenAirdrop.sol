// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TokenAirdrop
 * @dev Airdrop contract with both batch transfer and Merkle Tree claim functionality
 */
contract TokenAirdrop is Ownable, ReentrancyGuard {
    IERC20 public token;
    
    // Merkle Tree variables
    bytes32 public merkleRoot;
    mapping(address => bool) public hasClaimed;
    
    // Airdrop tracking
    uint256 public totalAirdropped;
    uint256 public totalClaimed;
    mapping(address => uint256) public amountAirdropped;
    
    // Events
    event AirdropExecuted(address[] recipients, uint256[] amounts, uint256 totalAmount);
    event MerkleRootSet(bytes32 newMerkleRoot);
    event TokensClaimed(address indexed claimer, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    /**
     * @dev Batch airdrop to multiple addresses
     * @param recipients Array of recipient addresses
     * @param amounts Array of token amounts (in wei/smallest unit)
     */
    function batchAirdrop(
        address[] calldata recipients, 
        uint256[] calldata amounts
    ) external onlyOwner nonReentrant {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(recipients.length > 0, "Empty recipients array");
        require(recipients.length <= 200, "Too many recipients"); // Gas limit protection

        uint256 totalAmount = 0;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            require(amounts[i] > 0, "Amount must be greater than 0");
            
            totalAmount += amounts[i];
            amountAirdropped[recipients[i]] += amounts[i];
            
            require(
                token.transferFrom(msg.sender, recipients[i], amounts[i]),
                "Token transfer failed"
            );
        }

        totalAirdropped += totalAmount;
        emit AirdropExecuted(recipients, amounts, totalAmount);
    }

    /**
     * @dev Set Merkle root for claim-based airdrop
     * @param _merkleRoot The Merkle root hash
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }

    /**
     * @dev Claim tokens using Merkle proof
     * @param amount Amount of tokens to claim
     * @param merkleProof Array of proof hashes
     */
    function claim(uint256 amount, bytes32[] calldata merkleProof) 
        external 
        nonReentrant 
    {
        require(merkleRoot != bytes32(0), "Merkle root not set");
        require(!hasClaimed[msg.sender], "Already claimed");
        require(amount > 0, "Amount must be greater than 0");

        // Verify the Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, leaf),
            "Invalid Merkle proof"
        );

        // Mark as claimed
        hasClaimed[msg.sender] = true;
        totalClaimed += amount;
        amountAirdropped[msg.sender] += amount;

        // Transfer tokens
        require(
            token.transfer(msg.sender, amount),
            "Token transfer failed"
        );

        emit TokensClaimed(msg.sender, amount);
    }

    /**
     * @dev Check if an address has claimed
     */
    function isClaimed(address account) external view returns (bool) {
        return hasClaimed[account];
    }

    /**
     * @dev Verify if an address is eligible to claim
     */
    function verifyProof(
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(account, amount));
        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    /**
     * @dev Get contract token balance
     */
    function getContractBalance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev Withdraw remaining tokens (only owner)
     */
    function withdrawTokens(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "Invalid address");
        require(
            token.transfer(to, amount),
            "Token transfer failed"
        );
        emit TokensWithdrawn(to, amount);
    }

    /**
     * @dev Emergency withdraw all tokens (only owner)
     */
    function emergencyWithdraw(address to) external onlyOwner {
        require(to != address(0), "Invalid address");
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        require(
            token.transfer(to, balance),
            "Token transfer failed"
        );
        emit TokensWithdrawn(to, balance);
    }

    /**
     * @dev Get airdrop statistics
     */
    function getAirdropStats() 
        external 
        view 
        returns (
            uint256 _totalAirdropped,
            uint256 _totalClaimed,
            uint256 _contractBalance
        ) 
    {
        return (
            totalAirdropped,
            totalClaimed,
            token.balanceOf(address(this))
        );
    }
}
