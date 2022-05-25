const hre = require("hardhat");

async function main() {
	const Loot = await hre.ethers.getContractFactory("Loot");
	const loot = await Loot.deploy("testURI");

	await loot.deployed();
	console.log("Loot deployed to:", loot.address);

	const Raider = await hre.ethers.getContractFactory("Raider");
	const raider = await Raider.deploy(loot.address);

	await raider.deployed();
	console.log("Raider deployed to:", raider.address);

	const Dungeon = await hre.ethers.getContractFactory("DungeonRaid");
	const dungeon = await Dungeon.deploy(
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
	console.log("DungeonRaid deployed to:", dungeon.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
