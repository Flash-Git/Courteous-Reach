pragma solidity 0.4.24;

contract DonationBox is Ownable {
	/*
	* TODO
	* Gas optimisations
	* Tests
	* Over/Underflow checks
	*/

	//Total donation ether (in wei) ready to send
	uint248 public donationBalance;//storage?
	uint8 public maxCharitiesPerProfile = 5;
	//Temporary escape bool for the entire contract
	bool internal canBeDestroyed = true;
	//Every address is a potential charity
	mapping(address => charity) public charities;
	//Every address has a donation profile
	mapping(address => profile) internal profiles;//can't be public?
	//Array of valid charities
	address[] public validCharities;//is not functionally 0 based

	//Donations done with profile are split between the chosen charities based on shares      
	struct profile {
		//As address is 20bytes, does using uint 96 make a difference anywhere?
		address[] charities;//Charities on profile
		uint8[] shares;//Shares per Charity
	}

	struct charity {
		//Sized for tight packing
		uint16 index;//index of charity in validCharities, 0 for not valid
		uint240 balance;
	}

	//Logging
	event EthReceived(address _from, uint _amount, address indexed _charity);
	event EthSent(uint _amount, address indexed _to);
	event EthWithdrawn(uint _amount, address indexed _to);
	event CharityValidated(address indexed _charity);
	event CharityInvalidated(address indexed _charity);
	event ProfileModified(address indexed _profile, uint8 _index, address indexed _charity, uint8 _shares);
	event ContractKilled(uint _amount, address indexed _to);

	//Initial conditions
	//Validate charities and create initial profiles in here before launch
	constructor() public {
		validCharities.push(address(0x0));
		//dummy charity to take up profiles[profile].charities[0]
		validateCharity(owner);
	}

	//Careful with number of validated charities
	//If the number gets too large, perhaps set other contracts as proxy donation addresses to cheapen the cost of looping
	function validateCharity(address _charity) onlyOwner public {
		require(charities[_charity].index == 0, "Attempting to validate a valid charity");
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

	function setProfile(address[] _charities, uint8[] _shares) public {
		require(_charities.length <= maxCharitiesPerProfile, "Invalid number of charities");
		require(_charities.length == _shares.length, "Incompatible array sizes");

		for (uint8 i = 0; i < _charities.length; i++) {
			modifyProfileCharity(i, _charities[i], _shares[i]);
		}
		//TODO check optimisation in case where profile already has profile and this new profile is smaller than previous profile
		profiles[msg.sender].charities.length = _charities.length;
		//check cost of this operation vs check + operation
		profiles[msg.sender].shares.length = _charities.length;
		//check cost of this operation vs check + operation
	}

	//Add charity to sender's profile
	function addProfileCharity(address _charity, uint8 _share) private {//Max _share size is 255
		checkCharity(_charity);
		require(profiles[msg.sender].charities.length < maxCharitiesPerProfile, "Already at max number of charities");
		profiles[msg.sender].charities.push(_charity);
		profiles[msg.sender].shares.push(_share);
		emit ProfileModified(msg.sender, uint8(profiles[msg.sender].charities.length - 1), _charity, _share);
		//TODO check length-1, i cant think rn
	}

	//Modify charity on sender's profile, using _num prevents unwanted duplicates
	function modifyProfileCharity(uint8 _num, address _charity, uint8 _share) public {//Max _share size is 255
		if (_num >= profiles[msg.sender].charities.length) {
			addProfileCharity(_charity, _share);
			return;
		}
		checkCharity(_charity);
		profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].shares[_num] = _share;
		emit ProfileModified(msg.sender, _num, _charity, _share);
	}

	//Nullify charity
	//Will only remove charity from "list" if you're nullifying the last "element"
	function nullifyProfileCharity(uint8 _num) public {
		require(_num < profiles[msg.sender].charities.length, "Attempting to edit outside of array");
		profiles[msg.sender].shares[_num] = 0;
		emit ProfileModified(msg.sender, _num, profiles[msg.sender].charities[_num], 0);
		if (profiles[msg.sender].charities.length - 1 == _num) {
			profiles[msg.sender].charities.length--;
			//TODO check this works
		}
	}

	function copyProfileFrom(address _from) public {
		profiles[msg.sender] = profiles[_from];
	}

	function resetProfile() public {
		delete profiles[msg.sender];
	}

	//Doesn't update donator's balance
	function() public payable {
		emit EthReceived(msg.sender, msg.value, address(this));
		//I don't know why this gas cost fluctuates
	}

	//Donate directly
	function donateTo(address _charity) public payable {
		require(msg.value > 0, "Donation requires more than 0");
		checkCharity(_charity);
		charities[_charity].balance += uint240(msg.value);
		assert(donationBalance + msg.value > donationBalance);
		//fatal
		donationBalance += uint240(msg.value);
		emit EthReceived(msg.sender, msg.value, _charity);
	}

	//Donate through sender's profile
	function donateWithProfile() public payable {
		donateWithProfile(msg.sender);
	}

	//Donate through another's profile
	//TODO calc shares at runtime
	function donateWithProfile(address _profile) public payable {
		require(msg.value > 0, "Donation requires more than 0");
		require(profiles[_profile].charities.length > 0, "This profile is empty");

		//Only possible if owner reduces maxCharitiesPerProfile
		while (profiles[_profile].charities.length > maxCharitiesPerProfile) {//can either delete profile or remove the last elements
			profiles[_profile].charities.length--;
			profiles[_profile].shares[profiles[_profile].charities.length] = 0;
			emit ProfileModified(_profile, uint8(profiles[_profile].charities.length), profiles[_profile].charities[profiles[_profile].charities.length], 0);
		}
		require(getTotalShares(_profile) > 0, "Profile requires more than 0 shares");
		//This logic seems suboptimal

		uint240 donated;
		for (uint8 i = 0; i < profiles[_profile].charities.length; i++) {
			checkCharity(profiles[_profile].charities[i]);
			uint240 donateAmt = uint240(msg.value) * profiles[_profile].shares[i] / getTotalShares(_profile);
			charities[profiles[_profile].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit EthReceived(msg.sender, donateAmt, profiles[_profile].charities[i]);
		}
		//Is creating a uint cheaper than increasing another uint x times?
		charities[profiles[_profile].charities[0]].balance += (uint240(msg.value) - donated);
		//catch lost eth
		donated += (uint240(msg.value) - donated);
		assert(msg.value - donated == 0);
		assert(donationBalance + donated > donationBalance);
		//fatal
		donationBalance += donated;
	}

	//Payout all valid charities
	function payoutAllCharities(uint _minimumPayout) public {
		for (uint16 i = 0; i < validCharities.length; i++) {
			checkCharity(validCharities[i]);
			uint240 amtToPayout = charities[validCharities[i]].balance;
			if (amtToPayout < _minimumPayout || amtToPayout == 0) {
				continue;
			}
			charities[validCharities[i]].balance = 0;
			assert(donationBalance - amtToPayout < donationBalance);
			//fatal
			donationBalance -= amtToPayout;
			validCharities[i].transfer(amtToPayout);
			emit EthSent(amtToPayout, validCharities[i]);
		}
	}

	//Force payout an individual charity
	function payoutCharity(address _charity) public {
		checkCharity(_charity);
		uint240 amtToPayout = charities[_charity].balance;
		charities[_charity].balance = 0;
		assert(donationBalance - amtToPayout < donationBalance);
		//fatal
		donationBalance -= amtToPayout;
		_charity.transfer(amtToPayout);
		emit EthSent(amtToPayout, _charity);
	}

	//Is it more efficient to have these repeated without functions?
	function checkCharity(address _charity) view private {
		require(charities[_charity].index != 0, "Invalid charity");
	}

	function getTotalShares(address _profile) private view returns (uint16) {
		uint16 shares;
		for (uint8 i = 0; i < profiles[_profile].charities.length; i++) {
			shares += profiles[_profile].shares[i];
		}
		return shares;
	}

	function contractBalance() public view returns (uint) {
		return address(this).balance;
	}

	//Balance that is not a part of the donation pool
	function withdrawableBalance() onlyOwner public view returns (uint) {
		return address(this).balance - donationBalance;
	}

	//Withdraw balance that is no a part of the donation pool
	function withdrawExcess() onlyOwner public {
		uint excess = address(this).balance - donationBalance;
		assert(excess >= 0);
		msg.sender.transfer(excess);
		emit EthWithdrawn(excess, msg.sender);
	}

	//Keep this low
	function changeMaxCharitiesPerProfile(uint8 _maxCharitiesPerProfile) onlyOwner public {
		maxCharitiesPerProfile = _maxCharitiesPerProfile;
	}

	//Permanently remove temporary escape
	function removeEmergencyEscape() onlyOwner public {
		canBeDestroyed = false;
	}

	//Temporary escape in case of critical error
	function selfDestruct() onlyOwner public {
		require(canBeDestroyed, "Can no longer be destroyed, sorry");
		emit ContractKilled(address(this).balance, msg.sender);
		selfdestruct(owner);
	}

}