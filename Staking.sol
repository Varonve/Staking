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

    struct stakedNFT {
        uint256 NFTID;
        uint256 NFTLevel;
        uint256 lastBalanceUpdateTime;
        uint256 NFTXPMultiplier;
        uint256 balance;
    }

    mapping(address => mapping(uint256 => bool)) isStakerOfID;
    mapping(address => stakedNFT[]) stakedNFTs;
    mapping(address => uint256) public totalStakedPerAddress;
    mapping(address => mapping(uint256 => bool)) toRemove;

    bool isPaused = false;

    uint256 bonusPerNFTStake = 500;
    uint256 period = 30; //Real value is 86400, changed for test reasons
    uint256 xpPerPeriod = 10000;
    uint256 baseMultiplier = 1;
    uint256 levelTwoMultiplier = 2;
    uint256 LevelThreeMultiplier = 3;
    uint256 levelTwoPrice = 200000;
    uint256 levelThreePrice = 500000;
    uint256 public totalStakedNFTs;

    event Staked(address indexed user, uint256 tokenID);
    event Unstaked(address indexed user, uint256 tokenID);

    // MODIFIERS

    modifier isOwnerOfAll(uint256[] memory IDBatch) {
        bool valid = true;
        for (uint256 i = 0; i < IDBatch.length; i++) {
            if (varonve.ownerOf(IDBatch[i]) != msg.sender) {
                valid = false;
                break;
            }
        }
        require(valid, "User is not the owner of all NFTs");
        _;
    }

    modifier isStakerOfAll(uint256[] memory IDBatch) {
        bool valid = true;
        for (uint256 i = 0; i < IDBatch.length; i++) {
            if (isStakerOfID[msg.sender][IDBatch[i]] != true) {
                valid = false;
                break;
            }
        }
        require(valid, "User is not the staker of all NFTs");
        _;
    }

    modifier updateXP(address _address) {
        for (uint256 i = 0; i < stakedNFTs[_address].length; i++) {
            updateRewardSingleNFT(_address, stakedNFTs[_address][i].NFTID);
        }

        _;
    }

    // STAKE FUNCTIONS

    function stakeNFTs(uint256[] memory IDBatch)
        public
        nonReentrant
        updateXP(msg.sender)
        isOwnerOfAll(IDBatch)
    {
        require(
            isPaused == false,
            "Staking is not active. You can still unstake your NFTs."
        );
        for (uint256 i = 0; i < IDBatch.length; i++) {
            varonve.transferFrom(msg.sender, address(this), IDBatch[i]);

            stakedNFTs[msg.sender].push(
                stakedNFT(IDBatch[i], 1, block.timestamp, baseMultiplier, 0)
            );
            isStakerOfID[msg.sender][IDBatch[i]] = true;
            emit Staked(msg.sender, IDBatch[i]);
        }

        totalStakedPerAddress[msg.sender] += IDBatch.length;
        totalStakedNFTs += IDBatch.length;
    }

    function unstakeNFTs(uint256[] memory IDBatch)
        public
        nonReentrant
        updateXP(msg.sender)
        isStakerOfAll(IDBatch)
    {
        for (uint256 i = 0; i < IDBatch.length; i++) {
            varonve.transferFrom(address(this), msg.sender, IDBatch[i]);
            removeSingleItem(IDBatch[i]);
            isStakerOfID[msg.sender][IDBatch[i]] = false;
            emit Unstaked(msg.sender, IDBatch[i]);
        }

        totalStakedPerAddress[msg.sender] -= IDBatch.length;
        totalStakedNFTs -= IDBatch.length;
    }

    // XP MODIFICATIONS

    function levelUP(uint256 id)
        public
        nonReentrant
        isStakerOfAll(viewStakedNFTs(msg.sender))
        updateXP(msg.sender)
    {
        if (stakedNFTs[msg.sender][getIndexOfItem(id)].NFTLevel == 1) {
            spendXP(levelTwoPrice, msg.sender);
            stakedNFTs[msg.sender][getIndexOfItem(id)].balance++;
        } else if (stakedNFTs[msg.sender][getIndexOfItem(id)].NFTLevel == 2) {
            spendXP(levelThreePrice, msg.sender);
            stakedNFTs[msg.sender][getIndexOfItem(id)].balance++;
        } else {
            revert("Your NFT reached max level.");
        }
    }

    function spendXP(uint256 amount, address _address) public {
        require(showRewards(_address) >= amount, "Your balance is not Enough");
        require(stakedNFTs[_address].length > 0, "No NFTs staked");

        uint256 spent = 0;
        uint256 amountPerNFT = amount / stakedNFTs[_address].length;
        for (uint256 i = 0; i < stakedNFTs[_address].length; i++) {
            if (stakedNFTs[_address][i].balance >= amountPerNFT) {
                stakedNFTs[_address][i].balance -= amountPerNFT;
                spent += amountPerNFT;
            } else {
                stakedNFTs[_address][i].balance = 0;
                spent += stakedNFTs[_address][i].balance;
            }
        }

        stakedNFTs[_address][stakedNFTs[_address].length - 1]
            .balance -= (amount - spent);
    }

    function addXP(uint256 amount, address _address) public {
        uint256 paid = 0;
        uint256 payPerNFT = amount / stakedNFTs[msg.sender].length;
        for (uint256 i = 0; i < stakedNFTs[_address].length; i++) {
            if (stakedNFTs[_address][i].balance >= payPerNFT) {
                stakedNFTs[_address][i].balance -= payPerNFT;
                paid += payPerNFT;
            } else {
                stakedNFTs[_address][i].balance = 0;
                paid += stakedNFTs[_address][i].balance;
            }
        }

        stakedNFTs[_address][stakedNFTs[_address].length - 1]
            .balance += (amount - paid);
    }

    // INFO FUNCTIONS

    //ViewAllNFTs = Shows all the NFTs that user have.
    function viewAllNFTs(address _address)
        public
        view
        returns (uint256[] memory)
    {
        uint256 totalOwned = varonve.balanceOf(_address);
        require(totalOwned >= 1, "Address does not have a Varonve NFT");
        uint256 index = 0;
        uint256[] memory temp = new uint256[](totalOwned);

        for (uint256 i = 1; i <= varonve.totalSupply(); i++) {
            if (varonve.ownerOf(i) == _address) {
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
    function viewStakedNFTs(address _address)
        public
        view
        returns (uint256[] memory)
    {
        uint256 length = stakedNFTs[_address].length;
        uint256[] memory temp = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            temp[i] = stakedNFTs[_address][i].NFTID;
        }
        return temp;
    }

    // Used for showing the user balance without updating.
    function showRewards(address _address) public view returns (uint256) {
        stakedNFT[] memory NFTs = stakedNFTs[_address];
        uint256 sum = 0;
        uint256 currentTimeStamp = block.timestamp;

        for (uint256 i = 0; i < NFTs.length; i++) {
            sum += (NFTs[i].balance +
                (
                    (((currentTimeStamp - NFTs[i].lastBalanceUpdateTime) /
                        period) *
                        ((xpPerPeriod * NFTs[i].NFTXPMultiplier) +
                            ((NFTs.length - 1) * bonusPerNFTStake)))
                ));
        }
        return sum;
    }

    // Updates balance in {StakedNFT.balance} of the user and selected ID.
    function updateRewardSingleNFT(address _address, uint256 id) internal {
        stakedNFT[] storage NFTs = stakedNFTs[_address];

        for (uint256 i = 0; i < stakedNFTs[_address].length; i++) {
            if (NFTs[i].NFTID == id) {
                NFTs[i].balance += (
                    (((block.timestamp - NFTs[i].lastBalanceUpdateTime) /
                        period) *
                        ((xpPerPeriod * NFTs[i].NFTXPMultiplier) +
                            ((NFTs.length - 1) * bonusPerNFTStake)))
                );
                break;
            } else {
                continue;
            }
        }
    }

    // TOOLS

    function getIndexOfItem(uint256 idOfIndex) internal view returns (uint256) {
        for (uint256 i = 0; i < stakedNFTs[msg.sender].length; i++) {
            if (idOfIndex == stakedNFTs[msg.sender][i].NFTID) {
                return i;
            }
        }
        revert("Item not found.");
    }

    function removeSingleItem(uint256 idToRemove) internal {
        stakedNFTs[msg.sender][getIndexOfItem(idToRemove)] = stakedNFTs[
            msg.sender
        ][stakedNFTs[msg.sender].length - 1];
        stakedNFTs[msg.sender].pop();
    }

    function togglePause() external onlyOwner nonReentrant {
        isPaused = !isPaused;
    }

    /* ----------------- RAFFLE SYSTEM ----------------- */

    // TO BE UPDATED (NOT THE LATEST VERSION)

    event JoinedGiveaway(
        address indexed buyer,
        uint256 amount,
        uint256 raffleID
    );

    uint256 raffleCounter = 1;

    struct raffle {
        uint256 id;
        string rewardName;
        uint256 rewardAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        uint256 totalTicketsBought;
        uint256 image;
    }

    struct ticket {
        address owner;
        uint256 raffleID;
        uint256 amount;
    }

    raffle[] raffles;

    mapping(address => mapping(uint256 => ticket)) ticketsBought;
    mapping(address => mapping(uint256 => bool)) isWinnerOf;
    mapping(address => uint256) balanceToReturn;
    mapping(uint256 => address[]) joinedAddresses;
    mapping(uint256 => bool) losersPaidBack;

    // RAFFLE TOOLS

    function createRaffle(
        uint256 _endTime,
        string memory _raffleName,
        uint256 _rewardAmount,
        uint256 _price,
        uint256 _image
    ) public onlyOwner {
        raffles[raffleCounter - 1] = raffle(
            raffleCounter,
            _raffleName,
            _rewardAmount,
            block.timestamp,
            _endTime,
            _price,
            0,
            _image
        );
        raffleCounter++;
    }

    function addJoinerToList(address _address, uint256 id) internal {
        address[] storage list = joinedAddresses[id];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == _address) {
                break;
            } else {
                list[list.length] = _address;
            }
        }
    }

    function viewAllEntriesByRaffleId(uint256 id)
        external
        view
        returns (ticket[] memory)
    {
        ticket[] memory list;
        for (uint256 i = 0; i < joinedAddresses[id].length; i++) {
            list[i] = ticketsBought[joinedAddresses[id][i]][id];
        }
        return list;
    }

    function buyTicket(uint256 raffleid, uint256 amount)
        public
        updateXP(msg.sender)
        nonReentrant
    {
        require(raffleid <= raffles.length, "Raffle ID Does not exist");
        raffle storage choosenRaffle = raffles[raffleid - 1]; // points raffle at the index (raffleid-1).
        require(
            block.timestamp >= choosenRaffle.startTime,
            "Raffle has not started"
        );
        require(block.timestamp <= choosenRaffle.endTime, "Raffle is ended");
        require(
            showRewards(msg.sender) >= amount * choosenRaffle.price,
            "Your balance is not enough."
        );
        require(amount > 0, "Amount must be greater than zero");

        if (ticketsBought[msg.sender][raffleid].raffleID != raffleid) {
            ticketsBought[msg.sender][raffleid] = ticket(
                msg.sender,
                raffleid,
                amount
            );
        }

        spendXP(choosenRaffle.price, msg.sender);
        choosenRaffle.totalTicketsBought += amount;
        ticketsBought[msg.sender][raffleid].amount += amount;
        addJoinerToList(msg.sender, raffleid);

        emit JoinedGiveaway(msg.sender, amount, raffleid);
    }

    function insertWinnerAddresses(address[] memory _raffleWinners, uint256 id)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < _raffleWinners.length; i++) {
            isWinnerOf[_raffleWinners[i]][id] = true;
        }
    }

    function returnLoserTicketXPs(uint256 id) public onlyOwner {
        uint256 index = id - 1;
        require(losersPaidBack[id] == false, "Ticket prices already paid back");
        require(raffles[index].endTime >= block.timestamp);
        uint256 valueToReturn;
        for (uint256 i = 0; i < joinedAddresses[id].length; i++) {
            if (isWinnerOf[joinedAddresses[id][i]][id] == false) {
                valueToReturn =
                    ticketsBought[joinedAddresses[id][i]][id].amount *
                    ((9 * raffles[id].price) / 10);
                addXP(valueToReturn, joinedAddresses[id][i]);
            } else if (isWinnerOf[joinedAddresses[id][i]][id] == true) {
                valueToReturn =
                    (ticketsBought[joinedAddresses[id][i]][id].amount - 1) *
                    ((9 * raffles[id].price) / 10);
                addXP(valueToReturn, joinedAddresses[id][i]);
            }
        }
    }
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(address tokenId) external view returns (address);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external returns (bool);

    function approve(address to, uint256 tokenId) external returns (bool);

    function setApprovalForAll(address operator, bool approved)
        external
        returns (bool);
}
