/*

  Copyright 2017 ZeroEx Inc.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.4.8;

import "./base/MultiSigWallet.sol";

/// @title Multisignature wallet with time lock- Allows multiple parties to execute a transaction after a time lock has passed.
/// @author Amir Bandeali - <amir@0xProject.com>
contract MultiSigWalletWithTimeLock is MultiSigWallet {

    event ConfirmationTimeSet(uint indexed transactionId, uint confirmationTime);
    event TimeLockChange(uint secondsTimeLocked);

    uint public secondsTimeLocked;
    mapping (uint => uint) public confirmationTimes;

    modifier confirmationTimeNotSet(uint transactionId) {
        if (confirmationTimes[transactionId] != 0) throw;
        _;
    }

    modifier pastTimeLock(uint transactionId) {
      uint confirmationTime = confirmationTimes[transactionId];
      if (confirmationTime == 0 || block.timestamp < confirmationTime + secondsTimeLocked) throw;
      _;
    }

    /*
     * Public functions
     */

    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    /// @param _secondsTimeLocked Duration needed after a transaction is confirmed and before it becomes executable, in seconds.
    function MultiSigWalletWithTimeLock(address[] _owners, uint _required, uint _secondsTimeLocked)
        public
        validRequirement(_owners.length, _required)
    {
        for (uint i = 0; i < _owners.length; i++) {
            if (isOwner[_owners[i]] || _owners[i] == 0) throw;
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
        secondsTimeLocked = _secondsTimeLocked;
    }

    /// @dev Changes the duration of the time lock for transactions.
    /// @param _secondsTimeLocked Duration needed after a transaction is confirmed and before it becomes executable, in seconds.
    function changeTimeLock(uint _secondsTimeLocked)
        public
        onlyWallet
    {
        secondsTimeLocked = _secondsTimeLocked;
        TimeLockChange(_secondsTimeLocked);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId)
        public
        ownerExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
        confirmationTimeNotSet(transactionId)
    {
        confirmations[transactionId][msg.sender] = true;
        Confirmation(msg.sender, transactionId);
        if (!isConfirmationTimeSet(transactionId) && isConfirmed(transactionId)) {
            setConfirmationTime(transactionId, block.timestamp);
        }
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
        confirmationTimeNotSet(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        Revocation(msg.sender, transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
        public
        notExecuted(transactionId)
        pastTimeLock(transactionId)
    {
        Transaction tx = transactions[transactionId];
        tx.executed = true;
        if (tx.destination.call.value(tx.value)(tx.data))
            Execution(transactionId);
        else {
            ExecutionFailure(transactionId);
            tx.executed = false;
        }
    }

    /// @dev Checks if a transaction's confirmation time has been set.
    /// @param transactionId Transaction ID.
    /// @return Status of confirmation time.
    function isConfirmationTimeSet(uint transactionId)
        public
        constant
        returns (bool)
    {
        return confirmationTimes[transactionId] != 0;
    }

    /*
     * Internal functions
     */

    /// @dev Sets the time of when a submission first passed.
    function setConfirmationTime(uint transactionId, uint confirmationTime)
        internal
    {
        confirmationTimes[transactionId] = confirmationTime;
        ConfirmationTimeSet(transactionId, confirmationTime);
    }
}
