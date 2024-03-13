mod fee_vault;
mod gateway;
mod interfaces;
mod function_registry {
    mod component;
    mod interfaces;
    mod mock;
}
mod mocks {
    mod erc20_mock;
}
#[cfg(test)]
mod tests {
    mod test_fee_vault;
}
