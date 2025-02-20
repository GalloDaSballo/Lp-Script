interface ICurveFactory {
    function deploy_pool(
        string memory name,
        string memory symbol,
        address[2] memory _coins,
        uint256 A,
        uint256 gamma,
        uint256 mid_fee,
        uint256 out_fee,
        uint256 allowed_extra_profit,
        uint256 fee_gamma,
        uint256 adjustment_step,
        uint256 admin_fee,
        uint256 ma_half_time,
        uint256 initial_price
    ) external returns (address);
}

interface IOracle {
    function latestAnswer() external view returns (uint256);
}

interface ICurvePool {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function coins(uint256) external view returns (address);
    function balances(uint256) external view returns (uint256);
    function token() external view returns (address);
}
