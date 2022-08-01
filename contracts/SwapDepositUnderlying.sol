// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./Swap.sol";

interface CErc20 is IERC20 {
    function comptroller() external returns (address);

    function underlying() external returns (address);

    function mint(uint256 amount) external returns (uint256);

    function redeem(uint256 amount) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);
}

/**
 * @title Contract that help swap and deposit underlying into CToken Stableswap
 * @author bastionprotocol
 * @notice Swap and deposit underlying into CToken Stableswap
 * @dev addLiquidity and swapUnderying parameters should be similar to Swap
 */
contract SwapDepositUnderlying is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public swap;

    uint256 public numPooledToken;

    /**
     * @notice Construct a new money market
     * @param swap_ address of swap to deposit to
     * @param numPooledToken_ number of tokens in swap's pool
     */
    constructor(address swap_, uint256 numPooledToken_) public {
        swap = swap_;
        numPooledToken = numPooledToken_;
    }

    /**
     * @notice A simple method to convert amount of underlying
     * to amount in cToken and pass to calculateTokenAmount
     *
     * @dev This shouldn't be used outside frontends for user estimates.
     *
     * @param amounts an array of token amounts to deposit or withdrawal,
     * corresponding to pooledTokens. The amount should be in each
     * pooled underlying token's native precision. If a token charges a fee on transfers,
     * use the amount that gets transferred after the fee.
     * @param deposit whether this is a deposit or a withdrawal
     * @return if deposit was true, total amount of lp token that will be minted and if
     * deposit was false, total amount of lp token that will be burned
     */
    function calculateTokenAmount(uint256[] calldata amounts, bool deposit)
        external
        view
        returns (uint256)
    {
        uint256[] memory c_amounts = new uint256[](numPooledToken);
        for (uint8 i = 0; i < numPooledToken; i++) {
            uint256 amount = amounts[i];
            address ctoken = address(Swap(swap).getToken(i));
            uint256 exchangeRate = CErc20(ctoken).exchangeRateStored();
            c_amounts[i] = amount.mul(1e18).div(exchangeRate);
        }
        uint256 tokenAmount = Swap(swap).calculateTokenAmount(c_amounts, deposit);

        return tokenAmount;
    }

    /**
     * @notice deposit underlying to cToken market and add to stableswap Liquidity
     * @param amounts the amounts of each token to add, in their native precision
     * @param minToMint the minimum LP tokens adding this amount of liquidity
     * should mint, otherwise revert. Handy for front-running mitigation
     * @param deadline latest timestamp to accept this transaction
     * @return amount of LP token user minted and received
     */
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external nonReentrant returns (uint256) {
        uint256[] memory c_amounts = new uint256[](numPooledToken);
        for (uint8 i = 0; i < numPooledToken; i++) {
            uint256 amount = amounts[i];
            if (amount > 0) {
                address ctoken = address(Swap(swap).getToken(i));
                address token = CErc20(ctoken).underlying();
                IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
                IERC20(token).safeIncreaseAllowance(ctoken, amount);
                require(CErc20(ctoken).mint(amount) == 0, "Mint Failed");

                uint256 ctokenBalance = CErc20(ctoken).balanceOf(address(this));
                IERC20(ctoken).safeIncreaseAllowance(swap, ctokenBalance);
                c_amounts[i] = ctokenBalance;
            }
        }

        uint256 lpBalance = Swap(swap).addLiquidity(c_amounts, minToMint, deadline);
        (, , , , , , LPToken lptoken) = Swap(swap).swapStorage();

        lptoken.transfer(msg.sender, lpBalance);

        return lpBalance;
    }

    /**
     * @notice SwapFromUnderlying underlying of one of the two tokens using this pool
     * @param tokenIndexFrom the token with underlying that the user wants to swap from
     * @param tokenIndexTo the token the user wants to swap to
     * @param dx the amount of token's underlying the user wants to swap from
     * @param minDy the min amount the user would like to receive, or revert.
     * @param deadline latest timestamp to accept this transaction
     */
    function swapFromUnderlying(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx,
        uint256 minDy,
        uint256 deadline
    ) external virtual nonReentrant returns (uint256) {
        address cTokenFrom = address(Swap(swap).getToken(tokenIndexFrom));
        address cTokenTo = address(Swap(swap).getToken(tokenIndexTo));

        address underlyingFrom = CErc20(cTokenFrom).underlying();
        IERC20(underlyingFrom).safeTransferFrom(msg.sender, address(this), dx);
        IERC20(underlyingFrom).safeIncreaseAllowance(cTokenFrom, dx);
        require(CErc20(cTokenFrom).mint(dx) == 0, "Mint Failed");

        uint256 cDx = CErc20(cTokenFrom).balanceOf(address(this));
        CErc20(cTokenFrom).approve(swap, cDx);

        Swap(swap).swap(tokenIndexFrom, tokenIndexTo, cDx, 0, deadline);

        uint256 redeemAmount = CErc20(cTokenTo).balanceOf(address(this));
        require(CErc20(cTokenTo).redeem(redeemAmount) == 0, "Redeem Failed");

        address underlyingTo = CErc20(cTokenTo).underlying();
        uint256 underlyingDy = IERC20(underlyingTo).balanceOf(address(this));

        require(underlyingDy >= minDy, "!minDy");

        IERC20(underlyingTo).safeTransfer(msg.sender, underlyingDy);

        return underlyingDy;
    }

    /**
     * @notice Calculate amount of tokens you receive on swap from underlying
     * @param tokenIndexFrom the token the user wants to sell
     * @param tokenIndexTo the token the user wants to buy
     * @param dx the amount of tokens the user wants to sell. If the token charges
     * a fee on transfers, use the amount that gets transferred after the fee.
     * @return amount of tokens the user will receive
     */
    function calculateSwapFromUnderlying(
        uint8 tokenIndexFrom,
        uint8 tokenIndexTo,
        uint256 dx
    ) external view virtual returns (uint256) {
        address cTokenFrom = address(Swap(swap).getToken(tokenIndexFrom));
        uint256 cDx = dx.mul(1e18).div(CErc20(cTokenFrom).exchangeRateStored());

        address cTokenTo = address(Swap(swap).getToken(tokenIndexTo));

        return
            Swap(swap)
                .calculateSwap(tokenIndexFrom, tokenIndexTo, cDx)
                .mul(CErc20(cTokenTo).exchangeRateStored())
                .div(1e18);
    }
}
