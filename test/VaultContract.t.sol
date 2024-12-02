// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/VaultContract.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

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

contract MockGauge is IGauge {
    MockERC20 public oBEROToken;

    constructor(MockERC20 _oBEROToken) {
        oBEROToken = _oBEROToken;
    }

    function getReward(address account) external override {
        oBEROToken.mint(account, 500 ether);
    }
}

contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        return params.amountIn / 2; // Mock 50% output
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

    address public owner = address(this);

    function setUp() public {
        islandToken = new MockERC20("IslandToken", "ISL");
        oBEROToken = new MockERC20("oBEROToken", "OBR");
        nectToken = new MockERC20("NectToken", "NECT");
        honeyToken = new MockERC20("HoneyToken", "HONEY");

        plugin = new MockPlugin();
        gauge = new MockGauge(oBEROToken);
        swapRouter = new MockSwapRouter();

        vault = new VaultContract(
            islandToken,
            oBEROToken,
            nectToken,
            honeyToken,
            plugin,
            gauge,
            swapRouter
            );

        islandToken.mint(owner, 1000 ether);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 ether;
        islandToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        assertEq(islandToken.balanceOf(address(vault)), depositAmount);
    }

    function testHarvestRewards() public {
        vault.harvestRewards();
        assertEq(oBEROToken.balanceOf(address(vault)), 500 ether);
    }

    function testSwapTokens() public {
        oBEROToken.mint(address(vault), 100 ether);
        uint256 nectOut = vault.swapTokens(address(oBEROToken), address(nectToken), 100 ether, 3000);
        assertEq(nectOut, 50 ether);
    }
}
