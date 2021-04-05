pragma solidity ^0.8.0;

/**
 * @dev 防止合约函数重入攻击的合约
 */
abstract contract ReentrancyGuard {
    // 如果值为1，表示没有重入调用，如果大于1，表示有重入调用
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev 防止函数调用期间发生合约重入
     * 可以帮助防止以下情况：调用函数A，该函数调用外部合约B，
     * 然后外部合约B再次调用函数A，这可能会导致状态混乱
     */
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // 设置状态为已进入
        _status = _ENTERED;

        // 执行函数体
        _;

        // 重置状态
        _status = _NOT_ENTERED;
    }
} 