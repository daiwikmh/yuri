// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ILeverageInterfaces.sol";

// Factory contract for creating user wallets and managing deposits
contract WalletFactory is Ownable {
    address payable public immutable userWalletTemplate;

    // Implementation contract address
    struct AccountInfo {
        address payable walletAddress;
        bool exists;
        uint256 createdAt;
    }

    mapping(address => AccountInfo) public userAccounts;
    mapping(address => bool) public allowedTokens;
    address[] public tokenList;

    event AccountCreated(address indexed user, address wallet);
    event FundsDeposited(address indexed user, address indexed token, uint256 amount);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    constructor(address payable _userWalletTemplate) Ownable(msg.sender) {
        require(_userWalletTemplate != address(0), "Invalid template address");
        require(_userWalletTemplate.code.length > 0, "Not a contract");
        userWalletTemplate = _userWalletTemplate;
    }

    // Create a new user wallet
    function createUserAccount() external returns (address payable userWallet) {
        require(!userAccounts[msg.sender].exists, "Account already exists");
        userWallet = payable(Clones.clone(userWalletTemplate));
        UserWallet(userWallet).initialize(msg.sender, address(this));
        userAccounts[msg.sender] = AccountInfo({
            walletAddress: userWallet,
            exists: true,
            createdAt: block.timestamp
        });
        emit AccountCreated(msg.sender, userWallet);
        return userWallet;
    }

    // Deposit ERC-20 tokens
    function depositFunds(address token, uint256 amount) external {
        require(allowedTokens[token], "Token not allowed");
        address payable userWallet = userAccounts[msg.sender].walletAddress;
        require(userWallet != address(0), "Create account first");
        uint256 balanceBefore = IERC20(token).balanceOf(userWallet);
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, userWallet, amount);
        require(IERC20(token).balanceOf(userWallet) == balanceBefore + amount, "Transfer mismatch");
        UserWallet(userWallet).creditBalance(token, amount);
        emit FundsDeposited(msg.sender, token, amount);
    }

    // Deposit ETH
    function depositETH() external payable {
        require(allowedTokens[address(0)], "ETH not allowed");
        address payable userWallet = userAccounts[msg.sender].walletAddress;
        require(userWallet != address(0), "Create account first");
        (bool success, ) = userWallet.call{value: msg.value}("");
        require(success, "ETH transfer failed");
        UserWallet(userWallet).creditBalance(address(0), msg.value);
        emit FundsDeposited(msg.sender, address(0), msg.value);
    }

    // Owner adds a token to the whitelist (allows address(0) for ETH)
    function addToken(address token) external onlyOwner {
        if (token != address(0)) {
            require(token.code.length > 0, "Invalid ERC-20 token");
        }
        require(!allowedTokens[token], "Token already allowed");
        allowedTokens[token] = true;
        tokenList.push(token);
        emit TokenAdded(token);
    }

    // Owner removes a token from the whitelist
    function removeToken(address token) external onlyOwner {
        require(allowedTokens[token], "Token not allowed");
        allowedTokens[token] = false;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }
        emit TokenRemoved(token);
    }

    // View allowed tokens
    function getAllowedTokens() external view returns (address[] memory) {
        return tokenList;
    }
}

// User wallet implementation (delegated wallet)
contract UserWallet {
    address public owner;
    address public platform;
    bool private initialized;
    mapping(address => uint256) public balances;

    // Token balances (address(0) for ETH)
    // Delegation rules
    struct Delegation {
        bool active;
        uint256 maxTradeAmount;
        uint256 expiry;
    }

    mapping(bytes32 => Delegation) public delegations;

    event TradeExecuted(address indexed user, address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed user, address indexed token, uint256 amount);
    event DelegationSet(address indexed user, bytes32 indexed delegationHash);

    modifier onlyPlatform() {
        require(msg.sender == platform, "Only platform can execute");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    function initialize(address _owner, address _platform) external {
        require(!initialized, "Already initialized");
        initialized = true;
        owner = _owner;
        platform = _platform;
    }

    // Credit balance (called by WalletFactory)
    function creditBalance(address token, uint256 amount) external onlyPlatform {
        balances[token] += amount;
    }

    // Set delegation (user signs off-chain)
    function setDelegation(
        bytes32 delegationHash,
        uint256 maxTradeAmount,
        uint256 expiry,
        bytes calldata signature
    ) external onlyOwner {
        require(block.timestamp < expiry, "Expired");
        require(verifySignature(delegationHash, signature), "Invalid signature");
        delegations[delegationHash] = Delegation(true, maxTradeAmount, expiry);
        emit DelegationSet(owner, delegationHash);
    }

    // Platform executes trade with delegation rules
    function executeTrade(
        address tokenIn,
        uint256 amount,
        bytes calldata tradeData,
        bytes32 delegationHash
    ) external onlyPlatform {
        Delegation memory delegation = delegations[delegationHash];
        require(delegation.active, "Invalid delegation");
        require(block.timestamp < delegation.expiry, "Delegation expired");
        require(balances[tokenIn] >= amount, "Insufficient balance");
        require(amount <= delegation.maxTradeAmount, "Exceeds trade limit");
        if (tokenIn != address(0)) {
            SafeERC20.forceApprove(IERC20(tokenIn), platform, amount);
        }
        (bool success, ) = platform.call{value: tokenIn == address(0) ? amount : 0}(tradeData);
        require(success, "Trade failed");
        balances[tokenIn] -= amount;
        emit TradeExecuted(owner, tokenIn, amount);
    }

    // User withdraws funds
    function withdraw(address token, uint256 amount) external onlyOwner {
        require(balances[token] >= amount, "Insufficient balance");
        balances[token] -= amount;
        if (token == address(0)) {
            (bool success, ) = owner.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            SafeERC20.safeTransfer(IERC20(token), owner, amount);
        }
        emit FundsWithdrawn(owner, token, amount);
    }

    // Verify delegation signature
    function verifySignature(bytes32 hash, bytes calldata signature) internal view returns (bool) {
        require(signature.length == 65, "Invalid signature length");
        bytes memory sigCopy = new bytes(65);
        assembly {
            calldatacopy(add(sigCopy, 32), signature.offset, 65)
        }
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sigCopy, 32))
            s := mload(add(sigCopy, 64))
            v := byte(0, mload(add(sigCopy, 96)))
        }
        return owner == ecrecover(hash, v, r, s);
    }

    // Receive ETH
    receive() external payable {}
}
