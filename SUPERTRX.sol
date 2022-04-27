// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "./DividendPayingToken.sol";
import "./SafeMath.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";


contract SUPERTRX is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public  uniswapV2Pair;

    bool private swapping;

    TRXDividendTracker public dividendTracker;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    address public immutable TRX = address(0x85EAC5Ac2F758618dFa09bDbe0cf174e7d574D5B); //TRX

    uint256 public swapTokensAtAmount = 1000000000 * (10**18);
    uint256 public _maxBuyTxAmount = 30000000 * 10**18;
    uint256 public _maxSellTxAmount = 30000000 * 10**18;
    uint256 public maxWalletToken = 10000000 * (10**18);
    
    uint256 public TRXRewardsBuyFee = 5;
    uint256 public LiquidityBuyFee = 1;
    uint256 public MarketingBuyFee = 3;
    uint256 public buyBackBuyFee = 1;
    uint256 public weeklyLotteryBuyFee = 1;
    uint256 public DAOWalletBuyFee = 1;
    uint256 public totalBuyFees = TRXRewardsBuyFee.add(LiquidityBuyFee).add(MarketingBuyFee).add(buyBackBuyFee).add(weeklyLotteryBuyFee).add(DAOWalletBuyFee);
    
   
    uint256 public TRXRewardsSellFee = 5;
    uint256 public LiquiditySellFee = 3;
    uint256 public MarketingSellFee = 3;
    uint256 public buyBackSellFee = 3;
    uint256 public weeklyLotterySellFee = 2;
    uint256 public DAOWalletSellFee = 2;

    uint256 public totalSellFees = TRXRewardsSellFee.add(LiquiditySellFee).add(MarketingSellFee).add(buyBackSellFee).add(weeklyLotterySellFee).add(DAOWalletSellFee);

    address payable public _marketingWallet = payable(0x7d9C878542087Fd014aF8460c173D6F7D4B43718);
    address payable public _buyBackWallet = payable(0xa70bc74913CAA4a4c144cD1a26CB92a4cBacc0E2);
    address payable public _lotteryWallet = payable(0x4b632Cc09EDD338F2126cDd60807A52Ca81Ed020);
    address payable public _DAOWallet = payable(0xa93203122825c7A100bBaA2C5FfE89b30F1FE36e);
    
    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

     // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;


    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;
    
    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapETHForTokens(
        uint256 amountIn,
        address[] path
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
        uint256 tokensSwapped,
        uint256 amount
    );

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor() public ERC20("SUPERTRX", "SPTRX") {

        dividendTracker = new TRXDividendTracker();


        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(deadWallet);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(_marketingWallet, true);
        excludeFromFees(_buyBackWallet, true);
        excludeFromFees(_lotteryWallet, true);
        excludeFromFees(_DAOWallet, true);
        excludeFromFees(address(this), true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 1000000000000 * (10**18));
    }

    receive() external payable {

    }

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "SPTRX: The dividend tracker already has that address");

        TRXDividendTracker newDividendTracker = TRXDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "SPTRX: The new dividend tracker must be owned by the SPTRX token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "SPTRX: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "SPTRX: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }
    
    function SetSwapTokensAtAmount(uint256 _newAmount) external onlyOwner {
  	    swapTokensAtAmount = _newAmount * (10**18);
  	}

    function setMarketingWallet(address payable wallet) external onlyOwner{
        _marketingWallet = wallet;
    }

    function setBuyBackWallet(address payable wallet) external onlyOwner{
        _buyBackWallet = wallet;
    }

    function setLotteryWallet(address payable wallet) external onlyOwner{
        _lotteryWallet = wallet;
    }

    function setDAOWallet(address payable wallet) external onlyOwner{
        _DAOWallet = wallet;
    }

    function setMaxWalletTokend(uint256 _maxToken) external onlyOwner {
  	    maxWalletToken = _maxToken * (10**18);
  	}

    function setMaxBuyTxAmount(uint256 maxBuyTxAmount) external onlyOwner() {
        require(maxBuyTxAmount > 0, "transaction amount must be greater than zero");
        _maxBuyTxAmount = maxBuyTxAmount * (10**18);
    }
    
    function setMaxSellTxAmount(uint256 maxSellTxAmount) external onlyOwner() {
        require(maxSellTxAmount > 0, "transaction amount must be greater than zero");
        _maxSellTxAmount = maxSellTxAmount * (10**18);
    }

    function updateBuyFees(uint256 rewardFee, uint256 _liquidityFee, uint256 _marketingFee, uint256 _buybackFee, uint256 _lotteryFee, uint256 _DAOFee) external onlyOwner{
        TRXRewardsBuyFee = rewardFee;
        LiquidityBuyFee = _liquidityFee;
        MarketingBuyFee = _marketingFee;
        buyBackBuyFee = _buybackFee;
        weeklyLotteryBuyFee = _lotteryFee;
        DAOWalletBuyFee = _DAOFee;
        totalBuyFees = TRXRewardsBuyFee.add(LiquidityBuyFee).add(MarketingBuyFee).add(buyBackBuyFee).add(weeklyLotteryBuyFee).add(DAOWalletBuyFee);
    }

    function updateSellFees(uint256 rewardFee, uint256 _liquidityFee, uint256 _marketingFee, uint256 _buybackFee, uint256 _lotteryFee, uint256 _DAOFee) external onlyOwner{
        TRXRewardsSellFee = rewardFee;
        LiquiditySellFee = _liquidityFee;
        MarketingSellFee = _marketingFee;
        buyBackSellFee = _buybackFee;
        weeklyLotterySellFee = _lotteryFee;
        DAOWalletSellFee = _DAOFee;
        totalSellFees = TRXRewardsSellFee.add(LiquiditySellFee).add(MarketingSellFee).add(buyBackSellFee).add(weeklyLotterySellFee).add(DAOWalletSellFee);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "SPTRX: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "SPTRX: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "SPTRX: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "SPTRX: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) public view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function excludeFromDividends(address account) external onlyOwner{
        dividendTracker.excludeFromDividends(account);
    }

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
        dividendTracker.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
       
        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        bool excludedAccount = _isExcludedFromFees[from] || _isExcludedFromFees[to];
        
        if (uniswapV2Pair==from && !excludedAccount) {
            require(amount <= _maxBuyTxAmount,"Transfer amount exceeds the maxTxAmount.");
            
            uint256 contractBalanceRecepient = balanceOf(to);
            require(contractBalanceRecepient + amount <= maxWalletToken,"Exceeds maximum wallet token amount.");
        }

        if (uniswapV2Pair==to && !excludedAccount) {
            require(amount <= _maxSellTxAmount,"Transfer amount exceeds the maxTxAmount.");
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if(
            canSwap &&
            !swapping &&
            automatedMarketMakerPairs[to] &&
            !excludedAccount
        ) {
               
            swapping = true;

            contractTokenBalance = swapTokensAtAmount;

            uint256 swapTokens = contractTokenBalance.mul(LiquiditySellFee).div(totalSellFees);
            swapAndLiquify(swapTokens);

            uint256 marketingTokens = contractTokenBalance.mul(MarketingSellFee).div(totalSellFees);
            swapTokensForEth(marketingTokens, _marketingWallet);

            uint256 buybackTokens = contractTokenBalance.mul(buyBackSellFee).div(totalSellFees);
            swapTokensForEth(buybackTokens, _buyBackWallet);

            uint256 lotteryTokens = contractTokenBalance.mul(weeklyLotterySellFee).div(totalSellFees);
            swapTokensForEth(lotteryTokens, _lotteryWallet);

            uint256 DAOTokens = contractTokenBalance.mul(DAOWalletSellFee).div(totalSellFees);
            swapTokensForEth(DAOTokens, _DAOWallet);
                
            uint256 sellTokens = contractTokenBalance.mul(TRXRewardsSellFee).div(totalSellFees);
            swapAndSendDividends(sellTokens);

            swapping = false;
            
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {

            uint256 fees = amount.mul(totalBuyFees).div(100);

            if(automatedMarketMakerPairs[to]) {
                fees = amount.mul(totalSellFees).div(100);
            }
            
            amount = amount.sub(fees);
            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            }
            catch {

            }
        }
    }

    function swapAndLiquify(uint256 tokens) private {
       // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half, address(this)); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount, address _to) private {

        
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        if(allowance(address(this), address(uniswapV2Router)) < tokenAmount) {
          _approve(address(this), address(uniswapV2Router), ~uint256(0));
        }

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            _to,
            block.timestamp
        );
        
    }
    
    function swapTokensForTRX(uint256 tokenAmount) private {

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = TRX;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

    }

    function swapAndSendDividends(uint256 tokens) private{
        swapTokensForTRX(tokens);
        uint256 dividends = IERC20(TRX).balanceOf(address(this));
        bool success = IERC20(TRX).transfer(address(dividendTracker), dividends);

        if (success) {
            dividendTracker.distributeTRXDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }
}

contract TRXDividendTracker is Ownable, DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public immutable minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() public DividendPayingToken("SPTRX_Dividen_Tracker", "SPTRX_Dividend_Tracker") {
        claimWait = 3600;
        minimumTokenBalanceForDividends = 10000 * (10**18); //must hold 10000+ tokens
    }

    function _transfer(address, address, uint256) internal override {
        require(false, "SPTRX_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public override {
        require(false, "SPTRX_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main SPTRX contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
        require(!excludedFromDividends[account]);
        excludedFromDividends[account] = true;

        _setBalance(account, 0);
        tokenHoldersMap.remove(account);

        emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "SPTRX_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "SPTRX_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }



    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
        if(lastClaimTime > block.timestamp)  {
            return false;
        }

        return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
        if(excludedFromDividends[account]) {
            return;
        }

        if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
            tokenHoldersMap.set(account, newBalance);
        }
        else {
            _setBalance(account, 0);
            tokenHoldersMap.remove(account);
        }

        processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
        uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

        if(numberOfTokenHolders == 0) {
            return (0, 0, lastProcessedIndex);
        }

        uint256 _lastProcessedIndex = lastProcessedIndex;

        uint256 gasUsed = 0;

        uint256 gasLeft = gasleft();

        uint256 iterations = 0;
        uint256 claims = 0;

        while(gasUsed < gas && iterations < numberOfTokenHolders) {
            _lastProcessedIndex++;

            if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
                _lastProcessedIndex = 0;
            }

            address account = tokenHoldersMap.keys[_lastProcessedIndex];

            if(canAutoClaim(lastClaimTimes[account])) {
                if(processAccount(payable(account), true)) {
                    claims++;
                }
            }

            iterations++;

            uint256 newGasLeft = gasleft();

            if(gasLeft > newGasLeft) {
                gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
            }

            gasLeft = newGasLeft;
        }

        lastProcessedIndex = _lastProcessedIndex;

        return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

        if(amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
            return true;
        }

        return false;
    }
}
