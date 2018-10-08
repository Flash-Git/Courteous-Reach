pragma solidity 0.4.24;

contract DonationBoxHeavy is Ownable {

	//Total donation ether (in wei) ready to send
	uint public donationBalance;
	uint8 public maxCharitiesPerProfile = 5;
	bool internal canBeDestroyed = true;
	//Every address is a potential charity
	mapping(address => charity) public charities;
	//Every address has a donation profile
	mapping(address => profile) public profiles;
	//Every address has an amount donated
	mapping(address => uint) public amtDonated;//Not to be taken seriously
	//Array of valid charities
	address[] public validCharities;

	//Donations done with profile are split between the chosen charities based on shares        
	struct profile {
		address[] charities;//Charities on profile
		uint[] shares;//Shares per Charity
		uint totalShares;//Gas efficient to keep track of total shares(?)
		uint8 numOfCharities;//Gas efficient by knowing number of charities per profile
	}

	struct charity {
		bool valid;
		uint balance;
	}

	event Received(address _from, uint _amount, address indexed _charity);
	event Sent(uint _amount, address indexed _to);
	event Withdrawal(uint _amount, address indexed _to);
	event ValidatedCharity(address indexed _charity);
	event InvalidatedCharity(address indexed _charity);
	event ModifyCharityOnProfile(address indexed _profile, uint8 _index, address indexed _charity, uint8 _shares);
	event KilledContract(uint _amount, address indexed _to);

	//Initial conditions
	constructor() public {
		validateCharity(owner);
	}

	//Careful with number of validated charities.
	//If the number gets too large, perhaps set other contracts as proxy donation addresses to cheapen the cost of looping
	function validateCharity(address _charity) onlyOwner public {
		require(!charities[_charity].valid, "Attempting to validate a valid charity");
		charities[_charity].valid = true;
		validCharities.push(_charity);
		emit ValidatedCharity(_charity);
	}

	function invalidateCharity(address _charity) onlyOwner public {
		require(charities[_charity].valid, "Attempting to invalidate an invalid charity");
		charities[_charity].valid = false;
		//Replace the invalid charity with the last charity
		for (uint16 i = 0; i < validCharities.length; i++) {
			if (validCharities[i] == _charity) {
				validCharities[i] = validCharities[validCharities.length - 1];
				validCharities.length--;
				//shortening length does delete the omitted element
				break;
			}
		}
		emit InvalidatedCharity(_charity);
	}

	function addProfileCharity(address _charity, uint8 _share) public {//Max _share size is 255
		require(charities[_charity].valid, "Invalid charity");
		require(profiles[msg.sender].numOfCharities < maxCharitiesPerProfile, "Already at max number of charities");
		if (profiles[msg.sender].charities.length == profiles[msg.sender].numOfCharities) {//Length can be bigger than numOfCharities due to resize of maxCharitiesPerProfile
			profiles[msg.sender].charities.push(_charity);
			profiles[msg.sender].shares.push(_share);
		} else {
			profiles[msg.sender].charities[profiles[msg.sender].numOfCharities] = _charity;
			profiles[msg.sender].totalShares -= profiles[msg.sender].shares[profiles[msg.sender].numOfCharities];
			profiles[msg.sender].shares[profiles[msg.sender].numOfCharities] = _share;
		}
		profiles[msg.sender].totalShares += _share;
		profiles[msg.sender].numOfCharities++;
		emit ModifyCharityOnProfile(msg.sender, profiles[msg.sender].numOfCharities - 1, _charity, _share);
	}

	function modifyProfileCharity(uint8 _num, address _charity, uint8 _share) public {//Max _share size is 255
		require(_num < profiles[msg.sender].numOfCharities, "Attempting to edit outside of array");
		profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].shares[_num] = _share;
		emit ModifyCharityOnProfile(msg.sender, _num, _charity, _share);
	}

	//Will only remove charity from "list" if you're nullifying the last "element"
	function nullifyProfileCharity(uint8 _num) public {
		require(_num < profiles[msg.sender].numOfCharities, "Attempting to edit outside of array");
		profiles[msg.sender].totalShares -= profiles[msg.sender].shares[_num];
		profiles[msg.sender].shares[_num] = 0;
		emit ModifyCharityOnProfile(msg.sender, _num, profiles[msg.sender].charities[_num], 0);
		if (profiles[msg.sender].numOfCharities - 1 == _num) {
			profiles[msg.sender].numOfCharities--;
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
		emit Received(msg.sender, msg.value, address(this));
	}

	//Direct amt donate
	function donateWithAmt(uint _amount, address _charity) public payable {
		checkAmount(_amount);
		checkCharity(_charity);
		charities[_charity].balance += _amount;
		donationBalance += _amount;
		amtDonated[msg.sender] += _amount;
		emit Received(msg.sender, _amount, _charity);
	}

	//On behalf of, set to 0x0 for anonymous
	function donateWithAmtFor(uint _amount, address _charity, address _for) public payable {
		checkAmount(_amount);
		checkCharity(_charity);
		charities[_charity].balance += _amount;
		donationBalance += _amount;
		amtDonated[_for] += _amount;
		emit Received(_for, _amount, _charity);
	}

	//Direct % donate
	function donateWithPerc(uint8 _percentage, address _charity) public payable {
		checkCharity(_charity);
		checkPerc(_percentage);
		uint donateAmt = (msg.value * _percentage) / 100;
		charities[_charity].balance += donateAmt;
		donationBalance += donateAmt;
		amtDonated[msg.sender] += donateAmt;
		emit Received(msg.sender, donateAmt, _charity);
	}

	function donateWithPercFor(uint8 _percentage, address _charity, address _for) public payable {
		checkCharity(_charity);
		checkPerc(_percentage);
		uint donateAmt = (msg.value * _percentage) / 100;
		charities[_charity].balance += donateAmt;
		donationBalance += donateAmt;
		amtDonated[_for] += donateAmt;
		emit Received(_for, donateAmt, _charity);
	}

	//Direct profile donate
	function donateWithProfile(uint _amount) public payable {
		checkAmount(_amount);
		//Only possible if owner reduces maxCharitiesPerProfile
		while (profiles[msg.sender].numOfCharities > maxCharitiesPerProfile) {//can either delete profile or remove the last elements
			profiles[msg.sender].numOfCharities -= 1;
			//Less code than nullifyProfileCharity()
			profiles[msg.sender].totalShares -= profiles[msg.sender].shares[profiles[msg.sender].numOfCharities];
			profiles[msg.sender].shares[profiles[msg.sender].numOfCharities] = 0;
			emit ModifyCharityOnProfile(msg.sender, profiles[msg.sender].numOfCharities, profiles[msg.sender].charities[profiles[msg.sender].numOfCharities], 0);
		}
		require(profiles[msg.sender].totalShares > 0, "Profile requires more than 0 shares");
		//This logic seems suboptimal

		uint donated;
		for (uint8 i = 0; i < profiles[msg.sender].numOfCharities; i++) {
			checkCharity(profiles[msg.sender].charities[i]);
			uint donateAmt = _amount * profiles[msg.sender].shares[i] / profiles[msg.sender].totalShares;
			charities[profiles[msg.sender].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit Received(msg.sender, donateAmt, profiles[msg.sender].charities[i]);
		}
		//Is creating a uint cheaper than increasing another uint x times?
		donationBalance += donated;
		amtDonated[msg.sender] += donated;
	}

	function donateWithProfileFor(uint _amount, address _for) public payable {
		checkAmount(_amount);
		require(profiles[msg.sender].totalShares > 0, "Profile requires more than 0 shares");
		//Only possible if owner reduces maxCharitiesPerProfile
		while (profiles[msg.sender].numOfCharities > maxCharitiesPerProfile) {//can either delete profile or remove the last elements
			profiles[msg.sender].numOfCharities -= 1;
			//Less code than nullifyProfileCharity()
			profiles[msg.sender].totalShares -= profiles[msg.sender].shares[profiles[msg.sender].numOfCharities];
			profiles[msg.sender].shares[profiles[msg.sender].numOfCharities] = 0;
			emit ModifyCharityOnProfile(msg.sender, profiles[msg.sender].numOfCharities, profiles[msg.sender].charities[profiles[msg.sender].numOfCharities], 0);
		}
		uint donated;
		for (uint8 i = 0; i < profiles[msg.sender].numOfCharities; i++) {
			checkCharity(profiles[msg.sender].charities[i]);
			uint donateAmt = _amount * profiles[msg.sender].shares[i] / profiles[msg.sender].totalShares;
			charities[profiles[msg.sender].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit Received(_for, donateAmt, profiles[msg.sender].charities[i]);
		}
		donationBalance += donated;
		amtDonated[_for] += donated;
	}

	//Donate with another's profile
	function donateWithThisProfile(uint _amount, address _this) public payable {
		checkAmount(_amount);
		require(profiles[_this].totalShares > 0, "Profile requires more than 0 shares");
		//Only possible if owner reduces maxCharitiesPerProfile
		while (profiles[_this].numOfCharities > maxCharitiesPerProfile) {//can either delete profile or remove the last elements
			profiles[_this].numOfCharities -= 1;
			//Less code than nullifyProfileCharity()
			profiles[_this].totalShares -= profiles[_this].shares[profiles[_this].numOfCharities];
			profiles[_this].shares[profiles[_this].numOfCharities] = 0;
			emit ModifyCharityOnProfile(_this, profiles[_this].numOfCharities, profiles[_this].charities[profiles[_this].numOfCharities], 0);
		}
		uint donated;
		for (uint8 i = 0; i < profiles[_this].numOfCharities; i++) {
			checkCharity(profiles[_this].charities[i]);
			uint donateAmt = _amount * profiles[_this].shares[i] / profiles[_this].totalShares;
			charities[profiles[_this].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit Received(msg.sender, donateAmt, profiles[_this].charities[i]);
		}
		donationBalance += donated;
		amtDonated[msg.sender] += donated;
	}

	//Donate with another's profile on behalf of
	function donateWithThisProfileFor(uint _amount, address _this, address _for) public payable {
		checkAmount(_amount);
		require(profiles[_this].totalShares > 0, "Profile requires more than 0 shares");
		//Only possible if owner reduces maxCharitiesPerProfile
		while (profiles[_this].numOfCharities > maxCharitiesPerProfile) {//can either delete profile or remove the last elements
			profiles[_this].numOfCharities -= 1;
			//Less code than nullifyProfileCharity()
			profiles[_this].totalShares -= profiles[_this].shares[profiles[_this].numOfCharities];
			profiles[_this].shares[profiles[_this].numOfCharities] = 0;
			emit ModifyCharityOnProfile(_this, profiles[_this].numOfCharities, profiles[_this].charities[profiles[_this].numOfCharities], 0);
		}
		uint donated;
		for (uint8 i = 0; i < profiles[_this].numOfCharities; i++) {
			checkCharity(profiles[_this].charities[i]);
			uint donateAmt = _amount * profiles[_this].shares[i] / profiles[_this].totalShares;
			charities[profiles[_this].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit Received(_for, donateAmt, profiles[_this].charities[i]);
		}
		donationBalance += donated;
		amtDonated[_for] += donated;
	}

	//Payout all valid charities
	function payoutAllCharities(uint _minimumPayout) public {
		for (uint16 i = 0; i < validCharities.length; i++) {
			checkCharity(validCharities[i]);
			uint amtToPayout = charities[validCharities[i]].balance;
			if (amtToPayout < _minimumPayout || amtToPayout == 0) {
				continue;
			}
			charities[validCharities[i]].balance = 0;
			donationBalance -= amtToPayout;
			validCharities[i].transfer(amtToPayout);
			emit Sent(amtToPayout, validCharities[i]);
		}
	}

	//Force payout an individual charity
	function payoutCharity(address _charity) public {
		checkCharity(_charity);
		uint amtToPayout = charities[_charity].balance;
		charities[_charity].balance = 0;
		donationBalance -= amtToPayout;
		_charity.transfer(amtToPayout);
		emit Sent(amtToPayout, _charity);
	}

	//Is it more efficient to have these repeated without functions?
	function checkCharity(address _charity) view internal {
		require(charities[_charity].valid, "Invalid charity");
	}

	function checkAmount(uint _amount) view internal {
		require(_amount <= msg.value, "Attempting to donate more than was sent");
	}

	function checkPerc(uint _percentage) pure internal {
		require(_percentage <= 100, "Invalid percentage");
	}

	function contractBalance() public view returns (uint) {
		return address(this).balance;
	}

	function withdrawableBalance() onlyOwner public view returns (uint) {
		return address(this).balance - donationBalance;
	}

	function withdrawAll() onlyOwner public {
		assert(address(this).balance - donationBalance >= 0);
		msg.sender.transfer(address(this).balance - donationBalance);
		emit Withdrawal(address(this).balance - donationBalance, msg.sender);
	}

	//Keep this low
	function changeMaxCharitiesPerProfile(uint8 _maxCharitiesPerProfile) onlyOwner public {
		maxCharitiesPerProfile = _maxCharitiesPerProfile;
	}

	function removeEmergencyEscape() onlyOwner public {
		canBeDestroyed = false;
	}

	//Temporary escape in case of critical error
	function selfDestruct() onlyOwner public {
		require(canBeDestroyed, "Can no longer be destroyed, sorry");
		emit KilledContract(address(this).balance, msg.sender);
		selfdestruct(owner);
	}

}