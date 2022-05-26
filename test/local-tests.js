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

	it("Should drip correctly", async function () {
		await expect(erc1155.startDripping(owner.address, 2, 1)).to.be.revertedWith(
			"Token not drippable"
		);
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

	it("Should stop drip to single user correctly", async function () {
		await expect(erc1155.stopDripping(owner.address, 0, 1)).to.be.revertedWith(
			"user not accruing"
		);
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		await mineNBlocks(9);
		await expect(erc1155.stopDripping(owner.address, 2, 1)).to.be.revertedWith(
			"Token not drippable"
		);
		await expect(erc1155.stopDripping(owner.address, 0, 1)).to.not.be.reverted;
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(
			drip1.mul(10).add(10)
		);

		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(
			drip1.mul(10).add(10)
		);
	});

	it("Should add up multiplier when dripping to single user multiple times", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be.reverted;
		let balance = await erc1155.balanceOf(owner.address, 0);
		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(
			drip1.mul(30).add(balance)
		);
	});

	it("Should deduce multiplier correctly", async function () {
		await expect(erc1155.startDripping(owner.address, 0, 3)).to.not.be.reverted;

		await expect(erc1155.stopDripping(owner.address, 0, 1)).to.not.be.reverted;
		let balance = await erc1155.balanceOf(owner.address, 0);
		await mineNBlocks(10);
		expect(await erc1155.balanceOf(owner.address, 0)).to.equal(
			drip1.mul(20).add(balance)
		);
	});

	describe("Mint and Burn", async function () {
		describe("Drippable", async function () {
			it("Should correctly mint to single address", async function () {
				await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(100);
			});

			it("Should correctly batch mint to single address", async function () {
				let mintAmount = BN(100);
				await expect(
					erc1155.batchMint(
						owner.address,
						[0, 1],
						[mintAmount, mintAmount.sub(50)]
					)
				).to.not.be.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[0, 1]
				);
				expect(balances[0]).to.equal(mintAmount);
				expect(balances[1]).to.equal(mintAmount.sub(50));
			});

			it("Should correctly burn from single address", async function () {
				await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(100);
				await expect(erc1155.burn(owner.address, 0, 50)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(50);
			});

			it("Should correctly batch burn from single address", async function () {
				let mintAmount = BN(100);
				await expect(
					erc1155.batchMint(
						owner.address,
						[0, 1],
						[mintAmount, mintAmount.sub(50)]
					)
				).to.not.be.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[0, 1]
				);
				expect(balances[0]).to.equal(mintAmount);
				expect(balances[1]).to.equal(mintAmount.sub(50));

				await expect(erc1155.batchBurn(owner.address, [0, 1], [50, 25]));
				balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[0, 1]
				);
				expect(balances[0]).to.equal(mintAmount.sub(50));
				expect(balances[1]).to.equal(mintAmount.sub(75));
			});
		});

		describe("Non-drippable", async function () {
			it("Should correctly mint to single address", async function () {
				await expect(erc1155.mint(owner.address, 2, 100)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 2)).to.equal(100);
			});

			it("Should correctly batch mint to single address", async function () {
				let mintAmount = BN(100);
				await expect(
					erc1155.batchMint(
						owner.address,
						[2, 3],
						[mintAmount, mintAmount.sub(50)]
					)
				).to.not.be.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[2, 3]
				);
				expect(balances[0]).to.equal(mintAmount);
				expect(balances[1]).to.equal(mintAmount.sub(50));
			});

			it("Should correctly burn from single address", async function () {
				await expect(erc1155.mint(owner.address, 2, 100)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 2)).to.equal(100);
				await expect(erc1155.burn(owner.address, 2, 50)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 2)).to.equal(50);
			});

			it("Should correctly batch burn from single address", async function () {
				let mintAmount = BN(100);
				await expect(
					erc1155.batchMint(
						owner.address,
						[2, 3],
						[mintAmount, mintAmount.sub(50)]
					)
				).to.not.be.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[2, 3]
				);
				expect(balances[0]).to.equal(mintAmount);
				expect(balances[1]).to.equal(mintAmount.sub(50));
				await expect(
					erc1155.batchBurn(owner.address, [2], [50, 25])
				).to.be.revertedWith("LENGTH_MISMATCH");

				await expect(erc1155.batchBurn(owner.address, [2, 3], [50, 25])).to.not
					.be.reverted;
				balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[2, 3]
				);
				expect(balances[0]).to.equal(mintAmount.sub(50));
				expect(balances[1]).to.equal(mintAmount.sub(75));
			});
		});
	});

	describe("Transfer", async function () {
		describe("Drippable", async function () {
			it("Should correctly transfer after mint", async function () {
				await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(100);
				await expect(
					erc1155.safeTransferFrom(owner.address, addr1.address, 0, 50, "0x")
				).to.not.be.reverted;

				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(50);
				expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(50);
			});

			it("Should transfer from drip user to non-drip user", async function () {
				await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be
					.reverted;
				await mineNBlocks(9);

				await expect(
					erc1155.safeTransferFrom(owner.address, addr1.address, 0, 50, "0x")
				).to.not.be.reverted;
				await expect(erc1155.stopDripping(owner.address, 0, 1)).to.not.be
					.reverted;

				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(60);
				expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(50);
			});

			it("Should transfer from drip user to drip user", async function () {
				await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be
					.reverted;
				await expect(erc1155.startDripping(addr1.address, 0, 1)).to.not.be
					.reverted;
				await mineNBlocks(9);

				await expect(
					erc1155.safeTransferFrom(owner.address, addr1.address, 0, 50, "0x")
				).to.not.be.reverted;
				await expect(erc1155.stopDripping(owner.address, 0, 1)).to.not.be
					.reverted;
				await expect(erc1155.stopDripping(addr1.address, 0, 1)).to.not.be
					.reverted;

				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(70);
				expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(170);
			});

			it("Should correctly transfer if approved for all", async function () {
				await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
				await expect(erc1155.setApprovalForAll(addr1.address, true));
				await expect(
					erc1155
						.connect(addr1)
						.safeTransferFrom(owner.address, addr1.address, 0, 100, "0x")
				).to.not.be.reverted;

				expect(await erc1155.balanceOf(owner.address, 0)).to.equal(0);
				expect(await erc1155.balanceOf(addr1.address, 0)).to.equal(100);
			});

			it("Should fail if not approved", async function () {
				await expect(erc1155.mint(owner.address, 0, 100)).to.not.be.reverted;
				await expect(
					erc1155
						.connect(addr1)
						.safeTransferFrom(owner.address, addr1.address, 0, 100, "0x")
				).to.be.revertedWith("NOT_AUTHORIZED");
			});
		});

		describe("Non-Drippable", async function () {
			it("Should correctly transfer after mint", async function () {
				await expect(erc1155.mint(owner.address, 2, 1)).to.not.be.reverted;
				expect(await erc1155.balanceOf(owner.address, 2)).to.equal(1);
				await expect(
					erc1155.safeTransferFrom(owner.address, addr1.address, 2, 1, "0x")
				).to.not.be.reverted;

				expect(await erc1155.balanceOf(owner.address, 2)).to.equal(0);
				expect(await erc1155.balanceOf(addr1.address, 2)).to.equal(1);
			});

			it("Should correctly transfer if approved for all", async function () {
				await expect(erc1155.mint(owner.address, 2, 100)).to.not.be.reverted;
				await expect(erc1155.setApprovalForAll(addr1.address, true));
				await expect(
					erc1155
						.connect(addr1)
						.safeTransferFrom(owner.address, addr1.address, 2, 50, "0x")
				).to.not.be.reverted;

				expect(await erc1155.balanceOf(owner.address, 2)).to.equal(50);
				expect(await erc1155.balanceOf(addr1.address, 2)).to.equal(50);
			});
		});
	});

	describe("Transfer Batch", async function () {
		describe("Drippable", async function () {
			it("Should correctly batch transfer after mint", async function () {
				let mintAmount = BN(100);
				await expect(erc1155.mint(owner.address, 0, mintAmount)).to.not.be
					.reverted;
				await expect(erc1155.mint(owner.address, 1, mintAmount)).to.not.be
					.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[0, 1]
				);
				for (let i = 0; i < balances.length; i++) {
					expect(balances[i]).to.equal(mintAmount);
				}
				await expect(
					erc1155.safeBatchTransferFrom(
						owner.address,
						addr1.address,
						[0, 1],
						[50, 25],
						"0x"
					)
				).to.not.be.reverted;
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[0, 0]
				);

				expect(balances[0]).to.equal(mintAmount.sub(50));
				expect(balances[1]).to.equal(mintAmount.sub(50));
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[1, 1]
				);
				expect(balances[0]).to.equal(mintAmount.sub(25));
				expect(balances[1]).to.equal(mintAmount.sub(75));
			});

			it("Should correctly batch transfer after batch mint", async function () {
				let mintAmount = BN(100);
				await expect(
					erc1155.batchMint(
						owner.address,
						[0, 1],
						[mintAmount, mintAmount.sub(50)]
					)
				).to.not.be.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[0, 1]
				);
				expect(balances[0]).to.equal(mintAmount);
				expect(balances[1]).to.equal(mintAmount.sub(50));

				await expect(
					erc1155.safeBatchTransferFrom(
						owner.address,
						addr1.address,
						[0, 1],
						[50, 25],
						"0x"
					)
				).to.not.be.reverted;
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[0, 0]
				);

				expect(balances[0]).to.equal(mintAmount.sub(50));
				expect(balances[1]).to.equal(mintAmount.sub(50));
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[1, 1]
				);
				expect(balances[0]).to.equal(mintAmount.sub(75));
				expect(balances[1]).to.equal(mintAmount.sub(75));
			});

			it("Should correctly batch transfer after dripping", async function () {
				let perBlockOne = BN(10);
				let perBlockTwo = BN(20);

				await expect(erc1155.startDripping(owner.address, 0, 1)).to.not.be
					.reverted;
				await expect(erc1155.startDripping(owner.address, 1, 1)).to.not.be
					.reverted;
				await mineNBlocks(9);

				let startBlockOne = BN(await erc1155.getStartBlock(owner.address, 0));
				let startBlockTwo = BN(await erc1155.getStartBlock(owner.address, 1));

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[0, 1]
				);

				let latestBlock = BN(
					(await hre.ethers.provider.getBlock("latest")).number
				);

				expect(balances[0]).to.equal(
					perBlockOne.mul(latestBlock.sub(startBlockOne))
				);
				expect(balances[1]).to.equal(
					perBlockTwo.mul(latestBlock.sub(startBlockTwo))
				);

				await expect(
					erc1155.safeBatchTransferFrom(
						owner.address,
						addr1.address,
						[0, 1],
						[50, 100],
						"0x"
					)
				).to.not.be.reverted;
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[0, 0]
				);
				latestBlock = BN((await hre.ethers.provider.getBlock("latest")).number);

				expect(balances[0]).to.equal(
					perBlockOne.mul(latestBlock.sub(startBlockOne)).sub(50)
				);
				expect(balances[1]).to.equal(perBlockOne.mul(5));
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[1, 1]
				);
				latestBlock = BN((await hre.ethers.provider.getBlock("latest")).number);

				expect(balances[0]).to.equal(
					perBlockTwo.mul(latestBlock.sub(startBlockTwo)).sub(100)
				);
				expect(balances[1]).to.equal(perBlockTwo.mul(5));
			});
		});

		describe("Non-Drippable", async function () {
			it("Should correctly batch transfer after mint", async function () {
				let mintAmount = BN(100);
				await expect(erc1155.mint(owner.address, 2, mintAmount)).to.not.be
					.reverted;
				await expect(erc1155.mint(owner.address, 3, mintAmount)).to.not.be
					.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[2, 3]
				);
				for (let i = 0; i < balances.length; i++) {
					expect(balances[i]).to.equal(mintAmount);
				}
				await expect(
					erc1155
						.connect(addr1)
						.safeBatchTransferFrom(
							owner.address,
							addr1.address,
							[2, 3],
							[50, 25],
							"0x"
						)
				).to.be.revertedWith("NOT_AUTHORIZED");
				await expect(
					erc1155.safeBatchTransferFrom(
						owner.address,
						addr1.address,
						[2, 3],
						[50, 25],
						"0x"
					)
				).to.not.be.reverted;
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[2, 2]
				);

				expect(balances[0]).to.equal(mintAmount.sub(50));
				expect(balances[1]).to.equal(mintAmount.sub(50));
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[3, 3]
				);
				expect(balances[0]).to.equal(mintAmount.sub(25));
				expect(balances[1]).to.equal(mintAmount.sub(75));
			});

			it("Should correctly batch transfer after batch mint", async function () {
				let mintAmount = BN(100);
				await expect(
					erc1155.batchMint(
						owner.address,
						[2, 3],
						[mintAmount, mintAmount.sub(50)]
					)
				).to.not.be.reverted;

				let balances = await erc1155.balanceOfBatch(
					[owner.address, owner.address],
					[2, 3]
				);
				expect(balances[0]).to.equal(mintAmount);
				expect(balances[1]).to.equal(mintAmount.sub(50));

				await expect(
					erc1155.safeBatchTransferFrom(
						owner.address,
						addr1.address,
						[2, 3],
						[50, 25],
						"0x"
					)
				).to.not.be.reverted;
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[2, 2]
				);

				expect(balances[0]).to.equal(mintAmount.sub(50));
				expect(balances[1]).to.equal(mintAmount.sub(50));
				balances = await erc1155.balanceOfBatch(
					[owner.address, addr1.address],
					[3, 3]
				);
				expect(balances[0]).to.equal(mintAmount.sub(75));
				expect(balances[1]).to.equal(mintAmount.sub(75));
			});
		});

		describe("Both", async function () {});
	});
});
