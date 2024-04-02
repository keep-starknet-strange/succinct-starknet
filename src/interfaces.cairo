use alexandria_bytes::{Bytes, BytesTrait};
use starknet::ContractAddress;

#[starknet::interface]
trait IFunctionVerifier<TContractState> {
    fn verify(self: @TContractState, input_hash: u256, output_hash: u256, proof: Bytes) -> bool;
    fn verification_key_hash(self: @TContractState) -> u256;
}

#[starknet::interface]
trait ISuccinctGateway<TContractState> {
 /// Returns the fee vault address.
        ///
        /// # Returns
        ///
        /// * The fee vault address.
    fn get_fee_vault(self: @TContractState) -> ContractAddress;

     /// Sets the fee vault address.
        ///
        /// # Arguments
        ///
        /// * `_fee_vault` - The fee vault address.
    fn set_fee_vault(ref self: TContractState, _fee_vault: ContractAddress);

    /// Returns whether the specified prover is allowed or disallowed.
        ///
        /// # Arguments
        ///
        /// * `prover` - The prover address.
        ///
        /// # Returns
        ///
        /// * `is_prover` - Whether the prover is allowed or disallowed.
    fn get_prover(self: @TContractState, prover: ContractAddress) -> bool;

     /// Sets the specified prover to be allowed or disallowed.
        ///
        /// # Arguments
        /// 
        /// * `prover` - The prover address.
        /// * `is_prover` - Whether the prover is allowed or disallowed.
    fn set_prover(ref self: TContractState, prover: ContractAddress, is_prover: bool);

            /// Creates a onchain request for a proof. The output and proof is fulfilled asynchronously
        /// by the provided callback.
        ///
        /// # Arguments
        ///
        /// * `function_id` - The function identifier.
        /// * `input` - The function input.
        /// * `context` - The function context.
        /// * `callback_selector` - The selector of the callback function.
        /// * `callback_gas_limit` - The gas limit for the callback function.
    fn request_callback(
        ref self: TContractState,
        function_id: u256,
        input: Bytes,
        context: Bytes,
        callback_selector: felt252,
        callback_gas_limit: u32,
    ) -> u256;

     /// Creates a proof request for a call. Equivalent to an off-chain request through an API.
        ///
        /// # Arguments
        ///
        /// * `function_id` - The function identifier.
        /// * `input` - The function input.
        /// * `entry_address` - The address of the callback contract.
        /// * `entry_calldata` - The entry calldata for the call.
        /// * `entry_gas_limit` - The gas limit for the call.
    fn request_call(
        ref self: TContractState,
        function_id: u256,
        input: Bytes,
        entry_address: ContractAddress,
        entry_calldata: Bytes,
        entry_gas_limit: u32
    );


        /// If the call matches the currently verified function, returns the output. 
        /// Else this function reverts.
        ///
        /// # Arguments
        /// * `function_id` The function identifier.
        /// * `input` The function input.
    fn verified_call(self: @TContractState, function_id: u256, input: Bytes) -> (u256, u256);
    fn fulfill_callback(
        ref self: TContractState,
        nonce: u32,
        function_id: u256,
        input_hash: u256,
        callback_addr: ContractAddress,
        callback_selector: felt252,
        callback_calldata: Span<felt252>,
        callback_gas_limit: u32,
        context: Bytes,
        output: Bytes,
        proof: Bytes
    );
    fn fulfill_call(
        ref self: TContractState,
        function_id: u256,
        input: Bytes,
        output: Bytes,
        proof: Bytes,
        callback_addr: ContractAddress,
        callback_selector: felt252,
        callback_calldata: Span<felt252>,
    );
}


#[starknet::interface]
trait IFeeVault<TContractState> {

/// Get the current native currency address 
        /// # Returns
        /// The native currency address defined. 
    fn get_native_currency(self: @TContractState) -> ContractAddress;

     /// Set the native currency address 
        /// # Arguments
        /// * `_new_native_address`- The new native currency address to be set
    fn set_native_currency(ref self: TContractState, _new_native_address: ContractAddress);

     /// Check if the specified deductor is allowed to deduct from the vault.
        /// # Arguments
        /// * `_deductor` - The deductor to check.
        /// # Returns
        /// True if the deductor is allowed to deduct from the vault, false otherwise.
    fn is_deductor(self: @TContractState, _deductor: ContractAddress) -> bool;

        /// Add the specified deductor 
        /// # Arguments
        /// * `_deductor` - The address of the deductor to add.
    fn add_deductor(ref self: TContractState, _deductor: ContractAddress);

       /// Remove the specified deductor 
        /// # Arguments
        /// * `_deductor` - The address of the deductor to remove.
    fn remove_deductor(ref self: TContractState, _deductor: ContractAddress);

     /// Get the balance for a given token and account to use for Succinct services.
        /// # Arguments
        /// * `_account` - The account to retrieve the balance for.
        /// * `_token` - The token address to consider.
        /// # Returns
        /// The associated balance.
    fn get_account_balance(
        self: @TContractState, _account: ContractAddress, _token: ContractAddress
    ) -> u256;

       /// Deposit the specified amount of native currency from the caller.
        /// Dev: the native currency address is defined in the storage slot native_currency
        /// Dev: MUST approve this contract to spend at least _amount of the native_currency before calling this.
        /// # Arguments
        /// * `_account` - The account to deposit the native currency for.
    fn deposit_native(ref self: TContractState, _account: ContractAddress);

        /// Deposit the specified amount of the specified token from the caller.
        /// Dev: MUST approve this contract to spend at least _amount of _token before calling this.
        /// # Arguments
        /// * `_account` - The account to deposit the native currency for.
        /// * `_token` - The address of the token to deposit.
        /// * `_amount` - The amoun to deposit.
    fn deposit(
        ref self: TContractState, _account: ContractAddress, _token: ContractAddress, _amount: u256
    );


        /// Deduct the specified amount of native currency from the specified account.
        /// # Arguments
        /// * `_account` - The account to deduct the native currency from.
    fn deduct_native(ref self: TContractState, _account: ContractAddress);

        /// Deduct the specified amount of native currency from the specified account.
        /// # Arguments
        /// * `_account` - The account to deduct the native currency from.
        /// * `_token` - The address of the token to deduct.
        /// * `_amount` - The amount of the token to deduct.
    fn deduct(
        ref self: TContractState, _account: ContractAddress, _token: ContractAddress, _amount: u256
    );

     /// Collect the specified amount of the specified token.
        /// * `_to`- The address to send the collected tokens to.
        /// * `_token` - The address of the token to collect.
        /// *  `_amount`- The amount of the token to collect.
    fn collect_native(ref self: TContractState, _to: ContractAddress, _amount: u256);

    /// Collect the specified amount of the specified token.
        /// * `_to`- The address to send the collected tokens to.
        /// * `_token` - The address of the token to collect.
        /// *  `_amount`- The amount of the token to collect.
    fn collect(
        ref self: TContractState, _to: ContractAddress, _token: ContractAddress, _amount: u256
    );
}
