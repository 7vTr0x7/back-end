const  hre  = require("hardhat");


async function main () {
  const CPAMM = await ethers.getContractFactory('CPAMM');
  console.log('Deploying cpamm...');
  const cpamm = await upgrades.deployProxy(CPAMM,["0xc9a0ABeB48edAFcdb743c5B28d8E4996dbdC0207"] ,{ initializer: 'InIt' });
  await cpamm.waitForDeployment();
  console.log('cpamm deployed to:', cpamm.target);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


  //0xC22b094a471D9DC2Ff2EbE050A56A1d6a25cf4CA