// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./Varonve.sol"; // Ensure this path is correct
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract VaronveStaking is Ownable, ReentrancyGuard {
    
    Varonve public varonve;

    constructor(address varonveAddress) Ownable(msg.sender) {
        varonve = Varonve(varonveAddress);
    }

    struct stakedNFT{
        uint NFTID;
        uint NFTLevel;
        uint lastBalanceUpdateTime;
        uint NFTXPMultiplier;
        uint balance;
    }
    
    mapping (address => mapping (uint => bool)) isStakerOfID;
    mapping (address => stakedNFT[]) stakedNFTs;
    mapping (address => uint) public totalStakedPerAddress;
    mapping (address => mapping(uint => bool)) toRemove;

    bool isPaused = false;

    uint bonusPerNFTStake = 500;
    uint period = 30; //Real value is 86400, changed for test reasons
    uint xpPerPeriod = 10000;
    uint baseMultiplier = 1;
    uint levelTwoMultiplier = 2;
    uint LevelThreeMultiplier = 3;
    uint levelTwoPrice = 200000;
    uint levelThreePrice = 500000;
    uint public totalStakedNFTs;

    event Staked(address indexed user, uint256 tokenID);
    event Unstaked(address indexed user, uint256 tokenID);


    // MODIFIERS

    modifier isOwnerOfAll(uint256[] memory IDBatch){
        bool valid = true;
        for(uint i=0; i<IDBatch.length; i++){
            if(varonve.ownerOf(IDBatch[i]) != msg.sender){
                valid = false;
                break;
            }
        }
        require(valid, "User is not the owner of all NFTs");
        _;
    }  


    modifier isStakerOfAll(uint256[] memory IDBatch){
        bool valid = true;
        for(uint i=0; i<IDBatch.length; i++){
            if(isStakerOfID[msg.sender][IDBatch[i]] != true){
                valid = false;
                break;
            }
        }
        require(valid, "User is not the staker of all NFTs");
        _;
    }

    
    modifier updateXP(address _address) {
        for(uint i=0; i<stakedNFTs[_address].length; i++){
            updateRewardSingleNFT(_address,stakedNFTs[_address][i].NFTID);
        }

        _;
    }  




    // STAKE FUNCTIONS

    function stakeNFTs(uint256[] memory IDBatch) public nonReentrant updateXP(msg.sender) isOwnerOfAll(IDBatch){
       require(isPaused == false, "Staking is not active. You can still unstake your NFTs.");
       for (uint i=0; i<IDBatch.length; i++){
            varonve.transferFrom(msg.sender, address(this), IDBatch[i]);
            
            stakedNFTs[msg.sender].push(
                stakedNFT(IDBatch[i],1,block.timestamp,baseMultiplier,0)
            );
            isStakerOfID[msg.sender][IDBatch[i]] = true;
            emit Staked(msg.sender, IDBatch[i]);
       }
       
       totalStakedPerAddress[msg.sender] += IDBatch.length;
       totalStakedNFTs += IDBatch.length;
       
    }

    function unstakeNFTs(uint256[] memory IDBatch) public nonReentrant updateXP(msg.sender) isStakerOfAll(IDBatch){
        for (uint i=0; i<IDBatch.length; i++){
            varonve.transferFrom(address(this), msg.sender, IDBatch[i]);
            removeSingleItem(IDBatch[i]);
            isStakerOfID[msg.sender][IDBatch[i]] = false;
            emit Unstaked(msg.sender, IDBatch[i]);
        }
    
        totalStakedPerAddress[msg.sender] -= IDBatch.length;
        totalStakedNFTs -= IDBatch.length;
        
    }

    // XP MODIFICATIONS

    function levelUP(uint id) public nonReentrant isStakerOfAll(viewStakedNFTs(msg.sender)) updateXP(msg.sender){
        
        if(stakedNFTs[msg.sender][getIndexOfItem(id)].NFTLevel == 1){
            spendXP(levelTwoPrice, msg.sender);
            stakedNFTs[msg.sender][getIndexOfItem(id)].balance++;
        }else if(stakedNFTs[msg.sender][getIndexOfItem(id)].NFTLevel == 2){
            spendXP(levelThreePrice, msg.sender);
            stakedNFTs[msg.sender][getIndexOfItem(id)].balance++;
        }else{
            revert("Your NFT reached max level.");
        }
    }


    function spendXP(uint amount, address _address) public{
        require(showRewards(_address) >= amount, "Your balance is not Enough");
        require(stakedNFTs[_address].length > 0, "No NFTs staked");

        uint spent = 0;
        uint amountPerNFT = amount / stakedNFTs[_address].length;
        for(uint i=0; i<stakedNFTs[_address].length; i++){
            if(stakedNFTs[_address][i].balance >= amountPerNFT){
                stakedNFTs[_address][i].balance -= amountPerNFT;
                spent += amountPerNFT;
            }else{
                stakedNFTs[_address][i].balance = 0;
                spent += stakedNFTs[_address][i].balance;
            }
        }

        stakedNFTs[_address][stakedNFTs[_address].length-1].balance -= (amount-spent);

    }

    function addXP(uint amount, address _address) public{
        uint paid = 0;
        uint payPerNFT = amount / stakedNFTs[msg.sender].length;
        for(uint i=0; i<stakedNFTs[_address].length; i++){
            if(stakedNFTs[_address][i].balance >= payPerNFT){
                stakedNFTs[_address][i].balance -= payPerNFT;
                paid += payPerNFT;
            }else{
                stakedNFTs[_address][i].balance = 0;
                paid += stakedNFTs[_address][i].balance;
            }
        }

        stakedNFTs[_address][stakedNFTs[_address].length-1].balance += (amount-paid);
    }




    // INFO FUNCTIONS
    
    //ViewAllNFTs = Shows all the NFTs that user have.
    function viewAllNFTs(address _address) public view returns(uint[] memory){
        uint totalOwned = varonve.balanceOf(_address);
        require(totalOwned>=1, "Address does not have a Varonve NFT");
        uint index = 0;
        uint[] memory temp = new uint[](totalOwned);
        
        for(uint i=1; i<=varonve.totalSupply(); i++){
            if(varonve.ownerOf(i) == _address){
                temp[index] = i;
                index++;
                if (index == totalOwned) {
                    break;
                }
            }
        }
        return temp;
    }
    

    // INFO FUNCTION

    // Returns all the staked NFTs by address.
    function viewStakedNFTs(address _address) public view returns(uint[] memory){
        uint length = stakedNFTs[_address].length;
        uint[] memory temp = new uint[](length);

        for(uint i=0; i<length; i++){
            temp[i] = stakedNFTs[_address][i].NFTID;
        }
        return temp;
    }


    // Used for showing the user balance without updating.
    function showRewards(address _address) public view returns(uint){
        stakedNFT[] memory NFTs = stakedNFTs[_address];
        uint sum = 0;
        uint currentTimeStamp = block.timestamp;

        for(uint i=0; i<NFTs.length; i++){
            sum += (NFTs[i].balance + ((((currentTimeStamp - NFTs[i].lastBalanceUpdateTime) / period) * ((xpPerPeriod * NFTs[i].NFTXPMultiplier) + ((NFTs.length -1) * bonusPerNFTStake) ))));
        }      
        return sum;
    }


    // Updates balance in {StakedNFT.balance} of the user and selected ID.
    function updateRewardSingleNFT(address _address, uint id) internal{
        
        stakedNFT[] storage NFTs = stakedNFTs[_address];

        for(uint i=0; i<stakedNFTs[_address].length; i++){
            if(NFTs[i].NFTID == id){
                NFTs[i].balance += ((((block.timestamp - NFTs[i].lastBalanceUpdateTime) / period) * ((xpPerPeriod * NFTs[i].NFTXPMultiplier) + ((NFTs.length -1) * bonusPerNFTStake) )));
                break;
            }else{
                continue;
            }
        }
    }


    // TOOLS
    
    function getIndexOfItem(uint idOfIndex) internal view returns(uint){
        for(uint i=0; i<stakedNFTs[msg.sender].length; i++){
            if(idOfIndex == stakedNFTs[msg.sender][i].NFTID){
                return i;
            }
        }
        revert("Item not found.");
    }

    function removeSingleItem(uint idToRemove) internal {
        stakedNFTs[msg.sender][getIndexOfItem(idToRemove)] = stakedNFTs[msg.sender][stakedNFTs[msg.sender].length-1];
        stakedNFTs[msg.sender].pop();
    }
    
    function togglePause() external onlyOwner nonReentrant{
        isPaused = !isPaused;
    }
    

    /* ----------------- RAFFLE SYSTEM ----------------- */


    // TO BE UPDATED (NOT THE LATEST VERSION)

    event JoinedGiveaway(address indexed buyer, uint amount, uint raffleID);

    uint raffleCounter = 1;


    struct raffle{
        uint id;
        string rewardName;
        uint rewardAmount;
        uint startTime;
        uint endTime;
        uint price;
        uint totalTicketsBought;
        uint image;
    }

    struct ticket{
        address owner;
        uint raffleID;
        uint amount;
    }

    raffle[] raffles;

    mapping (address => mapping(uint => ticket)) ticketsBought;
    mapping (address => mapping(uint => bool)) isWinnerOf;
    mapping (address => uint) balanceToReturn;
    mapping (uint => address[]) joinedAddresses;
    mapping (uint => bool) losersPaidBack;
    
    // RAFFLE TOOLS
    
    function createRaffle(uint _endTime, string memory _raffleName, uint _rewardAmount, uint _price, uint _image)public onlyOwner{
        raffles[raffleCounter-1] = raffle(raffleCounter, _raffleName, _rewardAmount, block.timestamp, _endTime, _price, 0, _image);
        raffleCounter ++;
    }

    function addJoinerToList(address _address, uint id) internal{
        address[] storage list = joinedAddresses[id];
        for(uint i=0; i<list.length; i++){
            if(list[i] == _address){
                break;
            }else{
                list[list.length] = _address;
            }
        }
    }

    
    function viewAllEntriesByRaffleId(uint id) external view returns(ticket[] memory){
        ticket[] memory list;
        for(uint i=0; i<joinedAddresses[id].length; i++){
            list[i] = ticketsBought[joinedAddresses[id][i]][id];
        }
        return list;
    }



    function buyTicket(uint raffleid, uint amount) public updateXP(msg.sender) nonReentrant {
        require(raffleid <= raffles.length, "Raffle ID Does not exist");
        raffle storage choosenRaffle = raffles[raffleid-1]; // points raffle at the index (raffleid-1).
        require(block.timestamp >= choosenRaffle.startTime, "Raffle has not started");
        require(block.timestamp <= choosenRaffle.endTime, "Raffle is ended");
        require(showRewards(msg.sender) >= amount * choosenRaffle.price, "Your balance is not enough.");
        require(amount > 0, "Amount must be greater than zero");

        if(ticketsBought[msg.sender][raffleid].raffleID != raffleid){
            ticketsBought[msg.sender][raffleid] = ticket(msg.sender, raffleid, amount);
        }

        spendXP(choosenRaffle.price, msg.sender);
        choosenRaffle.totalTicketsBought += amount;
        ticketsBought[msg.sender][raffleid].amount += amount;
        addJoinerToList(msg.sender, raffleid);

        emit JoinedGiveaway(msg.sender, amount, raffleid);
        
    }

    function insertWinnerAddresses(address[] memory _raffleWinners, uint id) public onlyOwner{
        for(uint i=0; i<_raffleWinners.length; i++){
            isWinnerOf[_raffleWinners[i]][id] = true;
        }
    }


    function returnLoserTicketXPs(uint id) public onlyOwner{
        uint index = id - 1;
        require(losersPaidBack[id]==false, "Ticket prices already paid back");
        require(raffles[index].endTime >= block.timestamp);
        uint valueToReturn;
        for(uint i=0; i<joinedAddresses[id].length; i++){
            if(isWinnerOf[joinedAddresses[id][i]][id] == false){
                valueToReturn = ticketsBought[joinedAddresses[id][i]][id].amount * ((9 * raffles[id].price)/ 10);
                addXP(valueToReturn,joinedAddresses[id][i]);
            }else if(isWinnerOf[joinedAddresses[id][i]][id] == true){
                valueToReturn = (ticketsBought[joinedAddresses[id][i]][id].amount -1) * ((9 * raffles[id].price)/ 10);
                addXP(valueToReturn,joinedAddresses[id][i]);
            }
        }
    }


}


interface IERC721{

    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(address tokenId) external view returns (address);
    function transferFrom(address from, address to, uint tokenId) external returns(bool);
    function approve(address to, uint256 tokenId) external returns(bool);
    function setApprovalForAll(address operator, bool approved) external returns(bool);
}
