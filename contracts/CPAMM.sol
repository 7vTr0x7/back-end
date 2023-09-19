// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./TokenizedShares.sol";
import "./ERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract CPAMM is ReentrancyGuard {
    event LiquidityAdded(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares
    );
    event LiquidityRemoved(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 shares
    );

    event Swap(
        address indexed user,
        address indexed fromToken,
        address indexed toToken,
        uint256 amount,
        uint256 time
    );

    struct UserInfo {
        address owner;
        address token1;
        address token2;
        uint256 token1Amt;
        uint256 token2Amt;
        uint256 shares;
    }

    using SafeMath for uint256;

    mapping(address => UserInfo[]) private UserInfos;

    mapping(address => uint256) public reserves;

    uint public totalSupply;
    TokenizedShares public tokenizedSharesContract;

    function InIt(address _tokenizedSharesContract) public initializer {
        tokenizedSharesContract = TokenizedShares(
            payable(_tokenizedSharesContract)
        );
    }

    function _update(
        uint256 _reserve1,
        uint256 _reserve2,
        address token1Addr,
        address token2Addr
    ) private {
        reserves[token1Addr] = _reserve1;
        reserves[token2Addr] = _reserve2;
    }

    function _approve(address tokenAddress, uint256 amount) private {
        IERC20 token = ERC20(tokenAddress);
        token.approve(address(this), amount);
    }

    function _transferTokens(
        address tokenAddress,
        address recipient,
        uint256 amount
    ) private {
        IERC20 token = ERC20(tokenAddress);
        token.transfer(recipient, amount);
    }

    function getSwapAmount(
        uint256 _amountIn,
        uint256 _tokenInPrice,
        uint256 _tokenOutPrice,
        uint256 selectedFee
    )
        public
        view
        returns (uint256 tokenOutAmt, uint256 tokenInAmt, uint256 amountOut)
    {
        require(_amountIn > 0, "amtIn = 0");

        tokenInAmt = tokenizedSharesContract.get(_amountIn, _tokenInPrice);

        amountOut = (_amountIn * (10000 - selectedFee)) / 10000;

        tokenOutAmt = (tokenInAmt * _tokenInPrice) / _tokenOutPrice;

        tokenOutAmt = (tokenOutAmt * (10000 - selectedFee)) / 10000;
    }

    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 tokenInPrice,
        uint256 tokenOutPrice,
        uint256 exchangeRate,
        uint256 selectedFee
    ) external {
        require(amountIn > 0, "amtIn = 0");

        TokenizedShares.Share[] memory userShares = tokenizedSharesContract
            .getUserShares(msg.sender);

        for (uint256 i = 0; i < userShares.length; i++) {
            TokenizedShares.Share memory share = userShares[i];

            uint256 amount;

            if (tokenIn == share.tokenAddress) {
                amount =
                    (uint256(tokenInPrice) * uint256(share.buyAmount)) /
                    uint256(share.buyPrice);
            }

            if (tokenIn == share.tokenAddress && amountIn == amount) {
                handleSwap(
                    amountIn,
                    share,
                    tokenInPrice,
                    tokenOutPrice,
                    tokenOut,
                    selectedFee
                );

                tokenizedSharesContract.transferFees(
                    amountIn,
                    selectedFee,
                    exchangeRate
                );
            } else if (tokenIn == share.tokenAddress && amountIn < amount) {
                handlePartialSwap(
                    amountIn,
                    share,
                    tokenInPrice,
                    tokenOutPrice,
                    tokenOut,
                    selectedFee
                );

                tokenizedSharesContract.transferFees(
                    amountIn,
                    selectedFee,
                    exchangeRate
                );
            }
        }

        _update(
            ERC20(tokenIn).balanceOf(address(this)),
            ERC20(tokenOut).balanceOf(address(this)),
            tokenIn,
            tokenOut
        );
    }

    function handleSwap(
        uint256 amountIn,
        TokenizedShares.Share memory share,
        uint256 tokenInPrice,
        uint256 tokenOutPrice,
        address tokenOut,
        uint256 selectedFee
    ) private {
        (
            uint256 tokenOutAmt,
            uint256 tokenInAmt,
            uint256 amountOut
        ) = getSwapAmount(amountIn, tokenInPrice, tokenOutPrice, selectedFee);

        tokenizedSharesContract.AddUpdateShare(
            msg.sender,
            amountIn,
            amountOut,
            tokenInPrice,
            tokenOutPrice,
            share.tokenAddress,
            tokenOut
        );

        ERC20(share.tokenAddress).transferFrom(
            msg.sender,
            address(this),
            tokenInAmt
        );

        ERC20(tokenOut).transfer(msg.sender, tokenOutAmt);

        emit Swap(
            msg.sender,
            share.tokenAddress,
            tokenOut,
            amountOut,
            block.timestamp
        );
    }

    function handlePartialSwap(
        uint256 amountIn,
        TokenizedShares.Share memory share,
        uint256 tokenInPrice,
        uint256 tokenOutPrice,
        address tokenOut,
        uint256 selectedFee
    ) private {
        (
            uint256 tokenOutAmt,
            uint256 tokenInAmt,
            uint256 amountOut
        ) = getSwapAmount(amountIn, tokenInPrice, tokenOutPrice, selectedFee);

        tokenizedSharesContract.AddUpdateShare(
            msg.sender,
            amountIn,
            amountOut,
            tokenInPrice,
            tokenOutPrice,
            share.tokenAddress,
            tokenOut
        );

        ERC20(share.tokenAddress).transferFrom(
            msg.sender,
            address(this),
            tokenInAmt
        );

        ERC20(tokenOut).transfer(msg.sender, tokenOutAmt);

        emit Swap(
            msg.sender,
            share.tokenAddress,
            tokenOut,
            amountOut,
            block.timestamp
        );
    }

    function addLiquidity(
        uint256 _amount1,
        uint256 _amount2,
        address token1Addr,
        address token2Addr
    ) external returns (uint256 shares) {
        ERC20(token1Addr).transferFrom(msg.sender, address(this), _amount1);
        ERC20(token2Addr).transferFrom(msg.sender, address(this), _amount2);

        if (reserves[token1Addr] >= 0 || reserves[token2Addr] >= 0) {
            require(
                (reserves[token1Addr] >= 0 && reserves[token2Addr] >= 0) ||
                    (reserves[token1Addr] * _amount2 ==
                        reserves[token2Addr] * _amount1),
                "dy/dx != y/x"
            );
        }

        // Update the reserve values with the new amounts
        reserves[token1Addr] += _amount1;
        reserves[token2Addr] += _amount2;

        if (totalSupply == 0) {
            shares = _sqrt(_amount1 * _amount2);
        } else {
            if (reserves[token1Addr] == 0) {
                shares = (_amount2 * totalSupply) / reserves[token2Addr];
            } else if (reserves[token2Addr] == 0) {
                shares = (_amount1 * totalSupply) / reserves[token1Addr];
            } else {
                shares = _min(
                    (_amount1 * totalSupply) / reserves[token1Addr],
                    (_amount2 * totalSupply) / reserves[token2Addr]
                );
            }
        }

        UserInfo[] storage userInfo = UserInfos[msg.sender];

        // Check if the user added liquidity before
        bool addedLiquidityBefore = false;

        for (uint256 i = 0; i < userInfo.length; i++) {
            if (
                userInfo[i].token1 == token1Addr &&
                userInfo[i].token2 == token2Addr
            ) {
                userInfo[i].token1Amt += _amount1;
                userInfo[i].token2Amt += _amount2;
                userInfo[i].shares += shares;
                addedLiquidityBefore = true;

                break;
            }
        }

        // If the user didn't add liquidity before, create a new UserInfo entry
        if (!addedLiquidityBefore) {
            userInfo.push(
                UserInfo({
                    owner: msg.sender,
                    token1: token1Addr,
                    token2: token2Addr,
                    token1Amt: _amount1,
                    token2Amt: _amount2,
                    shares: shares
                })
            );
        }

        totalSupply += shares;

        _update(
            ERC20(token1Addr).balanceOf(address(this)),
            ERC20(token2Addr).balanceOf(address(this)),
            token1Addr,
            token2Addr
        );
    }

    function removeLiquidity(
        uint256 _shares,
        address token1Addr,
        address token2Addr
    ) external returns (uint256 amount1, uint256 amount2) {
        UserInfo[] storage userInfo = UserInfos[msg.sender];

        uint256 _index;

        for (uint256 i = 0; i < userInfo.length; i++) {
            if (
                userInfo[i].token1 == token1Addr &&
                userInfo[i].token2 == token2Addr
            ) {
                _index = i;

                break;
            }
        }

        require(_shares > 0, "Invalid shares amount");

        require(_index < userInfo.length, "Invalid index");

        UserInfo storage user = userInfo[_index];
        require(user.shares == _shares, "Invalid shares amount");

        uint256 bal1 = ERC20(token1Addr).balanceOf(address(this));
        uint256 bal2 = ERC20(token2Addr).balanceOf(address(this));

        amount1 = (_shares * bal1) / totalSupply;
        amount2 = (_shares * bal2) / totalSupply;

        require(amount1 > 0 && amount2 > 0, "amt1 or amt2 = 0");

        // Delete the user entry if shares match
        if (user.shares == _shares) {
            // Move the last element to the deleted position and reduce the array length
            delete UserInfos[msg.sender][_index];
        }

        totalSupply -= _shares;

        _update(bal1 - amount1, bal2 - amount2, token1Addr, token2Addr);
        ERC20(token1Addr).transfer(msg.sender, amount1);
        ERC20(token2Addr).transfer(msg.sender, amount2);
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }

    function getUserInfo(address user) public view returns (UserInfo[] memory) {
        UserInfo[] storage allInfo = UserInfos[user];
        uint256 count = 0;

        for (uint256 i = 0; i < allInfo.length; i++) {
            if (allInfo[i].owner == user) {
                count++;
            }
        }

        UserInfo[] memory ownedLiq = new UserInfo[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < allInfo.length; i++) {
            if (allInfo[i].owner == user) {
                ownedLiq[index] = allInfo[i];
                index++;
            }
        }

        return ownedLiq;
    }

    function getReseves(address token) external view returns (uint256) {
        return reserves[token];
    }
}
