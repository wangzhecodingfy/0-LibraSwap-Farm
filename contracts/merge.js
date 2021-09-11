const { merge } = require('sol-merger');
fs = require('fs');

// Get the merged code as a string
async function start(){
    const mergedCode = await merge("./MasterChef.sol");
    fs.writeFile('MasterChef_Verify.sol', mergedCode, function (err) {
        if (err) return console.log(err);
      });
}
start();
