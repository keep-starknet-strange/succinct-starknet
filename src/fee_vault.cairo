#[starknet::contract]
mod succinct_fee_vault {
    use core::starknet::event::EventEmitter;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::ownable::ownable::OwnableComponent::InternalTrait;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::{interface::IUpgradeable, upgradeable::UpgradeableComponent};
    use starknet::{ContractAddress, get_caller_address, ClassHash};
    use succinct_sn::interfaces::IFeeVault;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        // balances[token][account] => token balance for Succinct services.
        balances: LegacyMap::<(ContractAddress, ContractAddress), u256>,
        allowed_deductors: LegacyMap::<ContractAddress, bool>,
        native_currency_address: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Received: Received,
        Deducted: Deducted,
        Collected: Collected,
        // COMPONENT EVENTS
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Received {
        #[key]
        account: ContractAddress,
        #[key]
        token: ContractAddress,
        amount: u256
    }
    #[derive(Drop, starknet::Event)]
    struct Deducted {
        #[key]
        account: ContractAddress,
        #[key]
        token: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct Collected {
        #[key]
        to: ContractAddress,
        #[key]
        token: ContractAddress,
        amount: u256,
    }


    mod Errors {
        /// Data commitment for specified block range does not exist
        const InvalidAccount: felt252 = 'Invalid account';
        const InvalidToken: felt252 = 'Invalid token';
        const InsufficientAllowance: felt252 = 'Insufficient allowance';
        const OnlyDeductor: felt252 = 'Only deductor allowed';
        const InsufficientBalance: felt252 = 'Insufficient balance';
        const ERC20TransferFailed: felt252 = 'ERC20 transfer failed';
    }

    #[abi(embed_v0)]
    impl Upgradeable of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, native_currency_address: ContractAddress, owner: ContractAddress
    ) {
        self.native_currency_address.write(native_currency_address);
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl IFeeVaultImpl of IFeeVault<ContractState> {
        
        fn get_native_currency(self: @ContractState) -> ContractAddress {
            self.native_currency_address.read()
        }

       
        fn set_native_currency(ref self: ContractState, _new_native_address: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!_new_native_address.is_zero(), Errors::InvalidToken);
            self.native_currency_address.write(_new_native_address);
        }


       
        fn is_deductor(self: @ContractState, _deductor: ContractAddress) -> bool {
            self.allowed_deductors.read(_deductor)
        }

    
        fn add_deductor(ref self: ContractState, _deductor: ContractAddress) {
            self.ownable.assert_only_owner();
            self.allowed_deductors.write(_deductor, true);
        }

     
        fn remove_deductor(ref self: ContractState, _deductor: ContractAddress) {
            self.ownable.assert_only_owner();
            self.allowed_deductors.write(_deductor, false);
        }

       
        fn get_account_balance(
            self: @ContractState, _account: ContractAddress, _token: ContractAddress
        ) -> u256 {
            self.balances.read((_token, _account))
        }

     
        fn deposit_native(ref self: ContractState, _account: ContractAddress) {
            let native_currency = self.native_currency_address.read();
            self
                .deposit(
                    _account, native_currency, starknet::info::get_tx_info().unbox().max_fee.into()
                );
        }

     
        fn deposit(
            ref self: ContractState,
            _account: ContractAddress,
            _token: ContractAddress,
            _amount: u256
        ) {
            let caller_address = get_caller_address();
            let contract_address = starknet::info::get_contract_address();
            assert(!_account.is_zero(), Errors::InvalidAccount);
            assert(!_token.is_zero(), Errors::InvalidToken);
            let erc20_dispatcher = IERC20Dispatcher { contract_address: _token };
            let allowance = erc20_dispatcher.allowance(caller_address, contract_address);
            assert(allowance >= _amount, Errors::InsufficientAllowance);
            let success = erc20_dispatcher.transfer_from(caller_address, contract_address, _amount);
            assert(success, Errors::ERC20TransferFailed);
            let current_balance = self.balances.read((_token, _account));
            self.balances.write((_token, _account), current_balance + _amount);
            self.emit(Received { account: _account, token: _token, amount: _amount });
        }


        fn deduct_native(ref self: ContractState, _account: ContractAddress) {
            let native_currency = self.native_currency_address.read();
            self
                .deduct(
                    _account, native_currency, starknet::info::get_tx_info().unbox().max_fee.into()
                );
        }

    
        fn deduct(
            ref self: ContractState,
            _account: ContractAddress,
            _token: ContractAddress,
            _amount: u256
        ) {
            let caller_address = get_caller_address();
            assert(self.is_deductor(caller_address), Errors::OnlyDeductor);
            assert(!_account.is_zero(), Errors::InvalidAccount);
            assert(!_token.is_zero(), Errors::InvalidToken);
            let current_balance = self.balances.read((_token, _account));
            assert(current_balance >= _amount, Errors::InsufficientBalance);
            self.balances.write((_token, _account), current_balance - _amount);
            self.emit(Deducted { account: _account, token: _token, amount: _amount });
        }

        /// Collect the specified amount of native currency.
        /// * `_to`-  The address to send the collected native currency to.
        /// * `_amount`- The amount of native currency to collect.
        fn collect_native(ref self: ContractState, _to: ContractAddress, _amount: u256) {
            self.ownable.assert_only_owner();
            let native_currency = self.native_currency_address.read();
            self.collect(_to, native_currency, _amount);
        }

 
        fn collect(
            ref self: ContractState, _to: ContractAddress, _token: ContractAddress, _amount: u256
        ) {
            self.ownable.assert_only_owner();
            let contract_address = starknet::info::get_contract_address();
            assert(!_token.is_zero(), Errors::InvalidToken);
            let erc20_dispatcher = IERC20Dispatcher { contract_address: _token };
            assert(
                erc20_dispatcher.balance_of(contract_address) >= _amount,
                Errors::InsufficientBalance
            );
            let success = erc20_dispatcher.transfer(_to, _amount);
            assert(success, Errors::ERC20TransferFailed);
            self.emit(Collected { to: _to, token: _token, amount: _amount })
        }
    }
}

