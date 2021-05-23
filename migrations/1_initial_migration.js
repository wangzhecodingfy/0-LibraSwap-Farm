const Migrations = artifacts.require("SafeMoon");

module.exports = function (deployer) {
  deployer.deploy(Migrations);
};
