// Preguntar solo si tengo tiempo: How does the LinearDutchAuctionFactory knows about the existence of LinearDutchAuction contract on chain? Suppose we try to deploy on chain this src file as it is by the time the factory contract is deployed there would not be a pointer to the regular contract yet created supposing the compiler works line by line in order. Or this does not make sense?
// Linea 58: Creating a variable with the address of the auction, or balanceOf[address], or whatever thing that makes a external call does save some gas, correct? From what I recall from previous lessons, checking balance of the contract directly is safer than checking what our variable says the balance is but at the same time if we are going to make many external calls to gather the same information it makes sense to just collect it once and avoid those expensive calls?
// Linea 160: Preguntarle a ChatGPT.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// If someone wants to sell a token, they create a dutch auction using the linear dutch auction factory.
// In a single transaction, the factory creates the auction and the token is transferred from the user to the auction.

contract LinearDutchAuctionFactory {
    using SafeERC20 for IERC20;
    event AuctionCreated(
        address indexed auction,
        address indexed token,
        uint256 startingPriceEther,
        uint256 startTime,
        uint256 duration,
        uint256 amount,
        address seller
    );

    error InvalidToken();
    error InvalidPrice();
    error InvalidDuration();
    error InvalidSeller();
    error InvalidStartTime();

    function createAuction(
        IERC20 _token,
        uint256 _startingPriceEther,
        uint256 _startTime, // Should be compatible with block.timestamp format.
        uint256 _duration, //The name of the variable _durationSeconds would be more appropiate IMO to be coherent with the other contract.
        uint256 _amount,
        address _seller
    ) external returns (address) {
        if (address(_token) == address(0)) revert InvalidToken();
        if (_startingPriceEther <= 0) revert InvalidPrice();
        if (_duration <= 0) revert InvalidDuration();
        if (_seller == address(0)) revert InvalidSeller();
        if (_startTime < block.timestamp) revert InvalidStartTime();

        LinearDutchAuction auction = new LinearDutchAuction(
            //Vamos a crear un contrato auction del tipo contrato LinearDutchAuction con los parametros instertados por el usuario que van a ser los valores del constructor de LinearDutchAuction contract (que esta mas abajo en el texto).
            _token,
            _startingPriceEther,
            _startTime,
            _duration, //No ponemos amount como argumento porque el contrato LinearDutchAuction tiene solo 5 argumentos en el constructor.
            _seller
        );

        _token.safeTransferFrom(msg.sender, address(auction), _amount); // Transferimos los tokens al contrato de Auction, yo estaba transferiendo a Address(this) que seria el factory contract (el que crea todas las auctions).

        address auctionAddr = address(auction); // Creamos una variable auctionAddr que es igual al address(auction). Es para simplificarr pero no le veo mucho sentido

        emit AuctionCreated(
            //Emitimos el evento
            auctionAddr,
            address(_token),
            _startingPriceEther,
            _startTime,
            _duration,
            _amount,
            _seller
        );

        return auctionAddr; // La function dice que Devolvemos el address de la auction. Podria returnear directo address(auction) , correct?
    }
}

// The auction is a contract that sells the token at a decreasing price until the duration is over.
// The price starts at `startingPriceEther` and decreases linearly to 0 over the `duration`.
// Someone can buy the token at the current price by sending ether to the auction.
// The auction will try to refund the user if they send too much ether.
// The contract directly sends the Ether to the `seller` and does not hold any ether.
// If the price goes to zero, anyone can claim the tokens by calling the contract with msg.value = 0
//Este es el tipo de contrato que creamos con la factory
contract LinearDutchAuction {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    uint256 public immutable startingPriceEther;
    uint256 public immutable startTime;
    uint256 public immutable durationSeconds;
    address public immutable seller;

    error AuctionNotStarted();
    error MsgValueInsufficient();
    error SendEtherToSellerFailed();
    error AlreadySold();

    /*
     * @notice Constructor
     * @param _token The token to sell
     * @param _startingPriceEther The starting price of the token in Ether
     * @param _startTime The start time of the auction.
     * @param _duration The duration of the auction. In seconds
     * @param _seller The address of the seller
     */
    constructor(
        IERC20 _token,
        uint256 _startingPriceEther,
        uint256 _startTime,
        uint256 _durationSeconds,
        address _seller
    ) {
        token = _token;
        startingPriceEther = _startingPriceEther;
        startTime = _startTime;
        durationSeconds = _durationSeconds;
        seller = _seller;
    } //We do not need checks as the checks are already enforced on the factory contract, and we are deploying this contracts through the factory contract.

    /*
     * @notice Get the current price of the token
     * @dev Returns 0 if the auction has ended
     * @revert if the auction has not started yet
     * @revert if someone already purchased the token
     * @return the current price of the token in Ether
     */
    function currentPrice() public view returns (uint256) {
        if (token.balanceOf(address(this)) == 0) revert AlreadySold();
        if (block.timestamp < startTime) revert AuctionNotStarted();

        uint256 elapsed = block.timestamp - startTime;

        if (elapsed >= durationSeconds) return 0;

        uint256 remaining = durationSeconds - elapsed; // I assume everything is measuread in seconds or same format.

        return (startingPriceEther * remaining) / durationSeconds;
    }

    /*
     * @notice Buy tokens at the current price
     * @revert if the auction has not started yet
     * @revert if the auction has ended
     * @revert if the user sends too little ether for the current price
     * @revert if sending Ether to the seller fails
     * @dev Will try to refund the user if they send too much ether. If the refund reverts, the transaction still succeeds.
     */
    receive() external payable {
        if (token.balanceOf(address(this)) == 0) revert AlreadySold();
        if (block.timestamp < startTime) revert AuctionNotStarted();

        uint256 price = currentPrice();

        if (msg.value < price) revert MsgValueInsufficient();

        token.safeTransfer(msg.sender, token.balanceOf(address(this))); // Would it be best practice to check that msg.sender transfer first the ETH instead of us transfering first?

        (bool ok, ) = seller.call{value: price}(""); // I still think we should protect if the duration elapsed and there were no offer, that not anyone could send value 0 and take the token
        if (!ok) revert SendEtherToSellerFailed();

        if (msg.value > price) {
            payable(msg.sender).call{value: msg.value - price}(""); // Check this line
        }
    }
}
