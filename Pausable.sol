pragma solidity ^0.8.0;

/**
 * @dev 实现可暂停功能的合约
 */
abstract contract Pausable {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev 初始化为非暂停状态
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev 返回合约是否暂停
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev 要求合约未暂停
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev 要求合约已暂停
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev 触发合约暂停状态
     * 设置`_paused`为true并触发`Paused`事件
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev 触发合约恢复状态
     * 设置`_paused`为false并触发`Unpaused`事件
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
} 