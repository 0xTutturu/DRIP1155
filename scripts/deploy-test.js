const hre = require("hardhat");

async function main() {
	const DRIP = await hre.ethers.getContractFactory("DRIP");
	const drip = await DRIP.deploy(2, [10, 20]);

	await drip.deployed();
	console.log("Drip deployed to:", drip.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
	.then(() => process.exit(0))
	.catch((error) => {
		console.error(error);
		process.exit(1);
	});
