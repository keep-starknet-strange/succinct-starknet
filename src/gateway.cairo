#[starknet::contract]
mod succinct_gateway {
    use alexandria_bytes::{Bytes, BytesTrait};
    use core::array::SpanTrait;
    use openzeppelin::access::ownable::{OwnableComponent as ownable_cpt, interface::IOwnable};
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;
    use openzeppelin::upgrades::{interface::IUpgradeable, upgradeable::UpgradeableComponent};
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, syscalls::call_contract_syscall};
    use succinct_sn::function_registry::component::function_registry_cpt;
    use succinct_sn::function_registry::interfaces::IFunctionRegistry;
    use succinct_sn::interfaces::{
        ISuccinctGateway, IFunctionVerifierDispatcher, IFunctionVerifierDispatcherTrait,
        IFeeVaultDispatcher, IFeeVaultDispatcherTrait
    };

    component!(
        path: function_registry_cpt, storage: function_registry, event: FunctionRegistryEvent
    );
    component!(path: ownable_cpt, storage: ownable, event: OwnableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent
    );
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    impl ReentrancyGuardInternalImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl FunctionRegistryImpl =
        function_registry_cpt::FunctionRegistryImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = ownable_cpt::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = ownable_cpt::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        allowed_provers: LegacyMap<ContractAddress, bool>,
        is_callback: bool,
        nonce: u32,
        requests: LegacyMap<u32, u256>,
        verified_function_id: u256,
        verified_input_hash: u256,
        verified_output: (u256, u256),
        fee_vault_address: ContractAddress,
        #[substorage(v0)]
        function_registry: function_registry_cpt::Storage,
        #[substorage(v0)]
        ownable: ownable_cpt::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RequestCall: RequestCall,
        RequestCallback: RequestCallback,
        RequestFulfilled: RequestFulfilled,
        Call: Call,
        SetFeeVault: SetFeeVault,
        ProverUpdated: ProverUpdated,
        #[flat]
        FunctionRegistryEvent: function_registry_cpt::Event,
        #[flat]
        OwnableEvent: ownable_cpt::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestCall {
        #[key]
        function_id: u256,
        input: Bytes,
        entry_address: ContractAddress,
        entry_calldata: Bytes,
        entry_gas_limit: u32,
        sender: ContractAddress,
        fee_amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestCallback {
        #[key]
        nonce: u32,
        #[key]
        function_id: u256,
        input: Bytes,
        context: Bytes,
        callback_addr: ContractAddress,
        callback_selector: felt252,
        callback_gas_limit: u32,
        fee_amount: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestFulfilled {
        #[key]
        nonce: u32,
        #[key]
        function_id: u256,
        input_hash: u256,
        output_hash: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Call {
        #[key]
        function_id: u256,
        input_hash: u256,
        output_hash: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SetFeeVault {
        old_fee_vault: ContractAddress,
        new_fee_vault: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct ProverUpdated {
        #[key]
        prover: ContractAddress,
        is_prover: bool,
    }

    mod Errors {
        const INVALID_CALL: felt252 = 'Invalid call to verify';
        const INVALID_REQUEST: felt252 = 'Invalid request for fullfilment';
        const INVALID_PROOF: felt252 = 'Invalid proof provided';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, owner: ContractAddress, fee_vault_address: ContractAddress
    ) {
        self.ownable.initializer(owner);
        self.fee_vault_address.write(fee_vault_address);
    }

    #[abi(embed_v0)]
    impl Upgradeable of IUpgradeable<ContractState> {
        /// Upgrades the contract to a new implementation.
        ///
        /// # Arguments
        ///
        /// * `new_class_hash` - The class hash of the new implementation.
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[abi(embed_v0)]
    impl ISuccinctGatewayImpl of ISuccinctGateway<ContractState> {
        /// Returns the fee vault address.
        ///
        /// # Returns
        ///
        /// * The fee vault address.
        fn get_fee_vault(self: @ContractState) -> ContractAddress {
            self.fee_vault_address.read()
        }
        /// Sets the fee vault address.
        ///
        /// # Arguments
        ///
        /// * `_fee_vault` - The fee vault address.
        fn set_fee_vault(ref self: ContractState, _fee_vault: ContractAddress) {
            self.ownable.assert_only_owner();
            self
                .emit(
                    SetFeeVault {
                        old_fee_vault: self.fee_vault_address.read(), new_fee_vault: _fee_vault,
                    }
                );
            self.fee_vault_address.write(_fee_vault);
        }

        /// Returns whether the specified prover is allowed or disallowed.
        ///
        /// # Arguments
        ///
        /// * `prover` - The prover address.
        ///
        /// # Returns
        ///
        /// * `is_prover` - Whether the prover is allowed or disallowed.
        fn get_prover(self: @ContractState, prover: ContractAddress) -> bool {
            self.allowed_provers.read(prover)
        }

        /// Sets the specified prover to be allowed or disallowed.
        ///
        /// # Arguments
        /// 
        /// * `prover` - The prover address.
        /// * `is_prover` - Whether the prover is allowed or disallowed.
        fn set_prover(ref self: ContractState, prover: ContractAddress, is_prover: bool) {
            self.ownable.assert_only_owner();
            self.allowed_provers.write(prover, is_prover);
            self.emit(ProverUpdated { prover, is_prover });
        }

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
            ref self: ContractState,
            function_id: u256,
            input: Bytes,
            context: Bytes,
            callback_selector: felt252,
            callback_gas_limit: u32,
        ) -> u256 {
            let nonce = self.nonce.read();
            let callback_addr = starknet::info::get_caller_address();
            let request_hash = InternalImpl::_request_hash(
                nonce,
                function_id,
                input.sha256(),
                context.keccak(),
                callback_addr,
                callback_selector,
                callback_gas_limit
            );
            self.requests.write(nonce, request_hash);
            self
                .emit(
                    RequestCallback {
                        nonce,
                        function_id,
                        input,
                        context,
                        callback_addr,
                        callback_selector,
                        callback_gas_limit,
                        fee_amount: starknet::info::get_tx_info().unbox().max_fee,
                    }
                );

            self.nonce.write(nonce + 1);

            // Fee Vault

            let fee_vault_address = self.fee_vault_address.read();
            if (!fee_vault_address.is_zero()) {
                let fee_vault = IFeeVaultDispatcher { contract_address: fee_vault_address };
                fee_vault.deposit_native(callback_addr);
            }

            request_hash
        }
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
            ref self: ContractState,
            function_id: u256,
            input: Bytes,
            entry_address: ContractAddress,
            entry_calldata: Bytes,
            entry_gas_limit: u32
        ) {
            self
                .emit(
                    RequestCall {
                        function_id,
                        input,
                        entry_address,
                        entry_calldata,
                        entry_gas_limit,
                        sender: starknet::info::get_caller_address(),
                        fee_amount: starknet::info::get_tx_info().unbox().max_fee,
                    }
                );

            // Fee Vault

            let fee_vault_address = self.fee_vault_address.read();
            if (!fee_vault_address.is_zero()) {
                let fee_vault = IFeeVaultDispatcher { contract_address: fee_vault_address };
                fee_vault.deposit_native(starknet::info::get_caller_address());
            }
        }

        /// If the call matches the currently verified function, returns the output. 
        /// Else this function reverts.
        ///
        /// # Arguments
        /// * `function_id` The function identifier.
        /// * `input` The function input.
        fn verified_call(self: @ContractState, function_id: u256, input: Bytes) -> (u256, u256) {
            assert(self.verified_function_id.read() == function_id, Errors::INVALID_CALL);
            assert(self.verified_input_hash.read() == input.sha256(), Errors::INVALID_CALL);

            self.verified_output.read()
        }

        fn fulfill_callback(
            ref self: ContractState,
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
        ) {
            self.reentrancy_guard.start();
            self.assert_only_prover();
            let request_hash = InternalImpl::_request_hash(
                nonce,
                function_id,
                input_hash,
                context.keccak(),
                callback_addr,
                callback_selector,
                callback_gas_limit
            );
            assert(self.requests.read(nonce) != request_hash, Errors::INVALID_REQUEST);

            let output_hash = output.sha256();

            let verifier = self.function_registry.verifiers.read(function_id);
            let is_valid_proof: bool = IFunctionVerifierDispatcher { contract_address: verifier }
                .verify(input_hash, output_hash, proof);
            assert(is_valid_proof, Errors::INVALID_PROOF);

            // Note : call_contract_syscall will always revert if the callback fails,
            //        so we don't need to check the result
            self.is_callback.write(true);
            call_contract_syscall(
                address: callback_addr,
                entry_point_selector: callback_selector,
                calldata: callback_calldata
            )
                .unwrap_syscall();
            self.is_callback.write(false);

            self.emit(RequestFulfilled { nonce, function_id, input_hash, output_hash, });

            self.reentrancy_guard.end();
        }

        fn fulfill_call(
            ref self: ContractState,
            function_id: u256,
            input: Bytes,
            output: Bytes,
            proof: Bytes,
            callback_addr: ContractAddress,
            callback_selector: felt252,
            callback_calldata: Span<felt252>,
        ) {
            self.reentrancy_guard.start();
            self.assert_only_prover();

            let input_hash = input.sha256();
            let output_hash = output.sha256();

            let verifier = self.function_registry.verifiers.read(function_id);

            let is_valid_proof: bool = IFunctionVerifierDispatcher { contract_address: verifier }
                .verify(input_hash, output_hash, proof);
            assert(is_valid_proof, Errors::INVALID_PROOF);

            // Set the current verified call.
            self.verified_function_id.write(function_id);
            self.verified_input_hash.write(input_hash);

            // TODO: make generic after refactor
            let (offset, data_commitment) = output.read_u256(0);
            let (_, next_header) = output.read_u256(offset);
            self.verified_output.write((data_commitment, next_header));

            // Note : call_contract_syscall will always revert if the callback fails,
            //        so we don't need to check the result
            call_contract_syscall(
                address: callback_addr,
                entry_point_selector: callback_selector,
                calldata: callback_calldata
            )
                .unwrap_syscall();

            // reset current verified call
            self.verified_function_id.write(0);
            self.verified_input_hash.write(0);
            self.verified_output.write((0, 0));

            self.emit(Call { function_id, input_hash, output_hash, });

            self.reentrancy_guard.end();
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Computes a unique identifier for a request.
        ///
        /// # Arguments
        ///
        /// * `nonce` The contract nonce.
        /// * `function_id` The function identifier.
        /// * `input_hash` The hash of the function input.
        /// * `context_hash` The hash of the function context.
        /// * `callback_address` The address of the callback contract.
        /// * `callback_selector` The selector of the callback function.
        /// * `callback_gas_limit` The gas limit for the callback function.
        fn _request_hash(
            nonce: u32,
            function_id: u256,
            input_hash: u256,
            context_hash: u256,
            callback_addr: ContractAddress,
            callback_selector: felt252,
            callback_gas_limit: u32
        ) -> u256 {
            let mut packed_req = BytesTrait::new_empty();
            packed_req.append_u32(nonce);
            packed_req.append_u256(function_id);
            packed_req.append_u256(input_hash);
            packed_req.append_u256(context_hash);
            packed_req.append_felt252(callback_addr.into());
            packed_req.append_felt252(callback_selector);
            packed_req.append_u32(callback_gas_limit);
            packed_req.keccak()
        }

        /// Protects functions from being called by anoyone other
        /// than the allowed provers.
        fn assert_only_prover(self: @ContractState) {
            let caller = starknet::info::get_caller_address();
            assert(self.allowed_provers.read(caller), 'Only allowed provers can call');
        }
    }
}
