// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { DisputeGameFactory_Init } from "test/dispute/DisputeGameFactory.t.sol";
import { DisputeGameFactory } from "src/dispute/DisputeGameFactory.sol";
import { FaultDisputeGame } from "src/dispute/FaultDisputeGame.sol";
import { PreimageOracle } from "src/cannon/PreimageOracle.sol";

import "src/libraries/DisputeTypes.sol";
import "src/libraries/DisputeErrors.sol";
import { LibClock } from "src/dispute/lib/LibUDT.sol";
import { LibPosition } from "src/dispute/lib/LibPosition.sol";
import { IPreimageOracle } from "src/dispute/interfaces/IBigStepper.sol";
import { AlphabetVM } from "test/mocks/AlphabetVM.sol";

import { DisputeActor, HonestDisputeActor } from "test/actors/FaultDisputeActors.sol";

contract FaultDisputeGame_Init is DisputeGameFactory_Init {
    /// @dev The type of the game being tested.
    GameType internal constant GAME_TYPE = GameType.wrap(0);

    /// @dev The implementation of the game.
    FaultDisputeGame internal gameImpl;
    /// @dev The `Clone` proxy of the game.
    FaultDisputeGame internal gameProxy;

    /// @dev The extra data passed to the game for initialization.
    bytes internal extraData;

    event Move(uint256 indexed parentIndex, Claim indexed pivot, address indexed claimant);

    function init(
        Claim rootClaim,
        Claim absolutePrestate,
        uint256 l2BlockNumber,
        uint256 genesisBlockNumber,
        Hash genesisOutputRoot
    )
        public
    {
        // Set the time to a realistic date.
        vm.warp(1690906994);

        // Set the extra data for the game creation
        extraData = abi.encode(l2BlockNumber);

        AlphabetVM _vm = new AlphabetVM(absolutePrestate, new PreimageOracle(0, 0, 0));

        // Deploy an implementation of the fault game
        gameImpl = new FaultDisputeGame({
            _gameType: GAME_TYPE,
            _absolutePrestate: absolutePrestate,
            _genesisBlockNumber: genesisBlockNumber,
            _genesisOutputRoot: genesisOutputRoot,
            _maxGameDepth: 2 ** 3,
            _splitDepth: 2 ** 2,
            _gameDuration: Duration.wrap(7 days),
            _vm: _vm
        });
        // Register the game implementation with the factory.
        disputeGameFactory.setImplementation(GAME_TYPE, gameImpl);
        // Create a new game.
        gameProxy = FaultDisputeGame(address(disputeGameFactory.create(GAME_TYPE, rootClaim, extraData)));

        // Check immutables
        assertEq(gameProxy.gameType().raw(), GAME_TYPE.raw());
        assertEq(gameProxy.absolutePrestate().raw(), absolutePrestate.raw());
        assertEq(gameProxy.genesisBlockNumber(), genesisBlockNumber);
        assertEq(gameProxy.genesisOutputRoot().raw(), genesisOutputRoot.raw());
        assertEq(gameProxy.maxGameDepth(), 2 ** 3);
        assertEq(gameProxy.splitDepth(), 2 ** 2);
        assertEq(gameProxy.gameDuration().raw(), 7 days);
        assertEq(address(gameProxy.vm()), address(_vm));

        // Label the proxy
        vm.label(address(gameProxy), "FaultDisputeGame_Clone");
    }

    fallback() external payable { }

    receive() external payable { }
}

contract FaultDisputeGame_Test is FaultDisputeGame_Init {
    /// @dev The root claim of the game.
    Claim internal constant ROOT_CLAIM = Claim.wrap(bytes32((uint256(1) << 248) | uint256(10)));

    /// @dev The preimage of the absolute prestate claim
    bytes internal absolutePrestateData;
    /// @dev The absolute prestate of the trace.
    Claim internal absolutePrestate;

    /// @dev Minimum bond value that covers all possible moves.
    uint256 internal constant MIN_BOND = 0.01 ether;

    function setUp() public override {
        absolutePrestateData = abi.encode(0);
        absolutePrestate = _changeClaimStatus(Claim.wrap(keccak256(absolutePrestateData)), VMStatuses.UNFINISHED);

        super.setUp();
        super.init({
            rootClaim: ROOT_CLAIM,
            absolutePrestate: absolutePrestate,
            l2BlockNumber: 0x10,
            genesisBlockNumber: 0,
            genesisOutputRoot: Hash.wrap(bytes32(0))
        });
    }

    ////////////////////////////////////////////////////////////////
    //          `IFaultDisputeGame` Implementation Tests       //
    ////////////////////////////////////////////////////////////////

    function test_step_defend() public {
        // Give the test contract some ether
        vm.deal(address(this), 100 ether);

        // Make claims all the way down the tree.
        gameProxy.attack{ value: 1 ether }(0, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(1, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(2, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(3, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(4, _changeClaimStatus(_dummyClaim(), VMStatuses.PANIC));
        gameProxy.attack{ value: 1 ether }(5, _dummyClaim());
        bytes memory claimData = abi.encode(1, 1);
        Claim claim6 = Claim.wrap(keccak256(claimData));
        gameProxy.attack{ value: 1 ether }(6, claim6);
        Claim postState_ = Claim.wrap(gameImpl.vm().step(claimData, hex"", bytes32(0)));
        gameProxy.defend{ value: 1 ether }(7, postState_);
        gameProxy.addLocalData(LocalPreimageKey.DISPUTED_L2_BLOCK_NUMBER, 8, 0);

        vm.expectRevert(ValidStep.selector);
        gameProxy.step(8, false, claimData, hex"");
    }

    function test_step_defend_middle() public {
        // Give the test contract some ether
        vm.deal(address(this), 100 ether);

        // Make claims all the way down the tree.
        gameProxy.attack{ value: 1 ether }(0, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(1, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(2, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(3, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(4, _changeClaimStatus(_dummyClaim(), VMStatuses.PANIC));
        bytes memory claimData5 = abi.encode(5, 5);
        Claim claim5 = Claim.wrap(keccak256(claimData5));
        gameProxy.attack{ value: 1 ether }(5, claim5);
        gameProxy.defend{ value: 1 ether }(6, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(7, _dummyClaim());
        gameProxy.addLocalData(LocalPreimageKey.DISPUTED_L2_BLOCK_NUMBER, 8, 0);

        gameProxy.step(8, true, claimData5, hex"");
    }

    function test_step_defend_last() public {
        // Give the test contract some ether
        vm.deal(address(this), 100 ether);

        // Make claims all the way down the tree.
        gameProxy.attack{ value: 1 ether }(0, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(1, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(2, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(3, _dummyClaim());
        gameProxy.attack{ value: 1 ether }(4, _changeClaimStatus(_dummyClaim(), VMStatuses.PANIC));
        bytes memory claimData5 = abi.encode(5, 5);
        Claim claim5 = Claim.wrap(keccak256(claimData5));
        gameProxy.attack{ value: 1 ether }(5, claim5);
        gameProxy.defend{ value: 1 ether }(6, _dummyClaim());
        Claim postState_ = Claim.wrap(gameImpl.vm().step(claimData5, hex"", bytes32(0)));
        gameProxy.attack{ value: 1 ether }(7, postState_);
        gameProxy.addLocalData(LocalPreimageKey.DISPUTED_L2_BLOCK_NUMBER, 8, 0);

        vm.expectRevert(ValidStep.selector);
        gameProxy.step(8, true, claimData5, hex"");
    }

    /// @dev Helper to return a pseudo-random claim
    function _dummyClaim() internal view returns (Claim) {
        return Claim.wrap(keccak256(abi.encode(gasleft())));
    }

    /// @dev Helper to get the localized key for an identifier in the context of the game proxy.
    function _getKey(uint256 _ident, bytes32 _localContext) internal view returns (bytes32) {
        bytes32 h = keccak256(abi.encode(_ident | (1 << 248), address(gameProxy), _localContext));
        return bytes32((uint256(h) & ~uint256(0xFF << 248)) | (1 << 248));
    }
}

contract FaultDispute_1v1_Actors_Test is FaultDisputeGame_Init {
    /// @dev The honest actor
    DisputeActor internal honest;
    /// @dev The dishonest actor
    DisputeActor internal dishonest;

    function setUp() public override {
        // Setup the `FaultDisputeGame`
        super.setUp();
    }

    ////////////////////////////////////////////////////////////////
    //                          HELPERS                           //
    ////////////////////////////////////////////////////////////////

    /// @dev Helper to run a 1v1 actor test
    function _actorTest(
        uint256 _rootClaim,
        uint256 _absolutePrestateData,
        bytes memory _honestTrace,
        uint256[] memory _honestL2Outputs,
        bytes memory _dishonestTrace,
        uint256[] memory _dishonestL2Outputs,
        GameStatus _expectedStatus
    )
        internal
    {
        // Setup the environment
        bytes memory absolutePrestateData =
            _setup({ _absolutePrestateData: _absolutePrestateData, _rootClaim: _rootClaim });

        // Create actors
        _createActors({
            _honestTrace: _honestTrace,
            _honestPreStateData: absolutePrestateData,
            _honestL2Outputs: _honestL2Outputs,
            _dishonestTrace: _dishonestTrace,
            _dishonestPreStateData: absolutePrestateData,
            _dishonestL2Outputs: _dishonestL2Outputs
        });

        // Exhaust all moves from both actors
        _exhaustMoves();

        // Resolve the game and assert that the defender won
        _warpAndResolve();
        assertEq(uint8(gameProxy.status()), uint8(_expectedStatus));
    }

    /// @dev Helper to setup the 1v1 test
    function _setup(
        uint256 _absolutePrestateData,
        uint256 _rootClaim
    )
        internal
        returns (bytes memory absolutePrestateData_)
    {
        absolutePrestateData_ = abi.encode(_absolutePrestateData);
        Claim absolutePrestateExec =
            _changeClaimStatus(Claim.wrap(keccak256(absolutePrestateData_)), VMStatuses.UNFINISHED);
        Claim rootClaim = Claim.wrap(bytes32(uint256(_rootClaim)));
        super.init({
            rootClaim: rootClaim,
            absolutePrestate: absolutePrestateExec,
            l2BlockNumber: _rootClaim,
            genesisBlockNumber: 0,
            genesisOutputRoot: Hash.wrap(bytes32(0))
        });
    }

    /// @dev Helper to create actors for the 1v1 dispute.
    function _createActors(
        bytes memory _honestTrace,
        bytes memory _honestPreStateData,
        uint256[] memory _honestL2Outputs,
        bytes memory _dishonestTrace,
        bytes memory _dishonestPreStateData,
        uint256[] memory _dishonestL2Outputs
    )
        internal
    {
        honest = new HonestDisputeActor({
            _gameProxy: gameProxy,
            _l2Outputs: _honestL2Outputs,
            _trace: _honestTrace,
            _preStateData: _honestPreStateData
        });
        dishonest = new HonestDisputeActor({
            _gameProxy: gameProxy,
            _l2Outputs: _dishonestL2Outputs,
            _trace: _dishonestTrace,
            _preStateData: _dishonestPreStateData
        });

        vm.deal(address(honest), 100 ether);
        vm.deal(address(dishonest), 100 ether);
        vm.label(address(honest), "HonestActor");
        vm.label(address(dishonest), "DishonestActor");
    }

    /// @dev Helper to exhaust all moves from both actors.
    function _exhaustMoves() internal {
        while (true) {
            // Allow the dishonest actor to make their moves, and then the honest actor.
            (uint256 numMovesA,) = dishonest.move();
            (uint256 numMovesB, bool success) = honest.move();

            require(success, "Honest actor's moves should always be successful");

            // If both actors have run out of moves, we're done.
            if (numMovesA == 0 && numMovesB == 0) break;
        }
    }

    /// @dev Helper to warp past the chess clock and resolve all claims within the dispute game.
    function _warpAndResolve() internal {
        // Warp past the chess clock
        vm.warp(block.timestamp + 3 days + 12 hours + 1 seconds);

        // Resolve all claims in reverse order. We allow `resolveClaim` calls to fail due to
        // the check that prevents claims with no subgames attached from being passed to
        // `resolveClaim`. There's also a check in `resolve` to ensure all children have been
        // resolved before global resolution, which catches any unresolved subgames here.
        for (uint256 i = gameProxy.claimDataLen(); i > 0; i--) {
            (bool success,) = address(gameProxy).call(abi.encodeCall(gameProxy.resolveClaim, (i - 1)));
            assertTrue(success);
        }
        gameProxy.resolve();
    }
}

contract ClaimCreditReenter {
    FaultDisputeGame internal immutable GAME;
    uint256 public numCalls;

    constructor(FaultDisputeGame _gameProxy) {
        GAME = _gameProxy;
    }

    function claimCredit(address _recipient) public {
        numCalls += 1;
        GAME.claimCredit(_recipient);
    }

    receive() external payable {
        if (numCalls == 5) {
            return;
        }
        claimCredit(address(this));
    }
}

/// @dev Helper to change the VM status byte of a claim.
function _changeClaimStatus(Claim _claim, VMStatus _status) pure returns (Claim out_) {
    assembly {
        out_ := or(and(not(shl(248, 0xFF)), _claim), shl(248, _status))
    }
}
