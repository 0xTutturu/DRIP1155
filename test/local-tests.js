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

describe("ERC1155Drip", function () {
	let erc1155, owner, addr1, loot, raider, dungeon;
	beforeEach(async function () {
		[owner, addr1] = await ethers.getSigners();

		/* const ERC1155 = await hre.ethers.getContractFactory("DRIP");
		erc1155 = await ERC1155.deploy(2, [10, 20]);
		await erc1155.deployed(); */

		const Loot = await hre.ethers.getContractFactory("Loot");
		loot = await Loot.deploy([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);

		await loot.deployed();
		console.log("Loot deployed to:", loot.address);

		const Raider = await hre.ethers.getContractFactory("Raider");
		raider = await Raider.deploy(loot.address, 10, 5010);

		await raider.deployed();
		console.log("Raider deployed to:", raider.address);

		const Dungeon = await hre.ethers.getContractFactory("DungeonRaid");
		dungeon = await Dungeon.deploy(
			raider.address,
			loot.address,
			4659,
			[0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
			[
				[1, 2],
				[3, 4],
				[5, 6],
				[7, 8],
			]
		);
		await dungeon.deployed();
	});

	describe("Minting", async function () {
		it("Should mint", async function () {
			await expect(
				raider.mint(0, "tesla", { value: ethers.utils.parseEther("0.02") })
			).to.not.be.reverted;
		});
	});
});

/* describe("All contracts", function () {
	let loot, raider, dungeon, owner, addr1, addr2;
	beforeEach(async function () {
		[owner, addr1, addr2] = await ethers.getSigners();

		const Loot = await hre.ethers.getContractFactory("Loot");
		loot = await Loot.deploy("testURI");
		await loot.deployed();

		const Raider = await hre.ethers.getContractFactory("Raider");
		raider = await Raider.deploy(loot.address);
		await raider.deployed();

		const Dungeon = await hre.ethers.getContractFactory("DungeonRaid");
		dungeon = await Dungeon.deploy(raider.address, loot.address, 1234);
		await dungeon.deployed();
	});

	describe("Loot", async function () {
		it("Should correctly mint items", async function () {
			await expect(loot.mintItemFor(owner.address, 2)).to.not.be.reverted;
			expect(await loot.totalSupply()).to.equal(1);
			expect(await loot.balanceOf(owner.address, 2)).to.equal(1);

			await expect(loot.mintItemFor(owner.address, 3)).to.not.be.reverted;
			await expect(loot.mintItemFor(owner.address, 4)).to.not.be.reverted;
			expect(await loot.totalSupply()).to.equal(3);
			expect(await loot.balanceOf(owner.address, 3)).to.equal(1);
			expect(await loot.balanceOf(owner.address, 4)).to.equal(1);
		});
	});

	describe("Raider", async function () {
		it("Should correctly mint and equip items", async function () {
			await expect(
				raider.mintWithItems({ value: ethers.utils.parseEther("0.02") })
			).to.not.be.reverted;
			expect(await loot.balanceOf(owner.address, 2)).to.equal(1);
			expect(await loot.balanceOf(owner.address, 3)).to.equal(1);
			expect(await loot.balanceOf(owner.address, 4)).to.equal(1);
			expect(await raider.totalSupply()).to.equal(1);
			expect(await raider.ownerOf(1)).to.equal(owner.address);
			console.log(await raider._tokenDataOf(1));
		});
	});

	describe("DungeonRaid", async function () {
		beforeEach(async function () {
			await expect(loot.setDungeonContract(dungeon.address)).to.not.be.reverted;
			await expect(loot.setRaiderContract(raider.address)).to.not.be.reverted;

			await expect(raider.setLootContract(loot.address)).to.not.be.reverted;
			await expect(
				raider.setDungeonContract(dungeon.address)
			).to.not.be.reverted;

			await expect(
				raider.mintWithItems({ value: ethers.utils.parseEther("0.02") })
			).to.not.be.reverted;
			await expect(
				raider
					.connect(addr1)
					.mintWithItems({ value: ethers.utils.parseEther("0.02") })
			).to.not.be.reverted;
		});

		describe("mockGenerateDungeon", async function () {
			it("Should not revert and print dungeon", async function () {
				await expect(dungeon.mockGenerateDungeon()).to.not.be.reverted;
				//console.log(await dungeon.dungeons(1));
			});
		});

		

		// Minting multiple items returns an increased power for the next item minted
		describe("proposeDungeon", async function () {
			it("Should correctly propose a dungeon and print it", async function () {
				await expect(dungeon.mockGenerateDungeon()).to.not.be.reverted;
				await expect(dungeon.connect(addr1).proposeDungeon(1, 2)).to.not.be
					.reverted;
				console.log(await dungeon.dungeons(1));
				console.log(await raider._tokenDataOf(1));
				console.log(await raider._tokenDataOf(2));
				console.log(await raider.equippedItems(1, 0));
			});

			it("Should correctly join dungeon and print", async function () {
				await expect(dungeon.mockGenerateDungeon()).to.not.be.reverted;
				await expect(dungeon.connect(addr1).proposeDungeon(1, 2)).to.not.be
					.reverted;
				console.log(await dungeon.dungeons(1));
				await expect(dungeon.joinDungeon(1, 1)).to.not.be.reverted;
				console.log(await raider._tokenDataOf(1));
				console.log(await raider._tokenDataOf(2));
				console.log(await dungeon.dungeons(1));
			});

			it("Should correctly execute dungeon", async function () {
				await expect(dungeon.mockGenerateDungeon()).to.not.be.reverted;
				await expect(dungeon.connect(addr1).proposeDungeon(1, 2)).to.not.be
					.reverted;
				await expect(dungeon.joinDungeon(1, 1)).to.not.be.reverted;
				await advanceTime(time.delta6m);
				await expect(dungeon.mockExecuteDungeon(1)).to.not.be.reverted;
				expect(await loot.balanceOf(addr1.address, 0)).to.equal(0);
				expect(await loot.balanceOf(addr1.address, 1)).to.equal(0);
				await expect(dungeon.claimReward(1, 1)).to.not.be.reverted;
				expect(await loot.balanceOf(owner.address, 0)).to.equal(
					ethers.utils.parseEther("500")
				);
				expect(await loot.balanceOf(owner.address, 1)).to.equal(
					ethers.utils.parseEther("50")
				);
			});
		});
	});
}); */
