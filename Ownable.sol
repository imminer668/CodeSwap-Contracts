pragma solidity ^0.8.0;

/**
 * @dev 提供基本的访问控制机制的合约
 */
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev 初始化合约时设置原始所有者
     */
    constructor() {
        _transferOwnership(msg.sender);
    }

    /**
     * @dev 返回当前所有者地址
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev 限制函数只能被所有者调用
     */
    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev 转移合约所有权给新地址
     * 只能被当前所有者调用
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev 转移所有权到新地址
     * 内部函数，无访问限制
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
} 