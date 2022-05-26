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

describe("ERC1155Drip", function () {
	let erc1155, owner, addr1, drip1, drip2;
	beforeEach(async function () {
		[owner, addr1] = await ethers.getSigners();
		drip1 = BN(10);
		drip2 = BN(20);

		const ERC1155 = await hre.ethers.getContractFactory("DRIP");
		erc1155 = await ERC1155.deploy(2, [drip1, drip2]);
		await erc1155.deployed();
	});

	it("Should mint correct amount", async function () {
		await expect(erc1155.mint(owner.address, 0, 10)).to.not.be.reverted;
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(10);
	});

	it("Should burn correct amount", async function () {
		await expect(erc1155.mint(owner.address, 0, 10)).to.not.be.reverted;
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(10);
		await expect(erc1155.burn(owner.address, 0, 10)).to.not.be.reverted;
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(0);
	});

	it("Should drip correctly", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(drip1.mul(10));
	});

	it("Should drip correctly with multiplier", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 2)).to.not.be.reverted;
		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(drip1.mul(20));
	});

	it("Should drip correctly to multiple people", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 2)).to.not.be.reverted;
		await expect(erc1155.startDripping(addr1.address, 0, 1)).to.not.be.reverted;
		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(drip1.mul(22));
		expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(drip1.mul(10));
	});

	it("Should stop drip correctly", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		await mineNBlocks(9);
		await expect(erc1155.stopDripping(owner.address, 0, 1)).to.not.be.reverted;
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(drip1.mul(10));

		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(drip1.mul(10));
	});

	it("Should correctly transfer after mint", async function () {
		await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(100);
		await expect(
			erc1155.safeTransferFrom(owner.address, addr1.address, 0, 50, "0x")
		).to.not.be.reverted;

		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(50);
		expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(50);
	});

	it("Should transfer correctly while dripping", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		await mineNBlocks(9);

		await expect(
			erc1155.safeTransferFrom(owner.address, addr1.address, 0, 50, "0x")
		).to.not.be.reverted;
		await expect(erc1155.stopDripping(owner.address, 0, 1)).to.not.be.reverted;

		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(60);
		expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(50);
	});
});
