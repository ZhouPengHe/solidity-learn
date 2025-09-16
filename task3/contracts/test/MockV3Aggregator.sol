// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
	uint8 public immutable override decimals;
	string public constant override description = "mock";
	uint256 public override version = 1;

	int256 private _answer;

	uint80 private _roundId = 1;
	uint256 private _timestamp;

	constructor(uint8 _decimals, int256 initialAnswer) {
		decimals = _decimals;
		_answer = initialAnswer;
		_timestamp = block.timestamp;
	}

	function setAnswer(int256 newAnswer) external {
		_answer = newAnswer;
		_roundId++;
		_timestamp = block.timestamp;
	}

	function latestRoundData()
		external
		view
		override
		returns (
			uint80 roundId,
			int256 answer,
			uint256 startedAt,
			uint256 updatedAt,
			uint80 answeredInRound
		)
	{
		return (_roundId, _answer, _timestamp, _timestamp, _roundId);
	}

	function getRoundData(uint80)
		external
		view
		override
		returns (
			uint80 roundId,
			int256 answer,
			uint256 startedAt,
			uint256 updatedAt,
			uint80 answeredInRound
		)
	{
		return (_roundId, _answer, _timestamp, _timestamp, _roundId);
	}
}


