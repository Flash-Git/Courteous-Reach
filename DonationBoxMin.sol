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
	uint8 public profileSize = 5;
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
		address[5] charities;//Charities on profile
		uint8[5] shares;//Shares per Charity
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
		validCharities.push(address(0));//dummy charity to take up profiles[profile].charities[0]
		validateCharity(owner);
	}

	//Careful with number of validated charities
	//If the number gets too large, perhaps set other contracts as proxy donation addresses to cheapen the cost of looping
	function validateCharity(address _charity) onlyOwner public {
		require(charities[_charity].index == 0, "Attempting to validate a valid charity");

		validCharities.push(_charity);
		charities[_charity].index = uint16(validCharities.length-1);
		emit CharityValidated(_charity);
	}

	function invalidateCharity(address _charity) onlyOwner public {
		require(charities[_charity].index != 0, "Attempting to invalidate an invalid charity");

		//Set index of last charity in validCharities to the index of invalidatedCharity
		charities[validCharities[validCharities.length-1]].index = charities[_charity].index;
		//Replace invalidatedCharity with last charity in validCharities
		validCharities[charities[_charity].index] = validCharities[validCharities.length-1];
		//Shorten length of validCharities to delete the last charity
		validCharities.length--;

		//Set index of invalidatedCharity to 0
		charities[_charity].index = 0;
		emit CharityInvalidated(_charity);
	}

	function setProfile(address[] _charities, uint8[] _shares) public {
		require(_charities.length <= profileSize, "Invalid number of charities");
		require(_charities.length == _shares.length, "Incompatible array sizes");

		for(uint8 i = 0; i < _charities.length; i++){
			modifyProfileCharity(i, _charities[i], _shares[i]);
		}
		for(uint8 j = uint8(_charities.length); j < profileSize; j++){//fixed in 0.5.0
			nullifyProfileCharity(j);
		}
	}

	//Modify charity on sender's profile, using _num prevents unwanted duplicates
	function modifyProfileCharity(uint8 _num, address _charity, uint8 _share) public {//Max _share size is 255
		require(_num < profileSize, "Attempting to edit outside of array");
		checkCharity(_charity);

		profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].shares[_num] = _share;
		emit ProfileModified(msg.sender, _num, _charity, _share);
	}

	//Add charity to sender's profile, will occupy first slot where shares == 0
	function addProfileCharity(address _charity, uint8 _share) private {//Max _share size is 255
		for(uint8 i = 0; i < profileSize; i++){
			if(profiles[msg.sender].shares[i] == 0){
				modifyProfileCharity(i, _charity, _share);
				return;
			}
		}
		revert();
	}

	//Nullify charity on sender's profile by setting shares to 0
	function nullifyProfileCharity(uint8 _num) public {
		require(_num < profileSize, "Attempting to edit outside of array");

		profiles[msg.sender].shares[_num] = 0;
		emit ProfileModified(msg.sender, _num, profiles[msg.sender].charities[_num], 0);
	}

	function copyProfileFrom(address _from) public {
		profiles[msg.sender] = profiles[_from];
	}

	function resetProfile() public {
		delete profiles[msg.sender];
	}

	//Doesn't update donator's balance
	function() public payable {
		emit EthReceived(msg.sender, msg.value, address(this));//I don't know why this gas cost fluctuates
	}

	//Donate directly
	function donateTo(address _charity) public payable {
		require(msg.value > 0, "Donation must be larger than 0");
		checkCharity(_charity);

		charities[_charity].balance += uint240(msg.value);
		require(donationBalance + msg.value > donationBalance);//fatal
		donationBalance += uint240(msg.value);
		emit EthReceived(msg.sender, msg.value, _charity);
	}

	//Donate through sender's profile
	function donateWithProfile() public payable {
		donateWithProfile(msg.sender);
	}

	//Donate through another's profile
	function donateWithProfile(address _profile) public payable {
		require(msg.value > 0, "Donation must be larger than 0");
		require(profiles[_profile].charities.length > 0, "Profile is empty");
		uint16 totalShares = getTotalShares(_profile);
		require(getTotalShares(_profile) > 0, "Profile requires more than 0 shares");

		uint240 donated;
		for(uint8 i = 0; i < profileSize; i++){
			checkCharity(profiles[_profile].charities[i]);
			uint240 donateAmt = uint240(msg.value) * profiles[_profile].shares[i] / getTotalShares(_profile);
			charities[profiles[_profile].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit EthReceived(msg.sender, donateAmt, profiles[_profile].charities[i]);
			if(totalShares == 0){
				break;
			}
		}//Is creating a uint cheaper than increasing another uint x times?
		charities[profiles[_profile].charities[0]].balance += (uint240(msg.value)-donated);//catch lost eth
		donated += (uint240(msg.value)-donated);
		require(msg.value - donated == 0);
		require(donationBalance + donated > donationBalance);//fatal
		donationBalance += donated;
	}

	//Payout all valid charities
	function payoutAllCharities(uint _minimumPayout) public {
		for(uint16 i = 0; i < validCharities.length; i++){
			checkCharity(validCharities[i]);

			uint240 amtToPayout = charities[validCharities[i]].balance; 
			if(amtToPayout < _minimumPayout || amtToPayout == 0){
				continue;
			}
			charities[validCharities[i]].balance = 0;
			require(donationBalance - amtToPayout < donationBalance);//fatal
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
		require(donationBalance - amtToPayout < donationBalance);//fatal
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
		for(uint8 i = 0; i < profiles[_profile].charities.length; i++){
			shares += profiles[_profile].shares[i];
		}
		return shares;
	}

	function getTotalShares(uint8[] _shares) private view returns (uint16) {
		require(_shares.length <= profileSize, "Array too large");

		uint16 shares;
		for(uint8 i = 0; i < _shares.length; i++){
			shares += _shares[i];
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
		require(excess >= 0);

		msg.sender.transfer(excess);
		emit EthWithdrawn(excess, msg.sender);
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