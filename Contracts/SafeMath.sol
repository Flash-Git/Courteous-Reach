pragma solidity 0.4.24;

//From OpenZeppelin

library SafeMath {
	function mul(uint256 _a, uint256 _b) internal pure returns (uint256) {
		//Cheaper to test only one input
		if (_a == 0) {
			return 0;
		}
		uint256 c = _a * _b;
		require(c / _a == _b);
		return c;
	}

	function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
		//Already throws when dividing by 0
		require(_b > 0);
		//Truncates the quotient
		uint256 c = _a / _b;
		return c;
	}

	function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
		require(_b <= _a);
		uint256 c = _a - _b;
		return c;
	}

	function add(uint256 _a, uint256 _b) internal pure returns (uint256) {
		uint256 c = _a + _b;
		require(c >= _a);
		return c;
	}

	function mod(uint256 a, uint256 b) internal pure returns (uint256) {
		require(b != 0);
		return a % b;
	}
}