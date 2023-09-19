// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LiquidityToken.sol";
import "./ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TokenizedShares is ReentrancyGuard {
    struct Share {
        address owner;
        address tokenAddress;
        uint256 buyAmount;
        uint256 buyPrice;
        uint256 tokenAmt;
    }

    using SafeMath for uint256;

    address public owner;
    address[] public owners;

    function initialize() public initializer {
        owner = msg.sender;
    }

    mapping(address => Share[]) public shareOwner;

    event ShareBought(
        address indexed buyer,
        uint256 buyAmount,
        uint buyPrice,
        uint256 weiAmount,
        uint256 time
    );
    event ShareSold(
        address indexed buyer,
        uint256 buyAmount,
        uint buyPrice,
        uint256 weiAmount,
        uint256 time
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    receive() external payable {}

    function buyShares(
        uint256 buyAmount,
        uint256 _currentPriceInUSD,
        uint256 exchangeRate,
        address tokenAddress
    ) external payable nonReentrant {
        require(buyAmount > 0, "Buy amount must be greater than zero");

        uint256 weiAmount = (uint256(buyAmount) * exchangeRate + uint256(50)) /
            uint256(100);

        require(msg.value >= weiAmount, " < weiAmount");

        Share[] storage shares = shareOwner[msg.sender];

        bool exist;
        uint256 index;

        for (uint256 i = 0; i < shares.length; i++) {
            if (shares[i].tokenAddress == tokenAddress) {
                exist = true;
                index = i;
            }
        }

        if (exist) {
            uint256 totalPayment = (uint256(_currentPriceInUSD) *
                uint256(shares[index].buyAmount)) /
                uint256(shares[index].buyPrice);

            uint256 buy = buyAmount + totalPayment;

            uint256 mintAmt = get(buyAmount, _currentPriceInUSD);

            shares[index].tokenAmt += mintAmt;
            shares[index].buyAmount = buy;
            shares[index].buyPrice = _currentPriceInUSD;

            ERC20(tokenAddress).mint(msg.sender, mintAmt);
        } else {
            uint256 mintAmt = get(buyAmount, _currentPriceInUSD);

            Share memory newShare = Share(
                msg.sender,
                tokenAddress,
                buyAmount,
                _currentPriceInUSD,
                mintAmt
            );
            shareOwner[msg.sender].push(newShare);
            ERC20(tokenAddress).mint(msg.sender, mintAmt);
        }

        // Refund any excess Ether back to the buyer
        if (msg.value > weiAmount) {
            uint256 refundAmount = msg.value - weiAmount;
            payable(msg.sender).transfer(refundAmount);
        }

        emit ShareBought(
            msg.sender,
            buyAmount,
            _currentPriceInUSD,
            weiAmount,
            block.timestamp
        );
    }

    function sellShares(
        uint256 sellAmount,
        uint256 _currentPriceInUSD,
        uint256 exchangeRate,
        uint256 selectedFee,
        address tokenAddress
    ) external nonReentrant {
        require(sellAmount > 0, "Sell amount must be greater than zero");

        Share[] storage shares = shareOwner[msg.sender];
        require(shares.length > 0, "No shares owned by the user");

        bool exist;
        uint256 index;

        require(index < shares.length, "Invalid share index");

        for (uint256 i = 0; i < shares.length; i++) {
            if (shares[i].tokenAddress == tokenAddress) {
                exist = true;
                index = i;
            }
        }

        require(exist, "not exist");

        uint256 totalPayment = (uint256(_currentPriceInUSD) *
            uint256(shares[index].buyAmount)) / uint256(shares[index].buyPrice);

        shares[index].buyAmount = totalPayment;

        require(totalPayment >= sellAmount, "Insufficient shares to sell");

        uint feesAmt = transferFees(sellAmount, selectedFee, exchangeRate);

        uint payment = sellAmount - feesAmt;

        uint256 totalPaymentInWei = (uint256(payment) *
            exchangeRate +
            uint256(50)) / uint256(100);

        uint256 burnAmt = get(sellAmount, _currentPriceInUSD);

        ERC20(tokenAddress).burn(msg.sender, burnAmt);

        // Update the share and the user's balances
        if (sellAmount == shares[index].buyAmount) {
            // If selling all shares in this entry, delete the share entry
            delete shares[index];
            if (shares.length > 1) {
                shares[index] = shares[shares.length - 1];
            }
            shares.pop();
        } else {
            // If selling a portion of shares in this entry, update the remaining shares
            shares[index].buyAmount -= sellAmount;
            shares[index].buyPrice = _currentPriceInUSD;
            shares[index].tokenAmt -= burnAmt;
        }

        // Transfer the payment to the seller
        (bool paymentSuccess, ) = payable(msg.sender).call{
            value: totalPaymentInWei
        }("");
        require(paymentSuccess, "Payment failed");

        emit ShareSold(
            msg.sender,
            sellAmount,
            _currentPriceInUSD,
            totalPaymentInWei,
            block.timestamp
        );
    }

    function requiredEth(
        uint256 amount,
        uint256 exchangeRate
    ) public pure returns (uint256 weiAmount) {
        weiAmount =
            (uint256(amount) * exchangeRate + uint256(50)) /
            uint256(100);
    }

    function getUserShares(address user) public view returns (Share[] memory) {
        Share[] storage allShares = shareOwner[user];
        uint256 ownedSharesCount = 0;

        for (uint256 i = 0; i < allShares.length; i++) {
            if (allShares[i].owner == user) {
                ownedSharesCount++;
            }
        }

        Share[] memory ownedShares = new Share[](ownedSharesCount);
        uint256 ownedSharesIndex = 0;

        for (uint256 i = 0; i < allShares.length; i++) {
            if (allShares[i].owner == user) {
                ownedShares[ownedSharesIndex] = allShares[i];
                ownedSharesIndex++;
            }
        }

        return ownedShares;
    }

    function AddUpdateShare(
        address tokenOwner,
        uint256 amtIn,
        uint256 amtOut,
        uint256 tokenInPrice,
        uint256 tokenOutPrice,
        address tokenIn,
        address tokenOut
    ) external {
        require(tokenOwner != address(0), "Invalid token owner");
        require(amtOut > 0, "Buy amount must be greater than zero");
        require(amtIn > 0, "Buy amount must be greater than zero");

        require(tokenInPrice > 0, "Buy price must be greater than zero");
        require(tokenOutPrice > 0, "Buy price must be greater than zero");

        require(tokenIn != address(0), "Invalid token address");

        require(tokenOut != address(0), "Invalid token address");

        Share[] storage shares = shareOwner[tokenOwner];

        uint tokenInAmt = get(amtIn, tokenInPrice);
        uint tokenOutAmt = get(amtOut, tokenOutPrice);

        bool exist;

        for (uint256 i = 0; i < shares.length; i++) {
            if (shares[i].tokenAddress == tokenOut) {
                exist = true;
                // Update the existing tokenOut entry

                (shares[i].buyAmount) = (shares[i].buyAmount) + (amtOut);
                shares[i].buyPrice = tokenOutPrice;

                (shares[i].tokenAmt) = (shares[i].tokenAmt) + (tokenOutAmt);
                break;
            }
        }

        if (!exist) {
            Share memory newShare = Share(
                tokenOwner,
                tokenOut,
                amtOut,
                tokenOutPrice,
                tokenOutAmt
            );
            shares.push(newShare);
        }

        for (uint256 i = 0; i < shares.length; i++) {
            uint256 amount = (uint256(tokenInPrice) *
                uint256(shares[i].buyAmount)) / uint256(shares[i].buyPrice);

            if (shares[i].tokenAddress == tokenIn) {
                if (amount == amtIn) {
                    if (i < shares.length - 1) {
                        shares[i] = shares[shares.length - 1];
                    }
                    shares.pop();
                } else {
                    (shares[i].buyAmount) = amount - amtIn;

                    shares[i].buyPrice = tokenInPrice;
                    (shares[i].tokenAmt) = (shares[i].tokenAmt) - (tokenInAmt);
                }
                break;
            }
        }
    }

    function get(
        uint256 _amountIn,
        uint price
    ) public pure returns (uint256 tokenInAmt) {
        uint256 amt = _amountIn * 10 ** 18;
        uint256 Amt = price * 10 ** 18;

        uint256 decimals = 10 ** 18;
        tokenInAmt = amt.mul(decimals).div(Amt);
    }

    function setOwners(address _owner) external onlyOwner {
        // Check if the owner address doesn't already exist in the array
        for (uint256 i = 0; i < owners.length; i++) {
            require(owners[i] != _owner, "Owner already exists");
        }

        owners.push(_owner);
    }

    function getOwners() external view onlyOwner returns (address[] memory) {
        return owners;
    }

    function removeOwners(address _owner) external onlyOwner {
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
            }
        }
    }

    function transferFees(
        uint256 amountIn,
        uint256 selectedFee,
        uint256 exchangeRate
    ) public returns (uint amt) {
        amt = (amountIn * (10000 - selectedFee)) / 10000;
        amt = amountIn - amt;

        uint totalPaymentInWei = (uint256(amt) * exchangeRate + uint256(50)) /
            uint256(100);

        // Calculate the payment per owner
        uint paymentPerOwner = totalPaymentInWei / owners.length;

        for (uint256 i = 0; i < owners.length; i++) {
            (bool paymentSuccess, ) = payable(owners[i]).call{
                value: paymentPerOwner
            }("");
            require(paymentSuccess, "Payment failed");
        }
    }

    function transferFundsToOwner() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Contract balance is zero");
        payable(owner).transfer(contractBalance);
    }
}
