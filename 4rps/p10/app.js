// Smart Contract Configuration is now in config.js
const contractAddress = CONTRACT_ADDRESS;
const contractABI = CONTRACT_ABI;

let userScore = 0;
let computerScore = 0;
let provider;
let signer;
let contract;
let userAddress;
let minBetAmount;
let maxBetAmount;
let contractBalance;

// DOM Elements
const userScore_span = document.getElementById('user-score');
const computerScore_span = document.getElementById('computer-score');
const result_p = document.querySelector('.result > p');
const rock_div = document.getElementById('r');
const paper_div = document.getElementById('p');
const scissors_div = document.getElementById('s');
const connectBtn = document.getElementById('connectBtn');
const walletAddress_p = document.getElementById('wallet-address');
const betAmount_input = document.getElementById('bet-amount');
const maxBetBtn = document.getElementById('max-bet-btn');
const betInfo_p = document.getElementById('bet-info');
const contractBalance_span = document.getElementById('contract-balance');
const userBalance_span = document.getElementById('user-balance');

// Convert choice letter to word
function convertToWord(letter) {
    if (letter === 'r') return "Rock";
    if (letter === 'p') return "Paper";
    return "Scissors";
}

// Convert choice letter to smart contract Move enum (0=Rock, 1=Paper, 2=Scissors)
function convertToMove(letter) {
    if (letter === 'r') return 0;
    if (letter === 'p') return 1;
    if (letter === 's') return 2;
}

// Convert smart contract Move enum to letter
function convertMoveToLetter(move) {
    if (move === 0) return 'r';
    if (move === 1) return 'p';
    if (move === 2) return 's';
}

// Update contract balance display
async function updateContractBalance() {
    try {
        const balance = await contract.getBalance();
        contractBalance = balance;
        contractBalance_span.innerText = `${ethers.utils.formatEther(balance)} BNB`;
        
        // Update max bet (contract balance)
        maxBetAmount = balance;
        return balance;
    } catch (error) {
        console.error('Error getting contract balance:', error);
    }
}

// Update user balance display
async function updateUserBalance() {
    try {
        const balance = await provider.getBalance(userAddress);
        userBalance_span.innerText = `${parseFloat(ethers.utils.formatEther(balance)).toFixed(4)} BNB`;
    } catch (error) {
        console.error('Error getting user balance:', error);
    }
}

// Update bet info
async function updateBetInfo() {
    const minBet = await contract.minBet();
    minBetAmount = minBet;
    const minBetFormatted = ethers.utils.formatEther(minBet);
    const maxBetFormatted = ethers.utils.formatEther(maxBetAmount);
    
    betInfo_p.innerText = `Min: ${minBetFormatted} BNB | Max: ${maxBetFormatted} BNB`;
    betAmount_input.min = minBetFormatted;
    betAmount_input.max = maxBetFormatted;
}

// Set max bet
function setMaxBet() {
    if (maxBetAmount) {
        betAmount_input.value = ethers.utils.formatEther(maxBetAmount);
    }
}

// Connect Wallet Function
async function connectWallet() {
    if (typeof window.ethereum === 'undefined') {
        alert('Please install MetaMask!');
        return;
    }

    try {
        // Request account access
        await window.ethereum.request({ method: 'eth_requestAccounts' });
        
        provider = new ethers.providers.Web3Provider(window.ethereum);
        signer = provider.getSigner();
        userAddress = await signer.getAddress();
        
        // Create contract instance
        contract = new ethers.Contract(contractAddress, contractABI, signer);
        
        // Update UI
        connectBtn.innerText = 'Connected ✓';
        connectBtn.disabled = true;
        walletAddress_p.innerText = `${userAddress.substring(0, 6)}...${userAddress.substring(38)}`;
        result_p.innerHTML = 'Choose your move and place your bet!';
        
        // Update balances and bet info
        await updateContractBalance();
        await updateUserBalance();
        await updateBetInfo();
        
        console.log('Connected to:', userAddress);
        console.log('Contract:', contract);
        
    } catch (error) {
        console.error('Connection error:', error);
        alert('Failed to connect: ' + error.message);
    }
}

// Display result after game
function displayResult(userChoice, computerChoice, playerWon) {
    const userChoice_div = document.getElementById(userChoice);
    const smallUserWord = "user".fontsize(3).sub();
    const smallCompWord = "comp".fontsize(3).sub();
    
    if (playerWon === null) {
        // Draw
        result_p.innerHTML = `${convertToWord(userChoice)}${smallUserWord} equals ${convertToWord(computerChoice)}${smallCompWord}. It's a draw.`;
        userChoice_div.classList.add('gray-glow');
        setTimeout(() => userChoice_div.classList.remove('gray-glow'), 300);
    } else if (playerWon) {
        // Win
        userScore++;
        userScore_span.innerHTML = userScore;
        result_p.innerHTML = `${convertToWord(userChoice)}${smallUserWord} beats ${convertToWord(computerChoice)}${smallCompWord}. You win!`;
        userChoice_div.classList.add('green-glow');
        setTimeout(() => userChoice_div.classList.remove('green-glow'), 300);
    } else {
        // Lose
        computerScore++;
        computerScore_span.innerHTML = computerScore;
        result_p.innerHTML = `${convertToWord(userChoice)}${smallUserWord} loses to ${convertToWord(computerChoice)}${smallCompWord}. You lost...`;
        userChoice_div.classList.add('red-glow');
        setTimeout(() => userChoice_div.classList.remove('red-glow'), 300);
    }
}

// Main game function - now calls smart contract
async function game(userChoice) {
    if (!contract) {
        alert('Please connect your wallet first!');
        return;
    }
    
    try {
        // Get bet amount from input
        const betValue = betAmount_input.value;
        if (!betValue || parseFloat(betValue) <= 0) {
            alert('Please enter a valid bet amount!');
            return;
        }
        
        const betAmount = ethers.utils.parseEther(betValue);
        
        // Validate bet amount
        if (betAmount.lt(minBetAmount)) {
            alert(`Bet must be at least ${ethers.utils.formatEther(minBetAmount)} BNB`);
            return;
        }
        
        if (betAmount.gt(maxBetAmount)) {
            alert(`Bet cannot exceed ${ethers.utils.formatEther(maxBetAmount)} BNB (contract balance)`);
            return;
        }
        
        // Show loading message
        result_p.innerHTML = '⏳ Loading... Waiting for blockchain transaction...';
        
        const moveEnum = convertToMove(userChoice);
        
        // Call play() function on smart contract with user's bet amount
        const tx = await contract.play(moveEnum, { value: betAmount });
        
        result_p.innerHTML = '⏳ Transaction sent! Waiting for confirmation...';
        
        // Wait for transaction to be mined
        const receipt = await tx.wait();
        
        console.log('Transaction receipt:', receipt);
        
        // Update balances after game
        await updateContractBalance();
        await updateUserBalance();
        await updateBetInfo();
        
        // Parse the GamePlayed event from the receipt
        const gameEvent = receipt.events?.find(e => e.event === 'GamePlayed');
        
        if (gameEvent) {
            const { playerMove, contractMove, playerWon, amountWon } = gameEvent.args;
            
            const computerChoice = convertMoveToLetter(contractMove);
            const playerWonResult = playerMove === contractMove ? null : playerWon;
            
            console.log('Player move:', playerMove);
            console.log('Contract move:', contractMove);
            console.log('Player won:', playerWon);
            console.log('Amount won:', ethers.utils.formatEther(amountWon));
            
            // Display result
            displayResult(userChoice, computerChoice, playerWonResult);
        } else {
            result_p.innerHTML = 'Game played! Check console for details.';
        }
        
    } catch (error) {
        console.error('Game error:', error);
        
        if (error.code === 4001) {
            result_p.innerHTML = 'Transaction rejected by user.';
        } else if (error.message.includes('insufficient funds')) {
            result_p.innerHTML = 'Insufficient funds for bet + gas.';
        } else {
            result_p.innerHTML = 'Error: ' + error.message;
        }
    }
}

// Event listeners
connectBtn.addEventListener('click', connectWallet);
maxBetBtn.addEventListener('click', setMaxBet);

rock_div.addEventListener('click', function () {
    game('r');
});

paper_div.addEventListener('click', function () {
    game('p');
});

scissors_div.addEventListener('click', function () {
    game('s');
});