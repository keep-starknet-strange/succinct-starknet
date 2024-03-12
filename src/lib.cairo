mod fee_vault;
mod gateway;
mod interfaces;
mod function_registry {
    mod component;
    mod erc20_mock;
    mod interfaces;
    mod mock;
}
#[cfg(test)]
mod tests {
    mod test_fee_vault;
}
