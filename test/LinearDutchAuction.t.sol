// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {LinearDutchAuction, LinearDutchAuctionFactory} from "../src/LinearDutchAuction.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";

contract TokenForSale is ERC20 {
    constructor() ERC20("TokenForSale", "TFS") {
        _mint(msg.sender, 100e18);
    }
}

contract NoFallback {}

contract LinearDutchAuctionTest is Test {
    LinearDutchAuctionFactory auctionFactory;
    TokenForSale token;

    event AuctionCreated(address indexed auction, address indexed token, uint256 startingPriceEther, uint256 startTime, uint256 duration, uint256 amount, address seller);
    function setUp() public {
        token = new TokenForSale();
        auctionFactory = new LinearDutchAuctionFactory();
    }

    function test_createAuction() public {
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 1 days, 100e18, address(this));

        assertEq(token.balanceOf(address(auction)), 100e18);
        assertGt(address(auction).code.length, 0);
        assertEq(address(LinearDutchAuction(payable(auction)).token()), address(token));
        assertEq(LinearDutchAuction(payable(auction)).startingPriceEther(), 1 ether);
        assertEq(LinearDutchAuction(payable(auction)).startTime(), block.timestamp);
        assertEq(LinearDutchAuction(payable(auction)).durationSeconds(), uint256(1 days));
        assertEq(LinearDutchAuction(payable(auction)).seller(), address(this));

    }

    function test_event_auctionCreated() public {
        token.approve(address(auctionFactory), 100e18);
        address predictedAddress = LibRLP.computeAddress(address(auctionFactory), vm.getNonce(address(auctionFactory)));
        vm.expectEmit();
        emit AuctionCreated(predictedAddress, address(token), 1 ether, block.timestamp, 1 days, 100e18, address(this));
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 1 days, 100e18, address(this));
    }

    function test_auctionCreated_invalid_duration() public {
        token.approve(address(auctionFactory), 100e18);
        vm.expectRevert();
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 0, 100e18, address(this));
    }

    function test_auctionCreated_invalid_start_time() public {
        vm.warp(block.timestamp + 1 days);
        token.approve(address(auctionFactory), 100e18);
        vm.expectRevert();
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp - 1, 0, 100e18, address(this));
    }

    function test_auctionCreated_invalid_token() public {
        vm.expectRevert();
        address auction = auctionFactory.createAuction(ERC20(address(0)), 1 ether, block.timestamp, 1 days, 100e18, address(this));
    }

    function test_invalid_start_time() public {
        token.approve(address(auctionFactory), 100e18);
        vm.expectRevert();
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp - 1, 1 days, 100e18, address(this));
    }
    
    function test_invalid_start_price() public {
        token.approve(address(auctionFactory), 100e18);
        vm.expectRevert();
        address auction = auctionFactory.createAuction(token, 0, block.timestamp, 1 days, 100e18, address(this));
    }

    function test_invalid_seller() public {
        token.approve(address(auctionFactory), 100e18);
        vm.expectRevert();
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 1 days, 100e18, address(0));
    }

    function test_currentPrice() public {
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 1 days, 100e18, address(this));
        assertEq(LinearDutchAuction(payable(auction)).currentPrice(), 1 ether);
    }
    
    function test_currentPrice_after_auction_ended() public {
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 1 days, 100e18, address(this));
        vm.warp(block.timestamp + 1 days);
        assertEq(LinearDutchAuction(payable(auction)).currentPrice(), 0);
    }
    function test_3_percent_progress() public {
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 100 seconds, 100e18, address(this));
        skip(3 seconds);
        assertEq(LinearDutchAuction(payable(auction)).currentPrice(), 1 ether * 97 / 100);
    }

    function test_7_percent_progress() public {
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 100 seconds, 100e18, address(this));
        skip(7 seconds);
        assertEq(LinearDutchAuction(payable(auction)).currentPrice(), 1 ether * 93 / 100);
    }

    function test_not_started() public {
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp + 100 seconds, 100 seconds, 100e18, address(this));
        vm.expectRevert();
        LinearDutchAuction(payable(auction)).currentPrice();
    } 

    function test_buy_tokens() public {
        address seller = makeAddr("seller");
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 100 seconds, 100e18, seller);
        vm.deal(address(this), 1 ether);
        (bool ok, bytes memory reason) = auction.call{value: 1 ether}("");
        assertEq(ok, true);
        assertEq(token.balanceOf(address(this)), 100e18);

        assertEq(seller.balance, 1 ether);
    }

    function test_buy_tokens_1pct() public {
        address seller = makeAddr("seller");
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 100 seconds, 100e18, seller);
        vm.deal(address(this), 1 ether);
        vm.warp(block.timestamp + 1 seconds);
        (bool ok, bytes memory reason) = auction.call{value: 1 ether}("");
        assertEq(ok, true);
        assertEq(token.balanceOf(address(this)), 100e18);

        assertEq(seller.balance, 1 ether * 99 / 100);
        assertEq(token.balanceOf(address(this)), 100e18);
        assertEq(address(this).balance, 1 ether * 1 / 100);
    }

    function test_buy_tokens_not_enough_ether() public {
        address seller = makeAddr("seller");
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 100 seconds, 100e18, seller);
        vm.deal(address(this), 0.99 ether);
        (bool ok, ) = auction.call{value: 0.99 ether}("");
        assertEq(ok, false);
    }

    function test_buy_tokens_seller_revert() public {
        NoFallback seller = new NoFallback();
        token.approve(address(auctionFactory), 100e18);
        address auction = auctionFactory.createAuction(token, 1 ether, block.timestamp, 100 seconds, 100e18, address(seller));
        vm.deal(address(this), 1 ether);
        (bool ok, ) = auction.call{value: 1 ether}("");
        assertEq(ok, false);
    }

    receive() external payable {}
}
