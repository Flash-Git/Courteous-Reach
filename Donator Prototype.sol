pragma solidity ^0.4.24;

//Gas costs are too high
contract DonatorPrototype is Ownable{
    //"Donation" in this contract means deposited ether that was caught
    //by the fallback function, not charity donations
    
    //Maps an array of donations to each address
	mapping(address => donation[]) public donationMap;
	//Maps an unsigned integer that represents the start of each array to each address
	mapping(address => uint) public donationMapIndex;
	//Ordered array of donations being held
	indexedDon[] public activeDons;
    //Funds available for withdrawal
	uint public contractBalance;

	struct donation{
		address donator;
		uint expirationTime;
		uint amount;
	}

	struct indexedDon{
	    address donator;
	    uint index;//
	}

	//If you send eth to the contract, it will be withdrawable for 2 days
	//then considered a donation and added to the contract's withdrawable balance
	function() public payable {
		addDonation();
	}
	
	function addDonation() private {
	    require(msg.value>0, "Empty Donation");
	    //If sender has sent at least 10 donations without a 2 day gap then skip recall period until they are cleared
	    if(donationMap[msg.sender].length>10){
	    	contractBalance+=msg.value;
	    	return;
	    }
	    //If contract has at least 50 active donations then skip recall period
	    if(activeDons.length>=50){//50 picked out of thin air TODO: do some research and make it a var
	    	contractBalance+=msg.value;
	    	return;
	    }
	    donation memory newDonation;
	    newDonation.donator = msg.sender;
	    newDonation.expirationTime = now + 2 days;
	    newDonation.amount = msg.value;
	    indexedDon memory newIndexedDon;
	    newIndexedDon.donator = msg.sender;
	    newIndexedDon.index = donationMap[msg.sender].length;
	    activeDons.push(newIndexedDon);
	    donationMap[msg.sender].push(newDonation);
	}
    
	indexedDon[] newActiveDons;//TODO not sure if there is a way to make this memory
	function handleContractDonations() public {//Expensive and gets more expensive the less it's called
		uint counter = 0;
		donation memory currentDon;
		while(counter<activeDons.length){
		    //Gets the donation using the index
		    currentDon = donationMap[activeDons[counter].donator][activeDons[counter].index];
		    if(currentDon.amount==0||currentDon.expirationTime<now){//has been set to 0 or has expired
		        contractBalance += currentDon.amount;
		        donationMapIndex[activeDons[counter].donator]++;//This is required to be done out of the if()
		        if(donationMapIndex[activeDons[counter].donator] == donationMap[activeDons[counter].donator].length){
		            //delete array if index reaches map array.length (empty array with a nonzero length)
		            delete donationMap[activeDons[counter].donator];
	                donationMapIndex[activeDons[counter].donator]=0;
		        }else{
		            //sets all values to 0 at this index of the map array at this address
		            delete donationMap[activeDons[counter].donator][activeDons[counter].index];
		        }
		        counter++;
		    }else{//counter = number of donations to remove
		        break;
		    }
		}
		while(counter<activeDons.length){//hasn't expired
	    	//Gets the donation using the index
    	    currentDon = donationMap[activeDons[counter].donator][activeDons[counter].index];
		    if(currentDon.amount==0){//if amount has been manually set to 0
		        donationMapIndex[activeDons[counter].donator]++;
		        if(donationMapIndex[activeDons[counter].donator] == donationMap[activeDons[counter].donator].length){
		            //delete array if index reaches length (empty array with a nonzero length)
		            delete donationMap[activeDons[counter].donator];
	                donationMapIndex[activeDons[counter].donator]=0;
		        }else{
		            delete donationMap[activeDons[counter].donator][activeDons[counter].index];
		        }
		        counter++;
		        continue;
		    }
		    //add all active donations to the new index array
		    indexedDon memory newIndexedDon;
	        newIndexedDon.donator = activeDons[counter].donator;
	        newIndexedDon.index = activeDons[counter].index;
	        newActiveDons.push(newIndexedDon);
	        counter++;
		}
		activeDons = newActiveDons;
		delete newActiveDons;
	}

	//Recover eth sent to the contract
	function recallEth() public{
		uint length = donationMap[msg.sender].length; 
		require(length > 0, "No Eth to withdraw");
		uint recallableEth;
		for(uint i=donationMapIndex[msg.sender];i<length;i++){//Only iterate through the active donations
            if(donationMap[msg.sender][i].amount>0){
                recallableEth+=donationMap[msg.sender][i].amount;
                donationMap[msg.sender][i].amount = 0;
            }
		}
		handleContractDonations();//yikes
        msg.sender.transfer(recallableEth);
	}
    
	function withdrawAll() onlyOwner public {
		handleContractDonations();
	    require(contractBalance>0, "Nothing to withdraw");
        msg.sender.transfer(contractBalance);
        contractBalance=0;
	}
}