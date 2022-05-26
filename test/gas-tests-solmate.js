const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber, utils } = require("ethers");
const {
	centerTime,
	getBlockTimestamp,
	jumpToTime,
	advanceTime,
} = require("../scripts/utilities/utility.js");

const BN = BigNumber.from;
var time = centerTime();

const getBalance = ethers.provider.getBalance;

async function mineNBlocks(n) {
	for (let index = 0; index < n; index++) {
		await ethers.provider.send("evm_mine");
	}
}

describe("Gas tests - solmate", function () {
	let erc1155, owner, addr1, drip1, drip2;
	beforeEach(async function () {
		[owner, addr1] = await ethers.getSigners();

		const ERC1155 = await hre.ethers.getContractFactory("SOL");
		erc1155 = await ERC1155.deploy();
		await erc1155.deployed();
	});

	it("Mint, burn, transfer", async function () {
		await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
		await expect(erc1155.burn(owner.address, 0, 50)).to.not.be.reverted;
		await expect(
			erc1155.safeTransferFrom(owner.address, addr1.address, 0, 50, "0x")
		).to.not.be.reverted;
	});

	it("Batch mint, burn, transfer - two ids", async function () {
		let mintAmount = BN(100);
		await expect(
			erc1155.batchMint(owner.address, [0, 1], [mintAmount, mintAmount.sub(50)])
		).to.not.be.reverted;
		await expect(erc1155.batchBurn(owner.address, [0, 1], [50, 25])).to.not.be
			.reverted;
		await expect(
			erc1155.safeBatchTransferFrom(
				owner.address,
				addr1.address,
				[0, 1],
				[50, 25],
				"0x"
			)
		).to.not.be.reverted;
	});
});
