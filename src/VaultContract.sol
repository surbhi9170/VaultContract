// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPlugin {
    function depositFor(address account, uint256 amount) external;
    function withdrawTo(address account, uint256 amount) external;
    function claimAndDistribute() external;
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IGauge {
    function getReward(address account) external;  // Function to claim rewards (oBERO)
}

interface IKodiakRouter {
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

contract VaultContract is Ownable, ReentrancyGuard {
    IERC20 public immutable islandToken;  // Honey-Nect LP Token
    IERC20 public immutable oBEROToken;  // Reward token (oBERO)
    IERC20 public immutable nectToken;   // NECT Token
    IERC20 public immutable honeyToken;  // HONEY Token

    IPlugin public immutable plugin;      // Plugin contract
    IGauge public immutable gauge;        // Gauge contract
    ISwapRouter public immutable swapRouter; // Kodiak Swap Router
    IKodiakRouter public immutable router; // Kodiak Router

    constructor(
        IERC20 _islandToken,
        IERC20 _oBEROToken,
        IERC20 _nectToken,
        IERC20 _honeyToken,
        IPlugin _plugin,
        IGauge _gauge,
        ISwapRouter _swapRouter,
        IKodiakRouter _router
    ) Ownable(msg.sender) {
        islandToken = _islandToken;
        oBEROToken = _oBEROToken;
        nectToken = _nectToken;
        honeyToken = _honeyToken;
        plugin = _plugin;
        gauge = _gauge;
        swapRouter = _swapRouter;
        router = _router;

        // Approve Plugin for staking
        _islandToken.approve(address(_plugin), type(uint256).max);
    }

    /**
     * @dev Deposit an amount into the vault.
     * @param amount The amount of Island token (Honey-Nect LP Token) to deposit.
     */
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        islandToken.transferFrom(msg.sender, address(this), amount);
        plugin.depositFor(address(this), amount);
    }

    /**
     * @dev Harvest rewards by claiming oBERO from the Gauge contract.
     */
    function harvestRewards() public nonReentrant onlyOwner {
        // Claim rewards (oBERO)
        gauge.getReward(address(this));
        uint256 rewardBalance = oBEROToken.balanceOf(address(this));
        require(rewardBalance > 0, "No rewards to harvest");
    }

    /**
     * @dev Swap oBERO tokens for NECT or HONEY using exactInputSingle.
     */
    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint24 fee
    ) public returns (uint256 amountOut) {
        require(amount > 0, "Amount must be greater than 0");
        require(tokenIn != address(0) && tokenOut != address(0), "Invalid token addresses");

        // Approve the Swap Router to spend oBERO
        IERC20(tokenIn).approve(address(swapRouter), amount);

        // Define the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp + 300, // 5-minute deadline
            amountIn: amount,
            amountOutMinimum: 1, // Accept any amount greater than 0
            sqrtPriceLimitX96: 0 // No price limit
        });

        // Execute the swap
        amountOut = swapRouter.exactInputSingle(params);
    }

    /**
     * @dev Swap half of the harvested oBERO tokens for NECT.
     */
    function swapOBEROForNect(uint256 amount, uint256 beraAmount) public payable onlyOwner returns (uint256 nectReceived) {
        nectReceived = swapTokens(address(oBEROToken), address(nectToken), amount, 3000); // 0.3% fee
    }

    /**
     * @dev Swap the remaining harvested oBERO tokens for HONEY.
     */
    function swapOBEROForHoney(uint256 amount, uint256 beraAmount) public payable onlyOwner returns (uint256 honeyReceived) {
        honeyReceived = swapTokens(address(oBEROToken), address(honeyToken), amount, 3000); // 0.3% fee
    }

    /**
     * @dev Add liquidity to the NECT/HONEY pool using Kodiak Router.
     */
    // function addLiquidityToPool(uint256 nectAmount, uint256 honeyAmount) public nonReentrant onlyOwner returns (uint256 lpTokensReceived) {
    //     nectToken.approve(address(router), nectAmount);
    //     honeyToken.approve(address(router), honeyAmount);
    //     (,, lpTokensReceived) = router.addLiquidity(
    //         address(nectToken),
    //         address(honeyToken),
    //         nectAmount,
    //         honeyAmount,
    //         0,
    //         0,
    //         address(this),
    //         block.timestamp
    //     );
    //     return lpTokensReceived;
    // }

    /**
     * @dev Deposit the LP tokens back into the Plugin contract (Beradrome farm).
     */
    // function depositLPtokensToPlugin(uint256 lpAmount) public nonReentrant onlyOwner {
    //     require(lpAmount > 0, "Amount must be greater than 0");
    //     plugin.depositFor(address(this), lpAmount);
    // }

    /**
     * @dev Complete harvest and compound process by calling each step.
     */
    function harvestAndCompound(uint256 beraForNect, uint256 beraForHoney) external payable nonReentrant onlyOwner {
        // Step 1: Harvest rewards
        harvestRewards();

        uint256 rewardBalance = oBEROToken.balanceOf(address(this));
        uint256 halfReward = rewardBalance / 2;

        // Step 2: Swap half of oBERO for NECT
        uint256 nectReceived = swapOBEROForNect(halfReward,beraForNect);

        // Step 3: Swap the remaining oBERO for HONEY
        uint256 honeyReceived = swapOBEROForHoney(rewardBalance - halfReward,beraForHoney);

    }
}
