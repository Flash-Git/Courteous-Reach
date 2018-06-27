pragma solidity ^0.4.24;

contract Donator is Ownable {
	
	uint public contractBalance;
    
	mapping(address => charity) public charities;
	//User profiles
	mapping(address => profile) profiles;
    //Array of valid charities
   	address[] public validCharities;

    struct profile{
        address[5] charities;
        uint8[5] share;
        uint16 totalShares;
        uint8 numOfCharities;
    }
    
	struct donator {
		address addr;
		mapping(address => token) tokens;
	}
    
	struct token {
		address addr;
		string name;
		string symbol;
		bool valid;
	}
    
	struct charity {
		bool valid;
		uint balance;
	}

	function addCharityToProfile(address _charity, uint8 _share) public {
		require(charities[_charity].valid, "Invalid charity");
		uint8 num = profiles[msg.sender].numOfCharities;
		if(num<5) {
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
	
	function resetProfile() public {
	    delete profiles[msg.sender];
	}
    
	//TODO set up sending throuh 3rd party
	//Straight donate
	function donate(uint _amount, address _charity) public payable {
		checkAmount(_amount);
		checkCharity(_charity);
		contractBalance += (msg.value-_amount);
		charities[_charity].balance += _amount;

	}
    
    //Is it more efficient to have these repeated outside functions 
    function checkCharity(address _charity) view internal {
		require(charities[_charity].valid, "Invalid charity");
	}

    function checkAmount(uint _amount) view internal {
		require(_amount <= msg.value, "Attempting to donate more than was sent");
	}

	function checkPerc(uint8 _percentage) view internal {
		require(_percentage  <= 100, "Invalid percentage");
	}

	//Straight % donate
	function donateWithPerc(uint8 _percentage, address _charity) public payable {
		checkCharity(_charity);
		checkPerc(_percentage);
		uint donateAmt = (msg.value*_percentage)/100;//TODO safemath
		contractBalance += (msg.value-donateAmt);
		charities[_charity].balance+=donateAmt;
	}

    function donateWithProfile(uint _amount) public payable {//safemath
		checkAmount(_amount);
		uint donated;
		for(uint i = 0; i<profiles[msg.sender].numOfCharities; i++){
			checkCharity(profiles[msg.sender].charities[i]);
			uint amount = profiles[msg.sender].share[i]/profiles[msg.sender].totalShares*_amount;
			charities[profiles[msg.sender].charities[i]].balance+=amount;//charities
			donated+=amount;
		}
		contractBalance+=(_amount-donated);
	}

	function tempValidateCharity(address _charity) public {
	    require(!charities[_charity].valid, "Charity already validated");
		charities[_charity].valid = true;
		validCharities.push(_charity);
	}
    
	function payoutAllCharities() public {
		for(uint16 i=0; i<validCharities.length; i++){
			checkCharity(validCharities[i]);
		    validCharities[i].transfer(charities[validCharities[i]].balance);
		    charities[validCharities[i]].balance=0;
		}
	}

	function payoutCharity(address _charity) public {
		checkCharity(_charity);
		_charity.transfer(charities[_charity].balance);
		charities[_charity].balance=0;
	}

    
	function sendEther() internal {
        
	}
	   
	function sendTokens() internal {
        
	}
    
	function withdrawAll() onlyOwner public {//TODO handle reentancy attack
		msg.sender.transfer(contractBalance);
        contractBalance = 0;
	}

}