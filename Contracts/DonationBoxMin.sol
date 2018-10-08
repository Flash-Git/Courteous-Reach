pragma solidity 0.4.25;

/*
* Courteous-Reach
* ===============

* Author: Flash
* Date: 22/08/2018
* Version: 1.0
*/

contract DonationBox is Ownable {
	/*
	* TODO
	*
	* Gas optimisations
	*	Tight packing solutions
	*	Manual optimisation
	*
	* Tests
	*
	* Research
	*	optimal profileSize
	*	necessary features
	*	necessary events
	*
	* Default profiles?
	* ENS
	* ERC20 tokens
	* NFTYs (potentially)
	*/


	/*
	* Storage
	*/

	//Total donation ether (in wei) ready to send
	uint96 public donationBalance;//storage?
	uint8 public profileSize = 5;
	//address public defaultProfile;
	//Temporary escape bool for the entire contract
	bool private canBeDestroyed = true;
	//Every address is a potential charity
	mapping(address => charity) public charities;
	//Every address has a donation profile
	mapping(address => profile) private profiles;//can't be public?
	//Array of valid charities, can handle up to 2**16 of them
	address[] public validCharities;//is not functionally 0 based TODO handle unlimited size


	/*
	* Structs
	*/

	//Donations done with profile are split between the chosen charities based on shares      
	struct profile {
		//As address is 20bytes, does using uint 96 make a difference anywhere?
		address[5] charities;//Charities on profile
		uint8[5] shares;//Shares per Charity
	}

	struct charity {
		//Sized for tight packing, better to add up to 256?
		uint16 index;//index of charity in validCharities, 0 for invalid
		uint96 balance;
	}


	/*
	* Events
	*/

	event EthReceived(address _from, uint96 _amount, address indexed _charity);
	event EthSent(uint96 _amount, address indexed _to);
	event EthWithdrawn(uint96 _amount, address indexed _to);
	event CharityValidated(address indexed _charity);
	event CharityInvalidated(address indexed _charity);
	event ProfileModified(address indexed _profile, uint8 _index, address indexed _charity, uint8 _shares);
	event ContractKilled(uint96 _amount, address indexed _to);


	/*
	* Constructor
	*/

	//Validate charities and create initial profiles in here before launch
	constructor() public {
		validCharities.push(address(0));
		//dummy charity to take up profiles[profile].charities[0]
		validateCharity(owner);
	}


	/*
	* Fallback function
	*/

	//Doesn't update donator's balance
	function() public payable {
		emit EthReceived(msg.sender, uint96(msg.value), address(this));
		//TODO understand gas cost fluctuations
	}


	/*
	* Validation methods
	*/

	//Careful with number of validated charities
	//If the number gets too large, perhaps set other contracts as proxy donation addresses to cheapen the cost of looping
	function validateCharity(address _charity) onlyOwner public {
		require(charities[_charity].index == 0, "Attempting to validate a valid charity");
		require(validCharities.length < 65536 - 1, "Array of valid charities is full");
		//TODO check overflow

		validCharities.push(_charity);
		charities[_charity].index = uint16(validCharities.length - 1);
		emit CharityValidated(_charity);
	}

	function invalidateCharity(address _charity) onlyOwner public {
		require(charities[_charity].index != 0, "Attempting to invalidate an invalid charity");

		//Set index of last charity in validCharities to the index of invalidatedCharity
		charities[validCharities[validCharities.length - 1]].index = charities[_charity].index;
		//Replace invalidatedCharity with last charity in validCharities
		validCharities[charities[_charity].index] = validCharities[validCharities.length - 1];
		//Shorten length of validCharities to delete the last charity
		validCharities.length--;

		//Set index of invalidatedCharity to 0
		charities[_charity].index = 0;
		emit CharityInvalidated(_charity);
	}


	/*
	* Profile Methods
	*/

	//Add charity to sender's profile, will occupy first slot where shares == 0
	function profileAddC(address _charity, uint8 _share) public {//Max _share size is 255
		require(_share > 0, "Shares must be larger than 0");

		for (uint8 i = 0; i < profileSize; i++) {
			if (profiles[msg.sender].shares[i] == 0) {
				profileModC(i, _charity, _share);
				return;
			}
		}
		revert("No space for new charity on profile");
	}

	//Modify charity on sender's profile, using _num prevents unwanted duplicates
	function profileModC(uint8 _num, address _charity, uint8 _share) public {//Max _share size is 255
		require(_num < profileSize, "Attempting to edit outside of array");
		checkCharity(_charity);

		profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].shares[_num] = _share;
		emit ProfileModified(msg.sender, _num, _charity, _share);
	}

	//Nullify charity on sender's profile by setting shares to 0
	function profileNulC(uint8 _num) public {
		require(_num < profileSize, "Attempting to edit outside of array");

		profiles[msg.sender].shares[_num] = 0;
		emit ProfileModified(msg.sender, _num, profiles[msg.sender].charities[_num], 0);
	}

	function profileSet(address[] _charities, uint8[] _shares) public {
		require(_charities.length <= profileSize, "Invalid number of charities");
		require(_charities.length == _shares.length, "Incompatible array sizes");

		for (uint8 i = 0; i < _charities.length; i++) {
			profileModC(i, _charities[i], _shares[i]);
		}
		for (i = uint8(_charities.length); i < profileSize; i++) {//Reinitialise i in 0.5.0
			profileNulC(i);
		}
	}

	function profileCopy(address _from) public {
		profiles[msg.sender] = profiles[_from];
	}

	function profileReset() public {
		delete profiles[msg.sender];
	}


	/*
	* Donation methods
	*/

	//Donate directly
	function donateTo(address _charity) public payable {
		require(msg.value > 0, "Donation must be larger than 0");
		checkCharity(_charity);

		charities[_charity].balance += uint96(msg.value);
		donationBalance += uint96(msg.value);
		emit EthReceived(msg.sender, uint96(msg.value), _charity);
	}

	//Donate through sender's profile
	function donateWithProfile() public payable {
		donateWithProfile(msg.sender);
	}

	//Donate through another's profile
	function donateWithProfile(address _profile) public payable {
		require(msg.value > 0, "Donation must be larger than 0");
		//Donations must also be smaller than 310698676526526814092329217 Wei (310,698,676 Ether)
		uint16 totalShares = getTotalShares(_profile);
		require(getTotalShares(_profile) > 0, "Profile requires more than 0 shares");

		uint96 donated;
		for (uint8 i = 0; i < profileSize; i++) {
			checkCharity(profiles[_profile].charities[i]);
			uint96 donateAmt = uint96(msg.value) * profiles[_profile].shares[i] / getTotalShares(_profile);
			//TODO verify overflow
			charities[profiles[_profile].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit EthReceived(msg.sender, donateAmt, profiles[_profile].charities[i]);
			if ((totalShares -= profiles[_profile].shares[i]) == 0) {//Exit loop early if end of profile shares == 0
				break;
			}
		}
		//Is creating a uint cheaper than increasing another uint x times?
		charities[profiles[_profile].charities[0]].balance += (uint96(msg.value) - donated);
		//catch lost eth
		donated += (uint96(msg.value) - donated);
		require(msg.value - donated == 0);
		assert(donationBalance + donated > donationBalance);
		//fatal
		donationBalance += donated;
	}


	/*
	* Payout methods
	*/

	//Force payout an individual charity
	function payoutCharity(address _charity) public {
		checkCharity(_charity);

		uint96 amtToPayout = charities[_charity].balance;
		charities[_charity].balance = 0;
		assert(donationBalance - amtToPayout < donationBalance);
		//fatal
		donationBalance -= amtToPayout;
		_charity.transfer(amtToPayout);
		emit EthSent(amtToPayout, _charity);
	}

	//Payout all valid charities
	function payoutAllCharities(uint _minimumPayout) public {
		for (uint16 i = 1; i < validCharities.length; i++) {
			if (_minimumPayout <= charities[validCharities[i]].balance && charities[validCharities[i]].balance != 0) {
				payoutCharity(validCharities[i]);
			}
		}
	}


	/*
	* Private getters
	*/

	function checkCharity(address _charity) private view {
		require(charities[_charity].index != 0, "Invalid charity");
	}

	function getTotalShares(address _profile) private view returns (uint16) {
		uint16 shares;
		for (uint8 i = 0; i < profileSize; i++) {
			shares += profiles[_profile].shares[i];
		}
		return shares;
	}

	function getTotalShares(uint8[] _shares) private view returns (uint16) {
		require(_shares.length <= profileSize, "Array too large");

		uint16 shares;
		for (uint8 i = 0; i < _shares.length; i++) {
			shares += _shares[i];
		}
		return shares;
	}


	/*
	* Public getters
	*/

	function getProfileCharities() public view returns (address[5]) {
		return getProfileCharities(msg.sender);
	}

	function getProfileShares() public view returns (uint8[5]) {
		return getProfileShares(msg.sender);
	}

	function getProfileCharities(address _profile) public view returns (address[5]) {
		return profiles[_profile].charities;
	}

	function getProfileShares(address _profile) public view returns (uint8[5]) {
		return profiles[_profile].shares;
	}

	function getContractBalance() public view returns (uint96) {
		return uint96(address(this).balance);
	}

	//Balance that is not part of the donation funds
	function getExcess() public view returns (uint96) {
		return uint96(address(this).balance) - donationBalance;
	}


	/*
	* Admin methods
	*/

	//Balance that is not part of the donation funds
	function sweepExcess() public {
		uint96 excess = uint96(address(this).balance) - donationBalance;
		require(excess > 0, "No excess funds to sweep");

		owner.transfer(excess);
		emit EthWithdrawn(excess, owner);
	}

	//Permanently remove temporary escape
	function removeEmergencyEscape() onlyOwner public {
		canBeDestroyed = false;
	}

	//Temporary escape in case of critical error
	function selfDestruct() onlyOwner public {
		require(canBeDestroyed, "Can no longer be destroyed, sorry");

		emit ContractKilled(uint96(address(this).balance), msg.sender);
		selfdestruct(owner);
	}

}