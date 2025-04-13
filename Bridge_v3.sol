/*


███████╗ ██████╗ █████╗ ██╗        ██████╗ ██████╗ ██╗██████╗  ██████╗ ███████╗        ██╗   ██╗██████╗ 
██╔════╝██╔════╝██╔══██╗██║        ██╔══██╗██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝        ██║   ██║╚════██╗
███████╗██║     ███████║██║        ██████╔╝██████╔╝██║██║  ██║██║  ███╗█████╗          ██║   ██║ █████╔╝
╚════██║██║     ██╔══██║██║        ██╔══██╗██╔══██╗██║██║  ██║██║   ██║██╔══╝          ╚██╗ ██╔╝ ╚═══██╗
███████║╚██████╗██║  ██║██║        ██████╔╝██║  ██║██║██████╔╝╚██████╔╝███████╗         ╚████╔╝ ██████╔╝
╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝        ╚═════╝ ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝          ╚═══╝  ╚═════╝ 


*///SPDX-License-Identifier: MIT
pragma solidity 0.8.29; 

interface ERC20Essential 
{

    function balanceOf(address user) external view returns(uint256);
    function transfer(address _to, uint256 _amount) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool);

}


//USDT contract in Ethereum does not follow ERC20 standard so it needs different interface
interface usdtContract
{
    function transferFrom(address _from, address _to, uint256 _amount) external;
    function transfer(address _to, uint256 _amount) external;
}




//*******************************************************************//
//------------------ Contract to Manage Ownership -------------------//
//*******************************************************************//
contract owned
{
    address public owner;
    mapping(address => bool) public signer;

    event OwnershipTransferred(address indexed _from, address indexed _to);
    event SignerUpdated(address indexed signer, bool indexed status);

    constructor() {
        owner = msg.sender;
        //owner does not become signer automatically.
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }


    modifier onlySigner {
        require(signer[msg.sender], 'caller must be signer');
        _;
    }


    function changeSigner(address _signer, bool _status) public onlyOwner {
        signer[_signer] = _status;
        emit SignerUpdated(_signer, _status);
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }


}



    
//****************************************************************************//
//---------------------        MAIN CODE STARTS HERE     ---------------------//
//****************************************************************************//
    
contract SCAIBridge_v3 is owned {
    
    uint256 public orderID;
    uint256 public exraCoinRewards;   // if we give users extra coins to cover gas cost of some initial transactions.
    bool public bridgeStatus = true;
    uint256 public peggedTokenFeePercentage = 5; // 0.5%
    uint256 public scaiBurnFeePercentage = 20;  // 2%
    address public peggedTokenFeeRecipient;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public USDScontract = 0x3A15028e6b1d1040f64BC19f0D89A336eA45D8a5;
    address public USDTcontractInEthereum = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public SCAIcontractAddress = 0x774b9Dd3977a7556BF16Cc22B74b2991e4511E13;
    

    // This generates a public event of coin received by contract
    event CoinIn(uint256 indexed orderID, address indexed inputTokenAddress, address indexed user, uint256 value, uint256 chainID, address outputTokenAddress, uint256 fee);
    event TokenIn(uint256 indexed orderID, address indexed inputTokenAddress, address indexed user, uint256 value, uint256 chainID, address outputTokenAddress, uint256 fee);
    event CoinOut(uint256 indexed orderID, address indexed outputTokenAddress, address indexed user, uint256 value, uint256 chainID);
    event TokenOut(uint256 indexed orderID, address indexed outputTokenAddress, address indexed user, uint256 value, uint256 chainID);
   

    constructor(
        address _peggedTokenFeeRecipient
    ) {
        peggedTokenFeeRecipient = _peggedTokenFeeRecipient;
    }
    
    receive () external payable {
        //nothing happens for incoming fund
    }
    
    //the coins will remains in this smart contract
    function coinIn(uint256 outputChainID, address outputCurrency) external payable returns(bool){
        require(bridgeStatus, "Bridge is inactive");
        orderID++;
        uint256 fee;

        //deducting the fee 
        //for scai network, burn fee will be applied, because it is dealing with SCAI
        //for other blockchains, peg fee will be applied, because it is dealing with other peg tokens.
        if (block.chainid == 34) {
            fee = (msg.value * scaiBurnFeePercentage) / 1000;
            payable(burnAddress).transfer(fee);
        }
        else{
            fee = (msg.value * peggedTokenFeePercentage) / 1000;
            payable(peggedTokenFeeRecipient).transfer(fee);
        }
        

        emit CoinIn (orderID, address(0), msg.sender, (msg.value - fee), outputChainID, outputCurrency, fee);
        return true;
    }
    

    
    //fund remains in this smart contract
    function tokenIn(address inputTokenAddress, uint256 tokenAmount, uint256 outputChainID, address outputTokenAddress) external returns(bool){
        require(bridgeStatus, "Bridge is inactive");
        orderID++;
        uint256 fee;
        
        if(inputTokenAddress == USDTcontractInEthereum){
            //There should be different interface for the USDT Ethereum contract
            usdtContract(inputTokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
        }else{
            ERC20Essential(inputTokenAddress).transferFrom(msg.sender, address(this), tokenAmount);
        }

        //deducting fee. burn fee for SCAI token movement and pegged token fee for USDS/USDT movement
        if(inputTokenAddress == USDScontract || outputTokenAddress == USDScontract){
            fee = (tokenAmount * peggedTokenFeePercentage) / 1000;
            
            if(inputTokenAddress == USDTcontractInEthereum){
            //There should be different interface for the USDT Ethereum contract
                usdtContract(inputTokenAddress).transfer(peggedTokenFeeRecipient, fee);
            }else{
                ERC20Essential(inputTokenAddress).transfer(peggedTokenFeeRecipient, fee);
            }
        }
        else if(inputTokenAddress == SCAIcontractAddress){
            fee = (tokenAmount * scaiBurnFeePercentage) / 1000;
            ERC20Essential(inputTokenAddress).transfer(burnAddress, fee);
        }


        emit TokenIn(orderID, inputTokenAddress, msg.sender, (tokenAmount-fee), outputChainID, outputTokenAddress, fee);
        return true;
    }
    

    function coinOut(address user, uint256 amount, uint256 _orderID, uint256 inputChainID) external onlySigner returns(bool){
        require(bridgeStatus, "Bridge is inactive");
        payable(user).transfer(amount);
        emit CoinOut(_orderID, address(0), user, amount, inputChainID);

        return true;
    }

    
    function tokenOut(address outputTokenAddress, address user, uint256 tokenAmount, uint256 _orderID, uint256 inputChainID) external onlySigner returns(bool){
            require(bridgeStatus, "Bridge is inactive");
          
            
            if(outputTokenAddress == USDTcontractInEthereum){
            //There should be different interface for the USDT Ethereum contract
                usdtContract(outputTokenAddress).transfer(user, tokenAmount);
            }else{
                ERC20Essential(outputTokenAddress).transfer(user, tokenAmount);
            }

            if(exraCoinRewards > 0 && address(this).balance >= exraCoinRewards && user.balance == 0 ){
                payable(user).transfer(exraCoinRewards);
            }
            emit TokenOut(_orderID, outputTokenAddress, user, tokenAmount, inputChainID);
        
        return true;
    }


    //admin functions

    function setExraCoinsRewards(uint256 _exraCoinRewards) external onlyOwner{
        exraCoinRewards = _exraCoinRewards;
    }

    function setBridgeStatus(bool status) external onlyOwner {
        bridgeStatus = status;
    }

    function setPeggedTokenFeePercentage(uint256 fee) external onlyOwner {
        peggedTokenFeePercentage = fee;
    }

    function setScaiBurnFeePercentage(uint256 fee) external onlyOwner {
        scaiBurnFeePercentage = fee;
    }

    function setPeggedTokenFeeRecipient(address _newRecipient) external onlyOwner {
        peggedTokenFeeRecipient = _newRecipient;
    }

    function setUSDScontract(address _USDScontract) external onlyOwner{
        USDScontract = _USDScontract;
    }

    function setSCAIcontract(address _SCAIcontract) external onlyOwner{
        SCAIcontractAddress = _SCAIcontract;
    }

}
