// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract OnChainSubscriptionManager {
    struct Subscription {
        uint256 id;
        address subscriber;
        address serviceProvider;
        uint256 amount;
        uint256 interval;
        uint256 nextPayment;
        bool isActive;
        uint256 totalPaid;
        uint256 subscriptionStart;
    }
    
    mapping(uint256 => Subscription) public subscriptions;
    mapping(address => uint256[]) public userSubscriptions;
    mapping(address => uint256[]) public providerSubscriptions;
    mapping(address => uint256) public providerBalances;
    
    uint256 public subscriptionCounter;
    uint256 public platformFee = 250; // 2.5% in basis points
    address public owner;
    
    event SubscriptionCreated(uint256 indexed subscriptionId, address indexed subscriber, address indexed provider, uint256 amount, uint256 interval);
    event PaymentProcessed(uint256 indexed subscriptionId, uint256 amount, uint256 nextPayment);
    event SubscriptionCancelled(uint256 indexed subscriptionId);
    event RefundIssued(uint256 indexed subscriptionId, uint256 refundAmount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function createSubscription(address _serviceProvider, uint256 _amount, uint256 _interval) external payable {
        require(_serviceProvider != address(0), "Invalid service provider");
        require(_amount > 0, "Amount must be greater than 0");
        require(_interval > 0, "Interval must be greater than 0");
        require(msg.value >= _amount, "Insufficient payment for first period");
        
        subscriptionCounter++;
        subscriptions[subscriptionCounter] = Subscription({
            id: subscriptionCounter,
            subscriber: msg.sender,
            serviceProvider: _serviceProvider,
            amount: _amount,
            interval: _interval,
            nextPayment: block.timestamp + _interval,
            isActive: true,
            totalPaid: _amount,
            subscriptionStart: block.timestamp
        });
        
        userSubscriptions[msg.sender].push(subscriptionCounter);
        providerSubscriptions[_serviceProvider].push(subscriptionCounter);
        
        // Process first payment
        uint256 fee = (_amount * platformFee) / 10000;
        uint256 providerAmount = _amount - fee;
        providerBalances[_serviceProvider] += providerAmount;
        
        // Refund excess payment
        if (msg.value > _amount) {
            payable(msg.sender).transfer(msg.value - _amount);
        }
        
        emit SubscriptionCreated(subscriptionCounter, msg.sender, _serviceProvider, _amount, _interval);
        emit PaymentProcessed(subscriptionCounter, _amount, subscriptions[subscriptionCounter].nextPayment);
    }
    
    function processPayment(uint256 _subscriptionId) external payable {
        Subscription storage sub = subscriptions[_subscriptionId];
        require(sub.isActive, "Subscription not active");
        require(block.timestamp >= sub.nextPayment, "Payment not due yet");
        require(msg.value >= sub.amount, "Insufficient payment");
        
        // Update subscription
        sub.nextPayment = block.timestamp + sub.interval;
        sub.totalPaid += sub.amount;
        
        // Process payment
        uint256 fee = (sub.amount * platformFee) / 10000;
        uint256 providerAmount = sub.amount - fee;
        providerBalances[sub.serviceProvider] += providerAmount;
        
        // Refund excess payment
        if (msg.value > sub.amount) {
            payable(msg.sender).transfer(msg.value - sub.amount);
        }
        
        emit PaymentProcessed(_subscriptionId, sub.amount, sub.nextPayment);
    }
    
    function cancelSubscription(uint256 _subscriptionId) external {
        Subscription storage sub = subscriptions[_subscriptionId];
        require(sub.subscriber == msg.sender || sub.serviceProvider == msg.sender, "Not authorized");
        require(sub.isActive, "Subscription already cancelled");
        
        sub.isActive = false;
        
        emit SubscriptionCancelled(_subscriptionId);
    }
    
    function withdrawProviderBalance() external {
        uint256 balance = providerBalances[msg.sender];
        require(balance > 0, "No balance to withdraw");
        
        providerBalances[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
    }
