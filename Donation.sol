pragma solidity ^0.4.24;

contract Donator is Ownable {
	
	uint public contractBalance;
    
    //Every address is a potential charity
	mapping(address => charity) public charities;
	//Every address has a donation profile
	mapping(address => profile) public profiles;
    //Array of valid charities
   	address[] public validCharities;
    //Mininmum needed in charity balance to withdraw
    uint public minimumPayout = 1 *10 ** 16;

	//Donations done with profile are split between the chosen charities based on shares        
    struct profile {
    	address[5] charities;//Charities on profile
        uint8[5] share;//Shares per Charity
        uint16 totalShares;//Gas efficient to keep track of total shares(?)
        uint8 numOfCharities;//Gas efficient by knowing number of charities per profile
    }
    
    //TODO Handle recognition
	struct donator {
		address addr;
		//uint amtDonated;
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

	function validateCharity(address _charity) onlyOwner public {
	    require(!charities[_charity].valid, "Charity already validated");
		charities[_charity].valid = true;
		validCharities.push(_charity);
	}

	function invalidateCharity(address _charity) onlyOwner public {
	    require(charities[_charity].valid, "Charity not valid");
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
	}

	function addCharityToProfile(address _charity, uint8 _share) public {
		require(charities[_charity].valid, "Invalid charity");
		uint8 num = profiles[msg.sender].numOfCharities;
		if(num < 5) {
			profiles[msg.sender].charities[num] = _charity;
			profiles[msg.sender].share[num] = _share;
			profiles[msg.sender].numOfCharities++;
			profiles[msg.sender].totalShares += _share;
		}
	}
    
	function removeCharityFromProfile(uint8 _num) public {
		profiles[msg.sender].totalShares -= profiles[msg.sender].share[_num];
	    profiles[msg.sender].share[_num] = 0;
	}
	
	function editCharityFromProfile(uint8 _num, address _charity, uint8 _share) public {
	    require(_num <= profiles[msg.sender].numOfCharities, "Editing outside of array");
	    profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].share[_num] = _share;
	}
	
	function resetProfile() public {//TODO check this works as expected
	    delete profiles[msg.sender];
	}

	function() public payable {
		contractBalance += msg.value;
	}

	//TODO set up sending throuh 3rd party
	//Direct amt donate
	function donateWithAmt(uint _amount, address _charity) public payable {
		checkAmount(_amount);
		checkCharity(_charity);
		contractBalance += (msg.value - _amount);
		charities[_charity].balance += _amount;
	}

	//Direct % donate
	function donateWithPerc(uint8 _percentage, address _charity) public payable {
		checkCharity(_charity);
		checkPerc(_percentage);
		uint donateAmt = (msg.value * _percentage) / 100;
		contractBalance += (msg.value - donateAmt);
		charities[_charity].balance += donateAmt;
	}

	//Direct profile donate
    function donateWithProfile(uint _amount) public payable {
		checkAmount(_amount);
		uint donated;
		for(uint8 i = 0; i < profiles[msg.sender].numOfCharities; i++){
			checkCharity(profiles[msg.sender].charities[i]);
			uint amount = profiles[msg.sender].share[i] / profiles[msg.sender].totalShares * _amount;
			charities[profiles[msg.sender].charities[i]].balance += amount;
			donated += amount;
		}
		contractBalance += (msg.value - donated);//Scoop up the lost ether
	}
    
    function setMinPayout(uint _minP) public onlyOwner {
        minimumPayout = _minP;
    }
    
    //Payout all valid charities
	function payoutAllCharities() public {
		for(uint16 i = 0; i < validCharities.length; i++){
			checkCharity(validCharities[i]);
			if(charities[validCharities[i]].balance < minimumPayout){
				continue;
			}
		    validCharities[i].transfer(charities[validCharities[i]].balance);
		    charities[validCharities[i]].balance = 0;
		}
	}

	//Force payout an individual charity
	function payoutCharity(address _charity) public {
		checkCharity(_charity);
		_charity.transfer(charities[_charity].balance);
		charities[_charity].balance = 0;
	}

	//Is it more efficient to have these repeated without functions 
    function checkCharity(address _charity) view internal {
		require(charities[_charity].valid, "Invalid charity");
	}

    function checkAmount(uint _amount) view internal {
		require(_amount <= msg.value, "Attempting to donate more than was sent");
	}

	function checkPerc(uint8 _percentage) view internal {
		require(_percentage  <= 100, "Invalid percentage");
	}

	function withdrawAll() onlyOwner public {//TODO handle (pointless) reentancy attack
		msg.sender.transfer(contractBalance);
        contractBalance = 0;
	}

}