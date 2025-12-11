// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RockPaperScissors {
    address public owner;
    uint256 public minBet = 0.0001 ether; // minimum bet
    uint256 public maxBet = 1 ether; // optional limit

    enum Move { Rock, Paper, Scissors }

    event GamePlayed(address indexed player, Move playerMove, Move contractMove, bool playerWon, uint256 amountWon);

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {} // allow deposits

    function play(Move _playerMove) external payable {
        require(msg.value >= minBet, "Bet too small");
        require(msg.value <= maxBet, "Bet too large");
        require(address(this).balance >= msg.value * 2, "Contract lacks funds for payout");

        // Generate pseudo-random move for contract (not secure for production)
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, block.prevrandao))) % 3;
        Move contractMove = Move(random);

        bool playerWon = _determineWinner(_playerMove, contractMove);
        uint256 payout = 0;

        if (playerWon) {
            payout = msg.value * 2;
            payable(msg.sender).transfer(payout);
        }

        emit GamePlayed(msg.sender, _playerMove, contractMove, playerWon, payout);
    }

    function _determineWinner(Move player, Move contractMove) internal pure returns (bool) {
        if (player == contractMove) return false; // 
        if (player == Move.Rock && contractMove == Move.Scissors) return true;
        if (player == Move.Paper && contractMove == Move.Rock) return true;
        if (player == Move.Scissors && contractMove == Move.Paper) return true;
        return false;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == owner, "Only owner can withdraw");
        payable(owner).transfer(amount);
    }
}