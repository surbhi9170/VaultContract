// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/VaultContract.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 Token
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Plugin
contract MockPlugin is IPlugin {
    function depositFor(address account, uint256 amount) external override {}
    function withdrawTo(address account, uint256 amount) external override {}
    function claimAndDistribute() external override {}
    function balanceOf(address account) external view override returns (uint256) {
        return 0;
    }
    function totalSupply() external view override returns (uint256) {
        return 0;
    }
}

// Mock Gauge
contract MockGauge is IGauge {
    function getReward(address account) external override {}
}

// Mock Swap Router
contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params)
    external
    payable
    returns (uint256 amountOut)
{
    // Mock behavior: return a fixed amount
    return params.amountIn; // Just returning the input amount as a mock
}

}

// Mock Kodiak Router (Optional)
contract MockKodiakRouter is IKodiakRouter {
    function addLiquidity(
        address,
        address,
        uint,
        uint,
        uint,
        uint,
        address,
        uint
    ) external pure override returns (uint, uint, uint liquidity) {
        return (0, 0, 100 ether); // Mock liquidity addition
    }
}

contract VaultContractTest is Test {
    VaultContract public vault;
    MockERC20 public islandToken;
    MockERC20 public oBEROToken;
    MockERC20 public nectToken;
    MockERC20 public honeyToken;
    MockPlugin public plugin;
    MockGauge public gauge;
    MockSwapRouter public swapRouter;
    MockKodiakRouter public router;

    address public owner = address(this);
    address public user = address(0x123);

    function setUp() public {
        // Deploy mock tokens
        islandToken = new MockERC20("IslandToken", "ISL");
        oBEROToken = new MockERC20("oBEROToken", "OBR");
        nectToken = new MockERC20("NectToken", "NECT");
        honeyToken = new MockERC20("HoneyToken", "HONEY");

        // Deploy mock dependencies
        plugin = new MockPlugin();
        gauge = new MockGauge();
        swapRouter = new MockSwapRouter();
        router = new MockKodiakRouter();

        // Deploy the VaultContract
        vault = new VaultContract(
            islandToken,
            oBEROToken,
            nectToken,
            honeyToken,
            plugin,
            gauge,
            swapRouter,
            router
        );

        // Mint tokens to user for testing
        islandToken.mint(user, 1000 ether);
        oBEROToken.mint(address(gauge), 500 ether); // Mock rewards
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;

        vm.startPrank(user);
        islandToken.approve(address(vault), depositAmount);

        vault.deposit(depositAmount);

        assertEq(islandToken.balanceOf(address(vault)), depositAmount, "Vault balance mismatch");
        vm.stopPrank();
    }

    function testHarvestRewards() public {
        vm.prank(owner);
        vault.harvestRewards();

        uint256 rewardBalance = oBEROToken.balanceOf(address(vault));
        assertEq(rewardBalance, 500 ether, "Harvested rewards balance mismatch");
    }

    function testSwapTokens() public {
        uint256 swapAmount = 100 ether;

        // Mint oBERO tokens to Vault for swapping
        oBEROToken.mint(address(vault), swapAmount);

        // Perform the token swap
        vm.prank(owner);
        uint256 nectOut = vault.swapTokens(address(oBEROToken), address(nectToken), swapAmount, 3000);

        assertEq(nectOut, swapAmount / 2, "Swap output mismatch");
    }

    function testHarvestAndCompound() public {
        uint256 beraForNect = 100 ether;
        uint256 beraForHoney = 100 ether;

        // Mint rewards
        oBEROToken.mint(address(vault), 500 ether);

        // Call harvestAndCompound
        vm.prank(owner);
        vault.harvestAndCompound(beraForNect, beraForHoney);

        // Verify the balances after swap
        uint256 nectBalance = nectToken.balanceOf(address(vault));
        uint256 honeyBalance = honeyToken.balanceOf(address(vault));

        assertGt(nectBalance, 0, "NECT balance mismatch");
        assertGt(honeyBalance, 0, "HONEY balance mismatch");
    }
}
