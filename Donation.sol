pragma solidity 0.4.24;

contract Donator is Ownable {

    //Total donation ether (in wei) ready to send
	uint public donationBalance;
	bool internal canBeDestroyed = true;

    //Every address is a potential charity
	mapping(address => charity) public charities;
	//Every address has a donation profile
	mapping(address => profile) public profiles;
    //Array of valid charities
   	address[] internal validCharities;

	//Donations done with profile are split between the chosen charities based on shares        
    struct profile {
    	address[5] charities;//Charities on profile
        uint[5] share;//Shares per Charity
        uint totalShares;//Gas efficient to keep track of total shares(?)
        uint8 numOfCharities;//Gas efficient by knowing number of charities per profile
    }
    
    /* TODO Handle tokens 
	struct token {
		address addr;
		string name;
		string symbol;
		bool valid;
	}*/

	struct charity {
		bool valid;
		uint balance;
	}
	
	event DonationReceived(address indexed _from, uint indexed _amount, address indexed _charity);
	event DonationSent(uint indexed _amount, address indexed _to);
    event Withdrawal(uint indexed _amount, address indexed _to);
    event ValidatedCharity(address indexed _charity);
    event InvalidatedCharity(address indexed _charity);
    
	function validateCharity(address _charity) onlyOwner public {
	    require(!charities[_charity].valid, "Attempting to validate a valid charity");
		charities[_charity].valid = true;
		validCharities.push(_charity);
		emit ValidatedCharity(_charity);
	}

	function invalidateCharity(address _charity) onlyOwner public {
	    require(charities[_charity].valid, "Attempting to invalidate an invalid charity");
		charities[_charity].valid = false;
		validCharities.push(_charity);
		if(validCharities.length == 1){
			delete validCharities[0];
			return;
		}
		//Replace the invalid charity with the last one
		for(uint i = 0; i < validCharities.length; i++){
			if(validCharities[i] == _charity){
				validCharities[i] = validCharities[validCharities.length-1];
				delete validCharities[validCharities.length-1];
				return;
			}
		}
        emit InvalidatedCharity(_charity);
	}

	function addCharityToProfile(address _charity, uint8 _share) public {//Max _share size is 255
		require(charities[_charity].valid, "Invalid charity");
		uint8 num = profiles[msg.sender].numOfCharities;
		if(num < 5) {
			profiles[msg.sender].charities[num] = _charity;
			profiles[msg.sender].share[num] = _share;
			profiles[msg.sender].numOfCharities++;
			profiles[msg.sender].totalShares += _share;
		}
	}
    
    //Does not technically remove the charity from profile, it still takes up a slot
	function removeCharityFromProfile(uint _num) public {
		profiles[msg.sender].totalShares -= profiles[msg.sender].share[_num];
	    profiles[msg.sender].share[_num] = 0;
	}
	
	function editCharityFromProfile(uint8 _num, address _charity, uint8 _share) public {//Max _share size is 255
	    require(_num <= profiles[msg.sender].numOfCharities, "Attempting to edit outside of array");
	    profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].share[_num] = _share;
	}
	
	function resetProfile() public {//TODO check this works as expected
	    delete profiles[msg.sender];
	}
    
	//Rejects potentially unintentional donations
	function() public payable {
		require(msg.data.length == 0, "Invalid function");
		emit DonationReceived(msg.sender, msg.value, address(this));
	}

	//TODO set up sending throuh 3rd party
	//Direct amt donate
	function donateWithAmt(uint _amount, address _charity) public payable {
		checkAmount(_amount);
		checkCharity(_charity);
		charities[_charity].balance += _amount;
		donationBalance += _amount;
		emit DonationReceived(msg.sender, _amount, _charity);
	}

	//Direct % donate
	function donateWithPerc(uint _percentage, address _charity) public payable {
		checkCharity(_charity);
		checkPerc(_percentage);
		uint donateAmt = (msg.value * _percentage) / 100;
		charities[_charity].balance += donateAmt;
		donationBalance += donateAmt;
		emit DonationReceived(msg.sender, donateAmt, _charity);
	}

	//Direct profile donate
    function donateWithProfile(uint _amount) public payable {
		checkAmount(_amount);
		require(profiles[msg.sender].totalShares > 0, "Profile requires more than 0 shares");
		uint donated;
		for(uint8 i = 0; i < profiles[msg.sender].numOfCharities; i++){
			checkCharity(profiles[msg.sender].charities[i]);
			uint donateAmt = _amount * profiles[msg.sender].share[i] / profiles[msg.sender].totalShares;
			charities[profiles[msg.sender].charities[i]].balance += donateAmt;
			donated += donateAmt;
			emit DonationReceived(msg.sender, donateAmt, profiles[msg.sender].charities[i]);
		}
		donationBalance += donated;
	}
    
    //Payout all valid charities
	function payoutAllCharities(uint _minimumPayout) public {
		for(uint i = 0; i < validCharities.length; i++){
			checkCharity(validCharities[i]);
			uint amtToPayout = charities[validCharities[i]].balance; 
			if(amtToPayout < _minimumPayout || amtToPayout == 0){
				continue;
			}
		    charities[validCharities[i]].balance = 0;
		    donationBalance -= amtToPayout;
		    validCharities[i].transfer(amtToPayout);
		    emit DonationSent(amtToPayout, validCharities[i]);
		}
	}
	
	//Force payout an individual charity
	function payoutCharity(address _charity) public {
		checkCharity(_charity);
		uint amtToPayout = charities[_charity].balance;
		charities[_charity].balance = 0;
	    donationBalance -= amtToPayout;
		_charity.transfer(amtToPayout);
		emit DonationSent(amtToPayout, _charity);
	}

	//Is it more efficient to have these repeated without functions?
    function checkCharity(address _charity) view internal {
		require(charities[_charity].valid, "Invalid charity");
	}

    function checkAmount(uint _amount) view internal {
		require(_amount <= msg.value, "Attempting to donate more than was sent");
	}

	function checkPerc(uint _percentage) pure internal {
		require(_percentage  <= 100, "Invalid percentage");
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
	
	function removeEmergencyEscape() onlyOwner public {
	    canBeDestroyed = false;
	}
	
	//Temporary escape in case of critical error
	function selfDestruct() onlyOwner public {
	    require(canBeDestroyed, "Can no longer be destroyed, sorry");
	    emit Withdrawal(address(this).balance, msg.sender);
	    selfdestruct(owner);
	}

}