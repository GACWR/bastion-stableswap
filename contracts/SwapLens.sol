// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./SwapFlashLoan.sol";

interface IMiniChefV2 {
    function userInfo(uint256, address) external view returns (uint256, int256);

    function lpToken(uint256) external view returns (ILPToken);

    function saddlePerSecond() external view returns (uint256);

    function pendingSaddle(uint256 _pid, address _user)
        external
        view
        returns (uint256 pending);
}

interface Oracle {
    function getUnderlyingPrice(address) external view returns (uint256);
}

interface Comptroller {
    function oracle() external view returns (Oracle);
}

interface CToken {
    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function comptroller() external view returns (Comptroller);
}

interface ILPToken {
    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}

contract SwapLens {
    struct CTokenData {
        address addrs;
        uint256 allowance;
        uint256 balanceOf;
        uint256 poolBalanceOf;
        uint256 exchangeRateStored;
        uint256 underlyingPrice;
    }
    struct SwapDataCToken {
        uint256 swapFee;
        uint256 adminFee;
        ILPToken lpToken;
        uint256 Amplification;
        uint256 virtualPrice;
        uint256 balanceOf;
        uint256 allowance;
        uint256 totalSupply;
        CTokenData[] pooledCToken;
    }
    struct TokenData {
        address addrs;
        uint256 allowance;
        uint256 balanceOf;
        uint256 poolBalanceOf;
    }
    struct SwapDataToken {
        uint256 swapFee;
        uint256 adminFee;
        ILPToken lpToken;
        uint256 Amplification;
        uint256 virtualPrice;
        uint256 balanceOf;
        uint256 allowance;
        uint256 totalSupply;
        TokenData[] pooledToken;
    }

    function getSwapDataCToken(
        Swap swap,
        uint8 pooledCount,
        address account
    ) public view returns (SwapDataCToken memory) {
        SwapDataCToken memory swapDataCToken;

        (, , , , uint256 swapFee, uint256 adminFee, LPToken lp) = swap
            .swapStorage();
        ILPToken lpToken = ILPToken(address(lp));
        swapDataCToken.swapFee = swapFee;
        swapDataCToken.adminFee = adminFee;
        swapDataCToken.lpToken = lpToken;
        swapDataCToken.Amplification = swap.getA();
        swapDataCToken.virtualPrice = swap.getVirtualPrice();
        swapDataCToken.balanceOf = lpToken.balanceOf(account);
        swapDataCToken.allowance = lpToken.allowance(account, address(swap));
        swapDataCToken.totalSupply = lpToken.totalSupply();

        CTokenData[] memory cTokensData = new CTokenData[](pooledCount);
        for (uint8 i = 0; i < pooledCount; i++) {
            CTokenData memory cTokenData = cTokensData[i];
            CToken cToken = CToken(address(swap.getToken(i)));

            cTokenData.addrs = address(cToken);
            cTokenData.allowance = cToken.allowance(account, address(swap));
            cTokenData.balanceOf = cToken.balanceOf(account);
            cTokenData.poolBalanceOf = cToken.balanceOf(address(swap));
            cTokenData.exchangeRateStored = cToken.exchangeRateStored();

            cTokenData.underlyingPrice = cToken
                .comptroller()
                .oracle()
                .getUnderlyingPrice(address(cToken));
        }
        swapDataCToken.pooledCToken = cTokensData;

        return swapDataCToken;
    }

    function getSwapDataToken(
        Swap swap,
        uint8 pooledCount,
        address account
    ) public view returns (SwapDataToken memory) {
        SwapDataToken memory swapDataToken;

        (, , , , uint256 swapFee, uint256 adminFee, LPToken lp) = swap
            .swapStorage();
        ILPToken lpToken = ILPToken(address(lp));
        swapDataToken.swapFee = swapFee;
        swapDataToken.adminFee = adminFee;
        swapDataToken.lpToken = lpToken;
        swapDataToken.Amplification = swap.getA();
        swapDataToken.virtualPrice = swap.getVirtualPrice();
        swapDataToken.balanceOf = lpToken.balanceOf(account);
        swapDataToken.allowance = lpToken.allowance(account, address(swap));
        swapDataToken.totalSupply = lpToken.totalSupply();

        TokenData[] memory tokensData = new TokenData[](pooledCount);
        for (uint8 i = 0; i < pooledCount; i++) {
            TokenData memory tokenData = tokensData[i];
            IERC20 token = IERC20(address(swap.getToken(i)));

            tokenData.addrs = address(token);
            tokenData.allowance = token.allowance(account, address(swap));
            tokenData.balanceOf = token.balanceOf(account);
            tokenData.poolBalanceOf = token.balanceOf(address(swap));
        }
        swapDataToken.pooledToken = tokensData;

        return swapDataToken;
    }

    struct ChefMetaData {
        uint256 rewardPerSecond;
        uint256 totalStaked;
        uint256 amountStaked;
        int256 rewardDebt;
        uint256 allowance;
        uint256 pendingReward;
    }

    function getChefMetaData(
        IMiniChefV2 chef,
        uint8 pid,
        address account
    ) public view returns (ChefMetaData memory chefMetaData) {
        (uint256 amountStaked, int256 rewardDebt) = chef.userInfo(pid, account);
        chefMetaData.rewardPerSecond = chef.saddlePerSecond();
        chefMetaData.totalStaked = chef.lpToken(pid).balanceOf(address(chef));
        chefMetaData.amountStaked = amountStaked;
        chefMetaData.rewardDebt = rewardDebt;
        chefMetaData.allowance = chef.lpToken(pid).allowance(
            account,
            address(chef)
        );
        chefMetaData.pendingReward = chef.pendingSaddle(pid, account);
    }
}
