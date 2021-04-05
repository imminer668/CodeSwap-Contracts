pragma solidity ^0.8.0;

/**
 * @dev ERC721接收者接口
 */
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
} 