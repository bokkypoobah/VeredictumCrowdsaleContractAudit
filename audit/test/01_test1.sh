#!/bin/bash
# ----------------------------------------------------------------------------------------------
# Testing the smart contract
#
# Enjoy. (c) BokkyPooBah / Bok Consulting Pty Ltd 2017. The MIT Licence.
# ----------------------------------------------------------------------------------------------

MODE=${1:-test}

GETHATTACHPOINT=`grep ^IPCFILE= settings.txt | sed "s/^.*=//"`
PASSWORD=`grep ^PASSWORD= settings.txt | sed "s/^.*=//"`

CONTRACTSDIR=`grep ^CONTRACTSDIR= settings.txt | sed "s/^.*=//"`

TOKENSOL=`grep ^TOKENSOL= settings.txt | sed "s/^.*=//"`
TOKENTEMPSOL=`grep ^TOKENTEMPSOL= settings.txt | sed "s/^.*=//"`
TOKENJS=`grep ^TOKENJS= settings.txt | sed "s/^.*=//"`

DEPLOYMENTDATA=`grep ^DEPLOYMENTDATA= settings.txt | sed "s/^.*=//"`

INCLUDEJS=`grep ^INCLUDEJS= settings.txt | sed "s/^.*=//"`
TEST1OUTPUT=`grep ^TEST1OUTPUT= settings.txt | sed "s/^.*=//"`
TEST1RESULTS=`grep ^TEST1RESULTS= settings.txt | sed "s/^.*=//"`

CURRENTTIME=`date +%s`
CURRENTTIMES=`date -r $CURRENTTIME -u`

BLOCKSINDAY=10

if [ "$MODE" == "dev" ]; then
  # Start time now
  STARTTIME=`echo "$CURRENTTIME" | bc`
else
  # Start time 1m 10s in the future
  STARTTIME=`echo "$CURRENTTIME+75" | bc`
fi
STARTTIME_S=`date -r $STARTTIME -u`
ENDTIME=`echo "$CURRENTTIME+60*4" | bc`
ENDTIME_S=`date -r $ENDTIME -u`

printf "MODE            = '$MODE'\n" | tee $TEST1OUTPUT
printf "GETHATTACHPOINT = '$GETHATTACHPOINT'\n" | tee -a $TEST1OUTPUT
printf "PASSWORD        = '$PASSWORD'\n" | tee -a $TEST1OUTPUT
printf "CONTRACTSDIR    = '$CONTRACTSDIR'\n" | tee -a $TEST1OUTPUT
printf "TOKENSOL        = '$TOKENSOL'\n" | tee -a $TEST1OUTPUT
printf "TOKENTEMPSOL    = '$TOKENTEMPSOL'\n" | tee -a $TEST1OUTPUT
printf "TOKENJS         = '$TOKENJS'\n" | tee -a $TEST1OUTPUT
printf "DEPLOYMENTDATA  = '$DEPLOYMENTDATA'\n" | tee -a $TEST1OUTPUT
printf "INCLUDEJS       = '$INCLUDEJS'\n" | tee -a $TEST1OUTPUT
printf "TEST1OUTPUT     = '$TEST1OUTPUT'\n" | tee -a $TEST1OUTPUT
printf "TEST1RESULTS    = '$TEST1RESULTS'\n" | tee -a $TEST1OUTPUT
printf "CURRENTTIME     = '$CURRENTTIME' '$CURRENTTIMES'\n" | tee -a $TEST1OUTPUT
printf "STARTTIME       = '$STARTTIME' '$STARTTIME_S'\n" | tee -a $TEST1OUTPUT
printf "ENDTIME         = '$ENDTIME' '$ENDTIME_S'\n" | tee -a $TEST1OUTPUT

# Make copy of SOL file and modify start and end times ---
`cp $CONTRACTSDIR/$TOKENSOL $TOKENTEMPSOL`

# --- Modify parameters ---
`perl -pi -e "s/fundWallet      \= 0x0;/fundWallet      \= 0xa22AB8A9D641CE77e06D98b7D7065d324D3d6976;/" $TOKENTEMPSOL`
`perl -pi -e "s/START_DATE      \= 1502668800;.*$/START_DATE      = $STARTTIME; \/\/ $STARTTIME_S/" $TOKENTEMPSOL`
`perl -pi -e "s/END_DATE  \= START_DATE \+ FUNDING_PERIOD;.*$/END_DATE  \= $ENDTIME; \/\/ $ENDTIME_S/" $TOKENTEMPSOL`
`perl -pi -e "s/USD_PER_ETH     \= 200;.*$/USD_PER_ETH     \= 270;/" $TOKENTEMPSOL`

DIFFS1=`diff $CONTRACTSDIR/$TOKENSOL $TOKENTEMPSOL`
echo "--- Differences $CONTRACTSDIR/$TOKENSOL $TOKENTEMPSOL ---"
echo "$DIFFS1"

echo "var tokenOutput=`solc --optimize --combined-json abi,bin,interface $TOKENTEMPSOL`;" > $TOKENJS

geth --verbosity 3 attach $GETHATTACHPOINT << EOF | tee -a $TEST1OUTPUT
loadScript("$TOKENJS");
loadScript("functions.js");

var tokenAbi = JSON.parse(tokenOutput.contracts["$TOKENTEMPSOL:VentanaToken"].abi);
var tokenBin = "0x" + tokenOutput.contracts["$TOKENTEMPSOL:VentanaToken"].bin;

console.log("DATA: tokenAbi=" + JSON.stringify(tokenAbi));

unlockAccounts("$PASSWORD");
printBalances();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var deployTokenMessage = "Deploy Token Contract";
// -----------------------------------------------------------------------------
console.log("RESULT: " + deployTokenMessage);
var tokenContract = web3.eth.contract(tokenAbi);
console.log(JSON.stringify(tokenContract));
var tokenTx = null;
var tokenAddress = null;

var token = tokenContract.new({from: contractOwnerAccount, data: tokenBin, gas: 6000000},
  function(e, contract) {
    if (!e) {
      if (!contract.address) {
        tokenTx = contract.transactionHash;
      } else {
        tokenAddress = contract.address;
        console.log("RESULT: tokenAddress=" + tokenAddress);
        console.log("RESULT: token.symbol()=" + token.symbol());
        // TODO console.log("RESULT: token.name()=" + token.name());
        addAccount(tokenAddress, "Token '" + token.symbol() + "'");
        addTokenContractAddressAndAbi(tokenAddress, tokenAbi);
        console.log("DATA: tokenAddress=" + tokenAddress);
      }
    }
  }
);

while (txpool.status.pending > 0) {
}

printTxData("tokenAddress=" + tokenAddress, tokenTx);
printBalances();
failIfGasEqualsGasUsed(tokenTx, deployTokenMessage);
printTokenContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var addKycAccountsMessage = "Add KYC Accounts";
// -----------------------------------------------------------------------------
console.log("RESULT: " + addKycAccountsMessage);
var addKycAccounts1Tx = token.addKycAddress(account3, true, {from: contractOwnerAccount, to: tokenAddress, gas: 400000});
var addKycAccounts2Tx = token.addKycAddress(account4, true, {from: contractOwnerAccount, to: tokenAddress, gas: 400000});
while (txpool.status.pending > 0) {
}
printTxData("addKycAccounts1Tx", addKycAccounts1Tx);
printTxData("addKycAccounts2Tx", addKycAccounts2Tx);
printBalances();
failIfGasEqualsGasUsed(addKycAccounts1Tx, addKycAccountsMessage + " ac3 true");
failIfGasEqualsGasUsed(addKycAccounts2Tx, addKycAccountsMessage + " ac4 true");
printTokenContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var contributionsBeforeStartMessage = "Send Contributions Before Start";
// -----------------------------------------------------------------------------
console.log("RESULT: " + contributionsBeforeStartMessage);
var contributionsBeforeStart1Tx = eth.sendTransaction({from: account4, to: tokenAddress, gas: 400000, value: web3.toWei("10", "ether")});
var contributionsBeforeStart2Tx = eth.sendTransaction({from: account5, to: tokenAddress, gas: 400000, value: web3.toWei("20", "ether")});
while (txpool.status.pending > 0) {
}
printTxData("contributionsBeforeStart1Tx", contributionsBeforeStart1Tx);
printTxData("contributionsBeforeStart2Tx", contributionsBeforeStart2Tx);
printBalances();
failIfGasEqualsGasUsed(contributionsBeforeStart1Tx, contributionsBeforeStartMessage + " 10 ETH from ac4 (KYC-ed)");
passIfGasEqualsGasUsed(contributionsBeforeStart2Tx, contributionsBeforeStartMessage + " 20 ETH from ac5 (non-KYCe-ed) fail");
printTokenContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
// Wait for crowdsale start
// -----------------------------------------------------------------------------
var startTime = token.START_DATE();
var startTimeDate = new Date(startTime * 1000);
console.log("RESULT: Waiting until startTime at " + startTime + " " + startTimeDate +
  " currentDate=" + new Date());
while ((new Date()).getTime() <= startTimeDate.getTime()) {
}
console.log("RESULT: Waited until startTime at " + startTime + " " + startTimeDate +
  " currentDate=" + new Date());
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var validContribution1Message = "Send Valid Contribution";
// -----------------------------------------------------------------------------
console.log("RESULT: " + validContribution1Message);
var sendValidContribution1Tx = eth.sendTransaction({from: account3, to: tokenAddress, gas: 400000, value: web3.toWei("5000.123333333333333333", "ether")});
var sendValidContribution2Tx = eth.sendTransaction({from: account4, to: tokenAddress, gas: 400000, value: web3.toWei("7000.234444444444444444", "ether")});
var sendValidContribution3Tx = eth.sendTransaction({from: account5, to: tokenAddress, gas: 400000, value: web3.toWei("10.123456789012345678", "ether")});
while (txpool.status.pending > 0) {
}
printTxData("sendValidContribution1Tx", sendValidContribution1Tx);
printTxData("sendValidContribution2Tx", sendValidContribution2Tx);
printTxData("sendValidContribution3Tx", sendValidContribution3Tx);
printBalances();
failIfGasEqualsGasUsed(sendValidContribution1Tx, validContribution1Message + " 5000.x ETH from ac3 (KYC-ed)");
failIfGasEqualsGasUsed(sendValidContribution2Tx, validContribution1Message + " 7000.x ETH from ac4 (KYC-ed)");
failIfGasEqualsGasUsed(sendValidContribution3Tx, validContribution1Message + " 10.x ETH from ac5 (non-KYC-ed)");
printTokenContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var finaliseMessage = "Finalise Crowdsale";
// -----------------------------------------------------------------------------
console.log("RESULT: " + finaliseMessage);
var finaliseTx = token.finaliseICO({from: contractOwnerAccount, to: tokenAddress, gas: 400000});
while (txpool.status.pending > 0) {
}
printTxData("finaliseTx", finaliseTx);
printBalances();
failIfGasEqualsGasUsed(finaliseTx, finaliseMessage);
printTokenContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var canMoveMessage = "Can Move Tokens After Crowdsale Finalised";
// -----------------------------------------------------------------------------
console.log("RESULT: " + canMoveMessage);
var canMove1Tx = token.transfer(account6, "1000000000000", {from: account4, gas: 100000});
var canMove2Tx = token.approve(account7,  "30000000000000000", {from: account5, gas: 100000});
while (txpool.status.pending > 0) {
}
var canMove3Tx = token.transferFrom(account5, account8, "30000000000000000", {from: account7, gas: 100000});
while (txpool.status.pending > 0) {
}
printTxData("canMove1Tx", canMove1Tx);
printTxData("canMove2Tx", canMove2Tx);
printTxData("canMove3Tx", canMove3Tx);
printBalances();
failIfGasEqualsGasUsed(canMove1Tx, canMoveMessage + " - transfer 0.000001 VNT ac4 -> ac6. CHECK for movement");
failIfGasEqualsGasUsed(canMove2Tx, canMoveMessage + " - approve 0.03 VNT ac5 -> ac7");
failIfGasEqualsGasUsed(canMove3Tx, canMoveMessage + " - transferFrom 0.03 VNT ac5 -> ac8. CHECK for movement");
printTokenContractDetails();
console.log("RESULT: ");


// -----------------------------------------------------------------------------
var invalidContribution1Message = "Send Invalid Contribution";
// -----------------------------------------------------------------------------
console.log("RESULT: " + invalidContribution1Message);
var sendInvalidContribution1Tx = eth.sendTransaction({from: account3, to: tokenAddress, gas: 400000, value: web3.toWei("2000.123333333333333333", "ether")});
var sendInvalidContribution2Tx = eth.sendTransaction({from: account6, to: tokenAddress, gas: 400000, value: web3.toWei("10.123456789012345678", "ether")});
while (txpool.status.pending > 0) {
}
printTxData("sendInvalidContribution1Tx", sendInvalidContribution1Tx);
printTxData("sendInvalidContribution2Tx", sendInvalidContribution2Tx);
printBalances();
passIfGasEqualsGasUsed(sendInvalidContribution1Tx, invalidContribution1Message + " 2000.x ETH from ac3 (KYC-ed)");
passIfGasEqualsGasUsed(sendInvalidContribution2Tx, invalidContribution1Message + " 10.x ETH from ac6 (non-KYC-ed)");
printTokenContractDetails();
console.log("RESULT: ");


EOF
grep "DATA: " $TEST1OUTPUT | sed "s/DATA: //" > $DEPLOYMENTDATA
cat $DEPLOYMENTDATA
grep "RESULT: " $TEST1OUTPUT | sed "s/RESULT: //" > $TEST1RESULTS
cat $TEST1RESULTS
