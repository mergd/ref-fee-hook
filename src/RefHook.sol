// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {IHookFeeManager} from "@uniswap/v4-core/contracts/interfaces/IHookFeeManager.sol";
import {IDynamicFeeManager} from "@uniswap/v4-core/contracts/interfaces/IDynamicFeeManager.sol";

contract Counter is BaseHook, IHookFeeManager, IDynamicFeeManager {
    using PoolIdLibrary for PoolKey;

    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------
    // Two variables to tracking hook fees
    uint256 private startFee0;
    uint256 private startFee1;

    struct Fees {
        uint128 fee0;
        uint128 fee1;
    }

    uint24 public immutable REF_FEE;
    mapping(bytes32 refCode => mapping(PoolId => Fees accruedFees)) public refFees;
    mapping(bytes32 refCode => address referrer) public refs;
    mapping(address lp => bytes32 refCode) public lpToRef;

    constructor(IPoolManager _poolManager, uint24 _ref_fee) BaseHook(_poolManager) {
        REF_FEE = _ref_fee;
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true,
            afterModifyPosition: true,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function getFee(address sender, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata data)
        external
        returns (uint24)
    {
        if (ref == bytes32(0) || refs[ref] == address(0)) return 0;
        else return REF_FEE;
    }
    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        if (params.zeroForOne) {
            startFee0 = poolManager.hookFeesAccrued(address(key.hooks), key.currency0);
        } else {
            startFee1 = poolManager.hookFeesAccrued(address(key.hooks), key.currency1);
        }
        return BaseHook.beforeSwap.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata ref
    ) external override returns (bytes4) {
        PoolId id = key.toId();
        Fees fee = new Fees();
        if (ref == bytes32(0) || refs[ref] == bytes32(0)) return BaseHook.afterSwap.selector;

        // Calculate swap hook swap fees
        if (params.zeroForOne) {
            uint256 hookFee0 = poolManager.hookFeesAccrued(address(key.hooks), key.currency0);
            fees.fee0 += uint128(startFee0 - hookfee0);
        } else {
            uint256 hookFee1 = poolManager.hookFeesAccrued(address(key.hooks), key.currency1);
            fees.fee1 += uint128(startFee1 - hookfee1);
        }
        refFees[ref][id] = fee;
        return BaseHook.afterSwap.selector;
    }

    function beforeModifyPosition(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        startFee0 = poolManager.hookFeesAccrued(address(key.hooks), key.currency0);

        startFee1 = poolManager.hookFeesAccrued(address(key.hooks), key.currency1);

        return BaseHook.beforeModifyPosition.selector;
    }

    function afterModifyPosition(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4) {
        // Calculate LP hook fees
        Fees fee = new Fees();
        PoolId id = key.toId();

        uint256 hookFee0 = poolManager.hookFeesAccrued(address(key.hooks), key.currency0);
        fees.fee0 += uint128(startFee0 - hookfee0);

        uint256 hookFee1 = poolManager.hookFeesAccrued(address(key.hooks), key.currency1);
        fees.fee1 += uint128(startFee1 - hookfee1);

        refFees[ref][id] = fee;
        return BaseHook.afterModifyPosition.selector;
    }

    function generateRefLink(bytes32 refCode) external returns (bytes32 code) {
        require(refs[refCode] == address(0), "refcode already set");
        if (refCode == bytes32(0)) code = bytes32(msg.sender);
        else code = refCode;
    }

    function updateRefLink(bytes32 refCode, address newAddr) external {
        if (refs[refCode] != msg.sender) revert("Not referrer");
        refs[refCode] = newAddr;
    }

    function claimRefLinkFees(bytes32 refCode, PoolId id, Currency[] calldata currencies) external {
        Fees _fee = refFees[refCode][id];
        poolManager.collectHookFees(address(0), currencies[0], _fee.fee0);
        poolManager.collectHookFees(address(0), currencies[1], _fee.fee1);
    }
}
