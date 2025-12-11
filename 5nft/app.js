// Global variables
let web3;
let contract;
let userAccount;
let allNFTs = [];
let filteredNFTs = [];

// Initialize the application
document.addEventListener('DOMContentLoaded', () => {
    initializeEventListeners();
    checkWalletConnection();
});

// Initialize all event listeners
function initializeEventListeners() {
    document.getElementById('connectWallet').addEventListener('click', connectWallet);
    document.getElementById('mintBtn').addEventListener('click', mintNFT);
    document.getElementById('searchBtn').addEventListener('click', applyFilters);
    document.getElementById('searchInput').addEventListener('keyup', (e) => {
        if (e.key === 'Enter') applyFilters();
    });
    document.getElementById('programFilter').addEventListener('change', applyFilters);
    document.getElementById('gradeFilter').addEventListener('change', applyFilters);
    document.getElementById('typeFilter').addEventListener('change', applyFilters);
    document.getElementById('resetFilters').addEventListener('click', resetFilters);
    
    // Debug buttons
    document.getElementById('debugBtn').addEventListener('click', showDebugInfo);
    document.getElementById('reloadBtn').addEventListener('click', () => {
        if (contract) {
            loadAllNFTs();
        } else {
            alert('Please connect wallet first!');
        }
    });
    
    // Modal close
    document.querySelector('.close').addEventListener('click', closeModal);
    window.addEventListener('click', (e) => {
        if (e.target.id === 'nftModal') closeModal();
    });
}

// Check if wallet is already connected
async function checkWalletConnection() {
    if (typeof window.ethereum !== 'undefined') {
        try {
            const accounts = await window.ethereum.request({ method: 'eth_accounts' });
            if (accounts.length > 0) {
                await connectWallet();
            }
        } catch (error) {
            console.error('Error checking wallet connection:', error);
        }
    }
}

// Connect to MetaMask wallet
async function connectWallet() {
    if (typeof window.ethereum === 'undefined') {
        alert('Please install MetaMask to use this DApp!');
        return;
    }

    try {
        showLoading(true);
        
        // Request account access
        const accounts = await window.ethereum.request({ method: 'eth_requestAccounts' });
        userAccount = accounts[0];
        
        // Initialize Web3
        web3 = new Web3(window.ethereum);
        
        // Initialize contract
        contract = new web3.eth.Contract(CONFIG.CONTRACT_ABI, CONFIG.CONTRACT_ADDRESS);
        
        // Update UI
        updateWalletUI();
        
        // Load NFTs
        await loadAllNFTs();
        
        // Enable mint button
        document.getElementById('mintBtn').disabled = false;
        
        // Listen for account changes
        window.ethereum.on('accountsChanged', handleAccountsChanged);
        window.ethereum.on('chainChanged', () => window.location.reload());
        
        showLoading(false);
    } catch (error) {
        console.error('Error connecting wallet:', error);
        alert('Failed to connect wallet: ' + error.message);
        showLoading(false);
    }
}

// Handle account changes
function handleAccountsChanged(accounts) {
    if (accounts.length === 0) {
        // User disconnected wallet
        location.reload();
    } else if (accounts[0] !== userAccount) {
        userAccount = accounts[0];
        updateWalletUI();
        loadAllNFTs();
    }
}

// Update wallet UI
async function updateWalletUI() {
    document.getElementById('connectWallet').style.display = 'none';
    document.getElementById('walletInfo').classList.remove('hidden');
    
    const shortAddress = `${userAccount.slice(0, 6)}...${userAccount.slice(-4)}`;
    document.getElementById('walletAddress').textContent = shortAddress;
    
    try {
        const userTokens = await contract.methods.getAllTokensOfOwner(userAccount).call();
        document.getElementById('userTokenCount').textContent = userTokens.length;
    } catch (error) {
        console.error('Error getting user tokens:', error);
        document.getElementById('userTokenCount').textContent = '0';
    }
}

// Load all NFTs from the contract
async function loadAllNFTs() {
    try {
        showLoading(true);
        
        // Get total supply
        const totalSupply = await contract.methods.totalSupply().call();
        const maxSupply = await contract.methods.maxSupply().call();
        
        console.log('📊 Total Supply:', totalSupply, 'Max Supply:', maxSupply);
        
        // Update stats
        document.getElementById('totalSupply').textContent = totalSupply;
        document.getElementById('maxSupply').textContent = maxSupply;
        
        allNFTs = [];
        
        // Load all NFTs
        for (let i = 0; i < totalSupply; i++) {
            try {
                const tokenId = await contract.methods.tokenByIndex(i).call();
                const tokenURI = await contract.methods.tokenURI(tokenId).call();
                
                console.log(`🔍 Loading NFT #${tokenId}, URI:`, tokenURI);
                
                // Fetch metadata
                const metadata = await fetchMetadata(tokenURI);
                
                if (metadata) {
                    console.log(`✅ NFT #${tokenId} loaded:`, metadata.name);
                    allNFTs.push({
                        tokenId: tokenId,
                        ...metadata
                    });
                } else {
                    console.warn(`⚠️ Failed to load metadata for NFT #${tokenId}`);
                    // Even if metadata fails, add a placeholder
                    allNFTs.push({
                        tokenId: tokenId,
                        name: `Certificate #${tokenId}`,
                        description: 'Metadata loading failed',
                        image: null,
                        attributes: []
                    });
                }
            } catch (error) {
                console.error(`❌ Error loading NFT ${i}:`, error);
            }
        }
        
        console.log('📦 Total NFTs loaded:', allNFTs.length);
        
        // Display NFTs
        filteredNFTs = [...allNFTs];
        displayNFTs(filteredNFTs);
        updateFilteredCount();
        
        showLoading(false);
    } catch (error) {
        console.error('❌ Error loading NFTs:', error);
        alert('Error loading NFTs. Check console for details.');
        showLoading(false);
    }
}

// Fetch metadata from IPFS with multiple gateway fallbacks
async function fetchMetadata(uri) {
    // Multiple IPFS gateways for reliability
    const gateways = [
        'https://gateway.pinata.cloud/ipfs/',
        'https://ipfs.io/ipfs/',
        'https://cloudflare-ipfs.com/ipfs/',
        'https://dweb.link/ipfs/'
    ];
    
    console.log('🔗 Fetching metadata from:', uri);
    
    for (const gateway of gateways) {
        try {
            // Convert IPFS URI to HTTP gateway URL
            const url = uri.replace('ipfs://', gateway);
            console.log('🌐 Trying gateway:', url);
            
            const response = await fetch(url, {
                method: 'GET',
                headers: {
                    'Accept': 'application/json'
                }
            });
            
            if (!response.ok) {
                console.warn(`⚠️ Gateway failed (${response.status}):`, gateway);
                continue;
            }
            
            const metadata = await response.json();
            console.log('✅ Metadata loaded from:', gateway);
            
            // Convert image URI if needed
            if (metadata.image && metadata.image.startsWith('ipfs://')) {
                metadata.image = metadata.image.replace('ipfs://', gateway);
                console.log('🖼️ Image URL:', metadata.image);
            }
            
            return metadata;
        } catch (error) {
            console.warn(`❌ Gateway error (${gateway}):`, error.message);
            // Continue to next gateway
        }
    }
    
    console.error('❌ All gateways failed for:', uri);
    return null;
}

// Display NFTs in the gallery
function displayNFTs(nfts) {
    const gallery = document.getElementById('nftGallery');
    const noResults = document.getElementById('noResults');
    
    console.log('🎨 Displaying', nfts.length, 'NFTs in gallery');
    
    gallery.innerHTML = '';
    
    if (nfts.length === 0) {
        noResults.classList.remove('hidden');
        console.warn('⚠️ No NFTs to display');
        return;
    }
    
    noResults.classList.add('hidden');
    
    nfts.forEach((nft, index) => {
        console.log(`🎴 Creating card for NFT #${nft.tokenId}`, nft);
        const card = createNFTCard(nft);
        gallery.appendChild(card);
    });
    
    console.log('✅ Gallery updated with', gallery.children.length, 'cards');
}

// Create NFT card element
function createNFTCard(nft) {
    const card = document.createElement('div');
    card.className = 'nft-card';
    card.onclick = () => showNFTDetails(nft);
    
    // Extract attributes
    const attributes = {};
    if (nft.attributes) {
        nft.attributes.forEach(attr => {
            attributes[attr.trait_type] = attr.value;
        });
    }
    
    card.innerHTML = `
        <div class="nft-image">
            ${nft.image ? `<img src="${nft.image}" alt="${nft.name}" onerror="this.parentElement.innerHTML='🎓'">` : '🎓'}
        </div>
        <div class="nft-details">
            <h3 class="nft-title">${nft.name || 'Certificate #' + nft.tokenId}</h3>
            <p class="nft-description">${nft.description || ''}</p>
            <div class="nft-attributes">
                ${attributes['Graduate Name'] ? `
                    <div class="attribute">
                        <span class="attribute-label">Graduate:</span>
                        <span class="attribute-value">${attributes['Graduate Name']}</span>
                    </div>
                ` : ''}
                ${attributes['Program'] ? `
                    <div class="attribute">
                        <span class="attribute-label">Program:</span>
                        <span class="attribute-value">${attributes['Program']}</span>
                    </div>
                ` : ''}
                ${attributes['Grade'] ? `
                    <div class="attribute grade-${attributes['Grade']}">
                        <span class="attribute-label">Grade:</span>
                        <span class="attribute-value">${attributes['Grade']}</span>
                    </div>
                ` : ''}
                ${attributes['Certificate Type'] ? `
                    <div class="attribute">
                        <span class="attribute-label">Type:</span>
                        <span class="attribute-value">${attributes['Certificate Type']}</span>
                    </div>
                ` : ''}
            </div>
            <div class="token-id">Token ID: ${nft.tokenId}</div>
        </div>
    `;
    
    return card;
}

// Show NFT details in modal
function showNFTDetails(nft) {
    const modal = document.getElementById('nftModal');
    const modalBody = document.getElementById('modalBody');
    
    const attributes = {};
    if (nft.attributes) {
        nft.attributes.forEach(attr => {
            attributes[attr.trait_type] = attr.value;
        });
    }
    
    modalBody.innerHTML = `
        <div style="text-align: center;">
            <div class="nft-image" style="margin-bottom: 20px; border-radius: 10px; overflow: hidden;">
                ${nft.image ? `<img src="${nft.image}" alt="${nft.name}" style="width: 100%; height: auto;" onerror="this.parentElement.innerHTML='<div style=\\'font-size: 8rem;\\'>🎓</div>'">` : '<div style="font-size: 8rem;">🎓</div>'}
            </div>
            <h2 style="margin-bottom: 15px;">${nft.name || 'Certificate #' + nft.tokenId}</h2>
            <p style="color: var(--text-secondary); margin-bottom: 20px;">${nft.description || ''}</p>
            <div style="text-align: left; background: var(--dark-bg); padding: 20px; border-radius: 10px;">
                <h3 style="margin-bottom: 15px; color: var(--primary-color);">Certificate Details</h3>
                ${Object.entries(attributes).map(([key, value]) => `
                    <div style="display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid var(--border-color);">
                        <span style="color: var(--text-secondary);">${key}:</span>
                        <span style="font-weight: 600;">${value}</span>
                    </div>
                `).join('')}
                <div style="display: flex; justify-content: space-between; padding: 10px 0; margin-top: 10px;">
                    <span style="color: var(--text-secondary);">Token ID:</span>
                    <span style="font-weight: 600; color: var(--accent-color);">${nft.tokenId}</span>
                </div>
            </div>
        </div>
    `;
    
    modal.classList.remove('hidden');
}

// Close modal
function closeModal() {
    document.getElementById('nftModal').classList.add('hidden');
}

// Apply search and filters
function applyFilters() {
    const searchTerm = document.getElementById('searchInput').value.toLowerCase();
    const programFilter = document.getElementById('programFilter').value;
    const gradeFilter = document.getElementById('gradeFilter').value;
    const typeFilter = document.getElementById('typeFilter').value;
    
    filteredNFTs = allNFTs.filter(nft => {
        // Search filter
        let matchesSearch = true;
        if (searchTerm) {
            const searchableText = JSON.stringify(nft).toLowerCase();
            matchesSearch = searchableText.includes(searchTerm);
        }
        
        // Program filter
        let matchesProgram = true;
        if (programFilter) {
            const programAttr = nft.attributes?.find(attr => attr.trait_type === 'Program');
            matchesProgram = programAttr?.value === programFilter;
        }
        
        // Grade filter
        let matchesGrade = true;
        if (gradeFilter) {
            const gradeAttr = nft.attributes?.find(attr => attr.trait_type === 'Grade');
            matchesGrade = gradeAttr?.value === gradeFilter;
        }
        
        // Type filter
        let matchesType = true;
        if (typeFilter) {
            const typeAttr = nft.attributes?.find(attr => attr.trait_type === 'Certificate Type');
            matchesType = typeAttr?.value === typeFilter;
        }
        
        return matchesSearch && matchesProgram && matchesGrade && matchesType;
    });
    
    displayNFTs(filteredNFTs);
    updateFilteredCount();
}

// Reset all filters
function resetFilters() {
    document.getElementById('searchInput').value = '';
    document.getElementById('programFilter').value = '';
    document.getElementById('gradeFilter').value = '';
    document.getElementById('typeFilter').value = '';
    
    filteredNFTs = [...allNFTs];
    displayNFTs(filteredNFTs);
    updateFilteredCount();
}

// Update filtered count
function updateFilteredCount() {
    document.getElementById('filteredCount').textContent = filteredNFTs.length;
}

// Mint new NFT
async function mintNFT() {
    if (!userAccount) {
        alert('Please connect your wallet first!');
        return;
    }
    
    try {
        const mintBtn = document.getElementById('mintBtn');
        mintBtn.disabled = true;
        mintBtn.textContent = 'Minting...';
        
        const cost = await contract.methods.cost().call();
        
        const tx = await contract.methods.safeMint(userAccount).send({
            from: userAccount,
            value: cost
        });
        
        alert('Certificate minted successfully! Transaction: ' + tx.transactionHash);
        
        // Reload NFTs
        await loadAllNFTs();
        await updateWalletUI();
        
        mintBtn.disabled = false;
        mintBtn.textContent = 'Mint Certificate';
    } catch (error) {
        console.error('Error minting NFT:', error);
        alert('Failed to mint certificate: ' + error.message);
        
        const mintBtn = document.getElementById('mintBtn');
        mintBtn.disabled = false;
        mintBtn.textContent = 'Mint Certificate';
    }
}

// Show/hide loading indicator
function showLoading(show) {
    const loading = document.getElementById('loadingIndicator');
    if (show) {
        loading.classList.remove('hidden');
    } else {
        loading.classList.add('hidden');
    }
}

// Utility function to format address
function formatAddress(address) {
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

// Show debug information
function showDebugInfo() {
    console.log('\n═══════════════════════════════════════════════');
    console.log('🔍 DEBUG INFORMATION');
    console.log('═══════════════════════════════════════════════');
    console.log('📱 Connected Account:', userAccount);
    console.log('📜 Contract Address:', CONFIG.CONTRACT_ADDRESS);
    console.log('🌐 Network:', window.ethereum?.chainId);
    console.log('📊 All NFTs loaded:', allNFTs.length);
    console.log('🔍 Filtered NFTs:', filteredNFTs.length);
    console.log('\n📦 NFT Data:');
    allNFTs.forEach((nft, index) => {
        console.log(`\n  NFT #${nft.tokenId}:`);
        console.log(`    Name: ${nft.name}`);
        console.log(`    Description: ${nft.description}`);
        console.log(`    Image: ${nft.image || 'No image'}`);
        console.log(`    Attributes:`, nft.attributes);
    });
    console.log('\n💡 DOM Gallery Cards:', document.querySelectorAll('.nft-card').length);
    console.log('═══════════════════════════════════════════════\n');
    
    alert(`✅ Debug info printed to console!\n\nAll NFTs: ${allNFTs.length}\nFiltered: ${filteredNFTs.length}\nGallery Cards: ${document.querySelectorAll('.nft-card').length}\n\nPress F12 to see detailed logs.`);
}

// Export functions for debugging (optional)
window.debugNFT = {
    reloadNFTs: loadAllNFTs,
    showNFTs: () => console.log(allNFTs),
    showFiltered: () => console.log(filteredNFTs),
    getContract: () => contract,
    getWeb3: () => web3,
    debugInfo: showDebugInfo
};
