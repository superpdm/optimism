// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Testing utilities
import { Test } from "forge-std/Test.sol";
import { Reverter } from "test/mocks/Callers.sol";

// Libraries
import { Predeploys } from "src/libraries/Predeploys.sol";

// Target contracts
import { L1Block } from "src/L2/L1Block.sol";
import { CrossL2Inbox, NotEntered } from "src/L2/CrossL2Inbox.sol";

contract CrossL2InboxTest is Test {
    /// @dev CrossL2Inbox contract instance.
    CrossL2Inbox crossL2Inbox;

    /// @dev Sample Identifier.
    CrossL2Inbox.Identifier sampleId = CrossL2Inbox.Identifier({
        origin: address(0),
        blocknumber: 0,
        logIndex: 0,
        timestamp: block.timestamp,
        chainId: block.chainid
    });

    /// @dev Sets up the test suite.
    function setUp() public {
        crossL2Inbox = new CrossL2Inbox();
    }

    /// @dev Tests that `executeMessage` succeeds when called with valid parameters.
    function testFuzz_executeMessage_succeeds(
        bytes calldata _msg,
        CrossL2Inbox.Identifier calldata _id,
        address _target,
        uint256 _value
    )
        external
        payable
    {
        vm.assume(_id.timestamp <= block.timestamp);

        // need to prevent call to L1Block.isInDependencySet from reverting
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(L1Block.isInDependencySet.selector, _id.chainId),
            abi.encode(true)
        );

        // need to prevent underlying SafeCall to target from reverting
        vm.etch(_target, address(0).code);

        vm.deal(tx.origin, _value);

        // executeMessage
        vm.prank(tx.origin);
        vm.expectCall(_target, _value, _msg);
        crossL2Inbox.executeMessage{ value: _value }({ _id: _id, _target: _target, _msg: _msg });

        assertEq(crossL2Inbox.origin(), _id.origin);
        assertEq(crossL2Inbox.blocknumber(), _id.blocknumber);
        assertEq(crossL2Inbox.logIndex(), _id.logIndex);
        assertEq(crossL2Inbox.timestamp(), _id.timestamp);
        assertEq(crossL2Inbox.chainId(), _id.chainId);
    }

    /// @dev Tests that `executeMessage` fails when called with an identifier with an invalid timestamp.
    function test_executeMessage_invalidTimestamp_fails() external {
        CrossL2Inbox.Identifier memory id = sampleId;
        id.timestamp = block.timestamp + 1;

        vm.prank(tx.origin);
        vm.expectRevert("CrossL2Inbox: invalid id timestamp");
        crossL2Inbox.executeMessage({ _id: id, _target: address(0), _msg: hex"1234" });
    }

    /// @dev Tests that `executeMessage` fails when called with an identifier with an invalid chain ID.
    function test_executeMessage_invalidChainId_fails() external {
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(L1Block.isInDependencySet.selector, sampleId.chainId),
            abi.encode(false)
        );

        vm.prank(tx.origin);
        vm.expectRevert("CrossL2Inbox: id chain not in dependency set");
        crossL2Inbox.executeMessage({ _id: sampleId, _target: address(0), _msg: hex"1234" });
    }

    /// @dev Tests that `executeMessage` succeeds when called with an identifier with the same chain ID as
    ///      the current chain.
    function test_executeMessage_sameChainId_succeeds() external {
        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(L1Block.isInDependencySet.selector, sampleId.chainId),
            abi.encode(true)
        );

        vm.prank(tx.origin);
        crossL2Inbox.executeMessage({ _id: sampleId, _target: address(0), _msg: hex"1234" });
    }

    /// @dev Tests that `executeMessage` fails when called by a non-EOA.
    function test_executeMessage_invalidSender_fails() external {
        vm.expectRevert("CrossL2Inbox: not EOA sender");
        crossL2Inbox.executeMessage({ _id: sampleId, _target: address(0), _msg: hex"1234" });
    }

    /// @dev Tests that `executeMessage` fails when the underlying target call reverts.
    function test_executeMessage_unsuccessfullSafeCall_fails() external {
        // need to make sure address leads to unsuccessfull SafeCall by executeMessage
        vm.etch(address(0), address(new Reverter()).code);

        vm.mockCall(
            Predeploys.L1_BLOCK_ATTRIBUTES,
            abi.encodeWithSelector(L1Block.isInDependencySet.selector, sampleId.chainId),
            abi.encode(true)
        );

        vm.prank(tx.origin);
        vm.expectRevert("CrossL2Inbox: target call failed");
        crossL2Inbox.executeMessage({ _id: sampleId, _target: sampleTarget, _msg: sampleMsg });
    }
}