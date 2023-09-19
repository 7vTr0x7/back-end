

const { ethers, upgrades } = require('hardhat');

async function main () {
  const TokenizedShares = await ethers.getContractFactory('TokenizedShares');
  console.log('Deploying TokenizedShares...');
  const tokenizedShares = await upgrades.deployProxy(TokenizedShares, { initializer: 'initialize' });
  await tokenizedShares.waitForDeployment();
  console.log('tokenizedShares deployed to:', tokenizedShares.target);
}


  // // Upgrading
  // const BoxV2 = await ethers.getContractFactory("BoxV2");
  // const upgraded = await upgrades.upgradeProxy(await instance.getAddress(), BoxV2);



// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
