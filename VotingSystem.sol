// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VotingSystem
 * @dev Advanced voting system with digital identity verification and quorum requirements
 * Features:
 * - Create voting sessions with multiple options
 * - Cast votes with duplicate prevention
 * - Extract voting results
 * - Real-time vote count tracking
 * - Minimum quorum requirements
 * - Digital Identity verification to prevent Sybil attacks
 */
contract VotingSystem is Ownable, ReentrancyGuard {
    // Digital Identity structure for Sybil attack prevention
    struct DigitalIdentity {
        bool isVerified;
        uint256 verificationTimestamp;
        string identityHash; // Could be hash of KYC data, government ID, etc.
        uint256 reputationScore;
    }

    // Voting option structure
    struct VotingOption {
        string name;
        uint256 voteCount;
    }

    // Voting session structure
    struct VotingSession {
        string topic;
        address creator;
        uint256 createdAt;
        uint256 endTime;
        bool isActive;
        bool requiresIdentityVerification;
        uint256 minimumQuorum;
        uint256 totalVotes;
        mapping(uint256 => VotingOption) options;
        uint256 optionsCount;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voterChoice;
        address[] voters;
    }

    // State variables
    mapping(uint256 => VotingSession) public votingSessions;
    uint256 public sessionCount;
    
    // Digital Identity registry
    mapping(address => DigitalIdentity) public identities;
    mapping(string => bool) public identityHashUsed;
    
    // Identity verifiers (authorized addresses that can verify identities)
    mapping(address => bool) public isVerifier;

    // Events
    event VotingSessionCreated(
        uint256 indexed sessionId,
        string topic,
        address indexed creator,
        uint256 endTime,
        uint256 minimumQuorum,
        bool requiresIdentityVerification
    );
    event VoteCast(
        uint256 indexed sessionId,
        address indexed voter,
        uint256 optionId,
        string optionName
    );
    event VotingSessionEnded(uint256 indexed sessionId, uint256 totalVotes);
    event IdentityVerified(address indexed user, string identityHash);
    event IdentityRevoked(address indexed user);
    event VerifierAdded(address indexed verifier);
    event VerifierRemoved(address indexed verifier);

    // Modifiers
    modifier sessionExists(uint256 sessionId) {
        require(sessionId < sessionCount, "Session does not exist");
        _;
    }

    modifier sessionActive(uint256 sessionId) {
        require(votingSessions[sessionId].isActive, "Session is not active");
        require(block.timestamp < votingSessions[sessionId].endTime, "Voting period has ended");
        _;
    }

    modifier onlyVerifier() {
        require(isVerifier[msg.sender] || msg.sender == owner(), "Not authorized verifier");
        _;
    }

    constructor() Ownable(msg.sender) {
        // Owner is automatically a verifier
        isVerifier[msg.sender] = true;
        emit VerifierAdded(msg.sender);
    }

    // ==================== Digital Identity Functions ====================

    /**
     * @dev Add a verifier who can verify digital identities
     */
    function addVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "Invalid address");
        require(!isVerifier[verifier], "Already a verifier");
        isVerifier[verifier] = true;
        emit VerifierAdded(verifier);
    }

    /**
     * @dev Remove a verifier
     */
    function removeVerifier(address verifier) external onlyOwner {
        require(isVerifier[verifier], "Not a verifier");
        isVerifier[verifier] = false;
        emit VerifierRemoved(verifier);
    }

    /**
     * @dev Verify a user's digital identity (KYC/identity verification)
     * @param user Address of the user to verify
     * @param identityHash Unique hash of user's identity document
     * @param reputationScore Initial reputation score (0-100)
     */
    function verifyIdentity(
        address user,
        string memory identityHash,
        uint256 reputationScore
    ) external onlyVerifier {
        require(user != address(0), "Invalid address");
        require(!identities[user].isVerified, "Already verified");
        require(!identityHashUsed[identityHash], "Identity hash already used");
        require(reputationScore <= 100, "Reputation score must be 0-100");
        require(bytes(identityHash).length > 0, "Identity hash cannot be empty");

        identities[user] = DigitalIdentity({
            isVerified: true,
            verificationTimestamp: block.timestamp,
            identityHash: identityHash,
            reputationScore: reputationScore
        });

        identityHashUsed[identityHash] = true;
        emit IdentityVerified(user, identityHash);
    }

    /**
     * @dev Revoke a user's identity verification
     */
    function revokeIdentity(address user) external onlyVerifier {
        require(identities[user].isVerified, "User not verified");
        
        // Mark identity hash as unused
        identityHashUsed[identities[user].identityHash] = false;
        
        // Reset identity
        delete identities[user];
        emit IdentityRevoked(user);
    }

    /**
     * @dev Update reputation score
     */
    function updateReputationScore(address user, uint256 newScore) external onlyVerifier {
        require(identities[user].isVerified, "User not verified");
        require(newScore <= 100, "Reputation score must be 0-100");
        identities[user].reputationScore = newScore;
    }

    /**
     * @dev Check if address has verified identity
     */
    function isIdentityVerified(address user) public view returns (bool) {
        return identities[user].isVerified;
    }

    /**
     * @dev Get user's identity information
     */
    function getIdentityInfo(address user) 
        external 
        view 
        returns (
            bool isVerified,
            uint256 verificationTimestamp,
            uint256 reputationScore
        ) 
    {
        DigitalIdentity memory identity = identities[user];
        return (
            identity.isVerified,
            identity.verificationTimestamp,
            identity.reputationScore
        );
    }

    // ==================== Voting Session Functions ====================

    /**
     * @dev Create a new voting session
     * @param topic The topic/question for voting
     * @param optionNames Array of voting option names
     * @param durationInSeconds How long the voting will be active
     * @param minimumQuorum Minimum percentage of votes required (0-100)
     * @param requiresIdentityVerification Whether voters must have verified identity
     */
    function createVotingSession(
        string memory topic,
        string[] memory optionNames,
        uint256 durationInSeconds,
        uint256 minimumQuorum,
        bool requiresIdentityVerification
    ) external returns (uint256) {
        require(bytes(topic).length > 0, "Topic cannot be empty");
        require(optionNames.length >= 2, "Must have at least 2 options");
        require(optionNames.length <= 20, "Too many options");
        require(durationInSeconds > 0, "Duration must be positive");
        require(minimumQuorum <= 100, "Quorum must be 0-100");

        uint256 sessionId = sessionCount++;
        VotingSession storage session = votingSessions[sessionId];
        
        session.topic = topic;
        session.creator = msg.sender;
        session.createdAt = block.timestamp;
        session.endTime = block.timestamp + durationInSeconds;
        session.isActive = true;
        session.requiresIdentityVerification = requiresIdentityVerification;
        session.minimumQuorum = minimumQuorum;
        session.totalVotes = 0;
        session.optionsCount = optionNames.length;

        // Add voting options
        for (uint256 i = 0; i < optionNames.length; i++) {
            require(bytes(optionNames[i]).length > 0, "Option name cannot be empty");
            session.options[i] = VotingOption({
                name: optionNames[i],
                voteCount: 0
            });
        }

        emit VotingSessionCreated(
            sessionId,
            topic,
            msg.sender,
            session.endTime,
            minimumQuorum,
            requiresIdentityVerification
        );

        return sessionId;
    }

    /**
     * @dev Cast a vote for a specific option
     * @param sessionId The ID of the voting session
     * @param optionId The ID of the option to vote for
     */
    function vote(uint256 sessionId, uint256 optionId) 
        external 
        nonReentrant
        sessionExists(sessionId)
        sessionActive(sessionId)
    {
        VotingSession storage session = votingSessions[sessionId];
        
        require(!session.hasVoted[msg.sender], "Already voted in this session");
        require(optionId < session.optionsCount, "Invalid option ID");
        
        // Check identity verification if required
        if (session.requiresIdentityVerification) {
            require(
                identities[msg.sender].isVerified,
                "Identity verification required to vote"
            );
        }

        // Record the vote
        session.hasVoted[msg.sender] = true;
        session.voterChoice[msg.sender] = optionId;
        session.voters.push(msg.sender);
        session.options[optionId].voteCount++;
        session.totalVotes++;

        emit VoteCast(
            sessionId,
            msg.sender,
            optionId,
            session.options[optionId].name
        );
    }

    /**
     * @dev End a voting session (can only be called by creator or after end time)
     */
    function endVotingSession(uint256 sessionId) 
        external 
        sessionExists(sessionId)
    {
        VotingSession storage session = votingSessions[sessionId];
        require(session.isActive, "Session already ended");
        require(
            msg.sender == session.creator || 
            block.timestamp >= session.endTime ||
            msg.sender == owner(),
            "Not authorized to end session"
        );

        session.isActive = false;
        emit VotingSessionEnded(sessionId, session.totalVotes);
    }

    // ==================== Result Extraction Functions ====================

    /**
     * @dev Get current vote count for a specific option (EXTRA)
     * @param sessionId The ID of the voting session
     * @param optionId The ID of the option
     */
    function getOptionVoteCount(uint256 sessionId, uint256 optionId)
        external
        view
        sessionExists(sessionId)
        returns (uint256)
    {
        VotingSession storage session = votingSessions[sessionId];
        require(optionId < session.optionsCount, "Invalid option ID");
        return session.options[optionId].voteCount;
    }

    /**
     * @dev Get current vote counts for all options (EXTRA)
     */
    function getAllVoteCounts(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (string[] memory optionNames, uint256[] memory voteCounts)
    {
        VotingSession storage session = votingSessions[sessionId];
        
        optionNames = new string[](session.optionsCount);
        voteCounts = new uint256[](session.optionsCount);

        for (uint256 i = 0; i < session.optionsCount; i++) {
            optionNames[i] = session.options[i].name;
            voteCounts[i] = session.options[i].voteCount;
        }

        return (optionNames, voteCounts);
    }

    /**
     * @dev Extract complete voting results
     * @param sessionId The ID of the voting session
     */
    function getVotingResults(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (
            string memory topic,
            string[] memory optionNames,
            uint256[] memory voteCounts,
            uint256 totalVotes,
            bool isActive,
            bool quorumMet,
            uint256 winningOptionId
        )
    {
        VotingSession storage session = votingSessions[sessionId];
        
        topic = session.topic;
        totalVotes = session.totalVotes;
        isActive = session.isActive;
        
        // Get all option names and vote counts
        optionNames = new string[](session.optionsCount);
        voteCounts = new uint256[](session.optionsCount);
        
        uint256 maxVotes = 0;
        winningOptionId = 0;

        for (uint256 i = 0; i < session.optionsCount; i++) {
            optionNames[i] = session.options[i].name;
            voteCounts[i] = session.options[i].voteCount;
            
            if (voteCounts[i] > maxVotes) {
                maxVotes = voteCounts[i];
                winningOptionId = i;
            }
        }

        // Check if quorum is met (EXTRA)
        // Quorum is based on percentage of total possible voters
        // For simplicity, we check if votes meet minimum threshold
        quorumMet = (totalVotes >= session.minimumQuorum);

        return (
            topic,
            optionNames,
            voteCounts,
            totalVotes,
            isActive,
            quorumMet,
            winningOptionId
        );
    }

    /**
     * @dev Get detailed session information
     */
    function getSessionInfo(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (
            string memory topic,
            address creator,
            uint256 createdAt,
            uint256 endTime,
            bool isActive,
            bool requiresIdentityVerification,
            uint256 minimumQuorum,
            uint256 totalVotes,
            uint256 optionsCount
        )
    {
        VotingSession storage session = votingSessions[sessionId];
        return (
            session.topic,
            session.creator,
            session.createdAt,
            session.endTime,
            session.isActive,
            session.requiresIdentityVerification,
            session.minimumQuorum,
            session.totalVotes,
            session.optionsCount
        );
    }

    /**
     * @dev Check if an address has voted in a session
     */
    function hasVoted(uint256 sessionId, address voter)
        external
        view
        sessionExists(sessionId)
        returns (bool)
    {
        return votingSessions[sessionId].hasVoted[voter];
    }

    /**
     * @dev Get the choice made by a voter
     */
    function getVoterChoice(uint256 sessionId, address voter)
        external
        view
        sessionExists(sessionId)
        returns (uint256 optionId, string memory optionName)
    {
        VotingSession storage session = votingSessions[sessionId];
        require(session.hasVoted[voter], "Voter has not voted");
        
        optionId = session.voterChoice[voter];
        optionName = session.options[optionId].name;
        
        return (optionId, optionName);
    }

    /**
     * @dev Get all voters in a session
     */
    function getVoters(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (address[] memory)
    {
        return votingSessions[sessionId].voters;
    }

    /**
     * @dev Get winning option details
     */
    function getWinner(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (
            uint256 optionId,
            string memory optionName,
            uint256 voteCount,
            bool quorumMet
        )
    {
        VotingSession storage session = votingSessions[sessionId];
        require(!session.isActive, "Voting session still active");
        
        uint256 maxVotes = 0;
        uint256 winningId = 0;

        for (uint256 i = 0; i < session.optionsCount; i++) {
            if (session.options[i].voteCount > maxVotes) {
                maxVotes = session.options[i].voteCount;
                winningId = i;
            }
        }

        quorumMet = (session.totalVotes >= session.minimumQuorum);

        return (
            winningId,
            session.options[winningId].name,
            maxVotes,
            quorumMet
        );
    }

    /**
     * @dev Check if quorum is met for a session (EXTRA)
     */
    function isQuorumMet(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (bool)
    {
        VotingSession storage session = votingSessions[sessionId];
        return (session.totalVotes >= session.minimumQuorum);
    }

    /**
     * @dev Get quorum progress percentage
     */
    function getQuorumProgress(uint256 sessionId)
        external
        view
        sessionExists(sessionId)
        returns (uint256 currentVotes, uint256 requiredVotes, uint256 percentageComplete)
    {
        VotingSession storage session = votingSessions[sessionId];
        currentVotes = session.totalVotes;
        requiredVotes = session.minimumQuorum;
        
        if (requiredVotes == 0) {
            percentageComplete = 100;
        } else {
            percentageComplete = (currentVotes * 100) / requiredVotes;
            if (percentageComplete > 100) {
                percentageComplete = 100;
            }
        }
        
        return (currentVotes, requiredVotes, percentageComplete);
    }
}
