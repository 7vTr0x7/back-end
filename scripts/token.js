

async function main() {

    const ether  = await hre.ethers.deployContract("Ether");
  
    await ether.waitForDeployment();
      
    console.log(
      `ether deployed to ${ether.target} `
    );
  }
  
  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
  
  //0x5FbDB2315678afecb367f032d93F642f64180aa3