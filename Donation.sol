pragma solidity ^0.4.24;

contract Donator is Ownable {
	
	uint public contractBalance;
    
	mapping(address => bool) public charities;
	//User profiles
	mapping(address => profile) profiles;
    
    struct profile{
        address[5] charities;
        uint8[5] share;
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
    
	function addCharityToProfile(address _charity, uint8 _share) public {
		require(charities[_charity], "Invalid charity");
		uint8 num = profiles[msg.sender].numOfCharities;
		if(num<5) {
			profiles[msg.sender].charities[num] = _charity;
			profiles[msg.sender].share[num] = _share;
			profiles[msg.sender].numOfCharities++;
		}
	}
    
	function removeCharityFromProfile(uint8 _num) public {
	    profiles[msg.sender].share[_num] = 0;
	}
	
	function editCharityFromProfile(uint8 _num, address _charity, uint8 _share) public {
	    require(_num<=profiles[msg.sender].numOfCharities, "Editing outside of array");
	    profiles[msg.sender].charities[_num] = _charity;
		profiles[msg.sender].share[_num] = _share;
	}
	
	function resetProfile() public {
	    delete charities[msg.sender];
	}
    
	//TODO set up sending throuh 3rd party
	function donate(uint _amount, address _charity) public payable {
		checkVars(_amount, _charity);
		contractBalance+=(msg.value-_amount);
	}
    
	function checkVars(uint _amount, address _charity) view internal {
		require(_amount<=msg.value, "Attempting to donate more than is being sent");
		require(charities[_charity], "Invalid charity");
	}
    
	function sendEther() internal {
        
	}
	   
	function sendTokens() internal {
        
	}
    
	function withdrawAll() onlyOwner public {//TODO handle reentancy attack
		msg.sender.transfer(contractBalance);
        contractBalance=0;
	}

}