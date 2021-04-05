pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

interface CodeSwapMarket {
struct AskEntry {
uint256 tokenId;
uint256 price;
}

struct BidEntry {
address bidder;
uint256 price;
}

struct UserBidEntry {
uint256 tokenId;
uint256 price;
}
}
contract CodeSwapExchange is  IERC721Receiver, Ownable, Pausable, ReentrancyGuard {
    // 存储变量
    address public  nft;                                // NFT合约地址
    address public  quoteErc20;                         // 支付代币地址
    address public  feeAddr;                            // 手续费接收地址
    uint256 public  feePercent;                         // 手续费百分比，以10000为基数
    
    // 映射表
    mapping(uint256 => uint256) private tokenPrice;             // tokenId => price
    mapping(uint256 => address) private tokenSeller;            // tokenId => seller
    mapping(uint256 => mapping(address => uint256)) private tokenBidderPrice; // tokenId => bidder => price
    mapping(address => uint256[]) private userAskTokenIds;      // user => tokenIds
    mapping(address => mapping(uint256 => uint256)) private userAskTokenIdIndex; // user => tokenId => index
    mapping(uint256 => address[]) private tokenBidders;         // tokenId => bidders
    mapping(uint256 => mapping(address => uint256)) private tokenBidderIndex; // tokenId => bidder => index
    mapping(address => uint256[]) private userBidTokenIds;      // user => tokenIds
    mapping(address => mapping(uint256 => uint256)) private userBidTokenIdIndex; // user => tokenId => index
    
    uint256[] private askTokenIds;                              // 所有在售的tokenId
    mapping(uint256 => uint256) private askTokenIdIndex;        // tokenId => index
    
    // 构造函数
    constructor(address _nft, address _quoteErc20, address _feeAddr, uint256 _feePercent) {
        require(_nft != address(0), "NFT address cannot be zero");
        require(_quoteErc20 != address(0), "Quote ERC20 address cannot be zero");
        require(_feeAddr != address(0), "Fee address cannot be zero");
        require(_feePercent <= 10000, "Fee percent cannot exceed 100%");
        
        nft = _nft;
        quoteErc20 = _quoteErc20;
        feeAddr = _feeAddr;
        feePercent = _feePercent;
    }
event Ask( address indexed seller,uint256 indexed tokenId,uint256 price ) ;
event Bid( address indexed bidder,uint256 indexed tokenId,uint256 price ) ;
event CancelBidToken( address indexed bidder,uint256 indexed tokenId ) ;
event CancelSellToken( address indexed seller,uint256 indexed tokenId ) ;
event FeeAddressTransferred( address indexed previousOwner,address indexed newOwner ) ;
event SetFeePercent( address indexed seller,uint256 oldFeePercent,uint256 newFeePercent ) ;
event Trade( address indexed seller,address indexed buyer,uint256 indexed tokenId,uint256 price,uint256 fee ) ;  
    
    // 提供NFT上架销售功能
    function readyToSellToken(uint256 _tokenId, uint256 _price) external  {
        readyToSellTokenTo(_tokenId, _price, msg.sender);
    }
    
    function readyToSellTokenTo(uint256 _tokenId, uint256 _price, address _to) public  {
        require(!paused(), "Market is paused");
        require(_price > 0, "Price must be greater than zero");
        require(tokenSeller[_tokenId] == address(0), "Token is already for sale");
        
        IERC721(nft).safeTransferFrom(msg.sender, address(this), _tokenId);
        
        tokenPrice[_tokenId] = _price;
        tokenSeller[_tokenId] = _to;
        
        // 添加到用户的售卖列表
        userAskTokenIds[_to].push(_tokenId);
        userAskTokenIdIndex[_to][_tokenId] = userAskTokenIds[_to].length - 1;
        
        // 添加到全局售卖列表
        askTokenIds.push(_tokenId);
        askTokenIdIndex[_tokenId] = askTokenIds.length - 1;
        
        emit Ask(_to, _tokenId, _price);
    }
    
    // 取消上架NFT
    function cancelSellToken(uint256 _tokenId) external  {
        require(tokenSeller[_tokenId] == msg.sender, "Only seller can cancel");
        
        IERC721(nft).safeTransferFrom(address(this), msg.sender, _tokenId);
        
        // 从用户列表移除
        uint256 userLastIndex = userAskTokenIds[msg.sender].length - 1;
        uint256 userTokenIndex = userAskTokenIdIndex[msg.sender][_tokenId];
        
        if (userTokenIndex < userLastIndex) {
            uint256 lastTokenId = userAskTokenIds[msg.sender][userLastIndex];
            userAskTokenIds[msg.sender][userTokenIndex] = lastTokenId;
            userAskTokenIdIndex[msg.sender][lastTokenId] = userTokenIndex;
        }
        
        userAskTokenIds[msg.sender].pop();
        delete userAskTokenIdIndex[msg.sender][_tokenId];
        
        // 从全局列表移除
        uint256 lastIndex = askTokenIds.length - 1;
        uint256 tokenIndex = askTokenIdIndex[_tokenId];
        
        if (tokenIndex < lastIndex) {
            uint256 lastTokenId = askTokenIds[lastIndex];
            askTokenIds[tokenIndex] = lastTokenId;
            askTokenIdIndex[lastTokenId] = tokenIndex;
        }
        
        askTokenIds.pop();
        delete askTokenIdIndex[_tokenId];
        
        delete tokenPrice[_tokenId];
        delete tokenSeller[_tokenId];
        
        emit CancelSellToken(msg.sender, _tokenId);
    }
    
    // 更新售价
    function setCurrentPrice(uint256 _tokenId, uint256 _price) external  {
        require(tokenSeller[_tokenId] == msg.sender, "Only seller can update price");
        require(_price > 0, "Price must be greater than zero");
        
        tokenPrice[_tokenId] = _price;
        
        emit Ask(msg.sender, _tokenId, _price);
    }
    
    // 购买NFT
    function buyToken(uint256 _tokenId) external  {
        buyTokenTo(_tokenId, msg.sender);
    }
    
    function buyTokenTo(uint256 _tokenId, address _to) public  nonReentrant {
        require(!paused(), "Market is paused");
        require(tokenSeller[_tokenId] != address(0), "Token is not for sale");
        
        address seller = tokenSeller[_tokenId];
        uint256 price = tokenPrice[_tokenId];
        uint256 feeAmount = (price * feePercent) / 10000;
        uint256 sellerAmount = price - feeAmount;
        
        // 处理资金转移
        IERC20(quoteErc20).transferFrom(msg.sender, seller, sellerAmount);
        if (feeAmount > 0) {
            IERC20(quoteErc20).transferFrom(msg.sender, feeAddr, feeAmount);
        }
        
        // 从卖家列表移除
        uint256 userLastIndex = userAskTokenIds[seller].length - 1;
        uint256 userTokenIndex = userAskTokenIdIndex[seller][_tokenId];
        
        if (userTokenIndex < userLastIndex) {
            uint256 lastTokenId = userAskTokenIds[seller][userLastIndex];
            userAskTokenIds[seller][userTokenIndex] = lastTokenId;
            userAskTokenIdIndex[seller][lastTokenId] = userTokenIndex;
        }
        
        userAskTokenIds[seller].pop();
        delete userAskTokenIdIndex[seller][_tokenId];
        
        // 从全局列表移除
        uint256 lastIndex = askTokenIds.length - 1;
        uint256 tokenIndex = askTokenIdIndex[_tokenId];
        
        if (tokenIndex < lastIndex) {
            uint256 lastTokenId = askTokenIds[lastIndex];
            askTokenIds[tokenIndex] = lastTokenId;
            askTokenIdIndex[lastTokenId] = tokenIndex;
        }
        
        askTokenIds.pop();
        delete askTokenIdIndex[_tokenId];
        
        // 清除出价数据
        _clearBidsForToken(_tokenId);
        
        // 转移NFT
        IERC721(nft).safeTransferFrom(address(this), _to, _tokenId);
        
        // 清除售卖信息
        delete tokenPrice[_tokenId];
        delete tokenSeller[_tokenId];
        
        emit Trade(seller, _to, _tokenId, price, feeAmount);
    }
    
    // 直接卖给指定买家
    function sellTokenTo(uint256 _tokenId, address _to) external  nonReentrant {
        require(!paused(), "Market is paused");
        require(tokenSeller[_tokenId] == msg.sender, "Only seller can sell");
        
        uint256 price = tokenBidderPrice[_tokenId][_to];
        require(price > 0, "Buyer has no bid");
        
        uint256 feeAmount = (price * feePercent) / 10000;
        uint256 sellerAmount = price - feeAmount;
        
        // 处理资金转移
        IERC20(quoteErc20).transferFrom(_to, msg.sender, sellerAmount);
        if (feeAmount > 0) {
            IERC20(quoteErc20).transferFrom(_to, feeAddr, feeAmount);
        }
        
        // 从卖家列表移除
        uint256 userLastIndex = userAskTokenIds[msg.sender].length - 1;
        uint256 userTokenIndex = userAskTokenIdIndex[msg.sender][_tokenId];
        
        if (userTokenIndex < userLastIndex) {
            uint256 lastTokenId = userAskTokenIds[msg.sender][userLastIndex];
            userAskTokenIds[msg.sender][userTokenIndex] = lastTokenId;
            userAskTokenIdIndex[msg.sender][lastTokenId] = userTokenIndex;
        }
        
        userAskTokenIds[msg.sender].pop();
        delete userAskTokenIdIndex[msg.sender][_tokenId];
        
        // 从全局列表移除
        uint256 lastIndex = askTokenIds.length - 1;
        uint256 tokenIndex = askTokenIdIndex[_tokenId];
        
        if (tokenIndex < lastIndex) {
            uint256 lastTokenId = askTokenIds[lastIndex];
            askTokenIds[tokenIndex] = lastTokenId;
            askTokenIdIndex[lastTokenId] = tokenIndex;
        }
        
        askTokenIds.pop();
        delete askTokenIdIndex[_tokenId];
        
        // 清除该买家的出价
        _removeBidForToken(_tokenId, _to);
        
        // 清除出价数据
        _clearBidsForToken(_tokenId);
        
        // 转移NFT
        IERC721(nft).safeTransferFrom(address(this), _to, _tokenId);
        
        // 清除售卖信息
        delete tokenPrice[_tokenId];
        delete tokenSeller[_tokenId];
        
        emit Trade(msg.sender, _to, _tokenId, price, feeAmount);
    }
    
    // 出价功能
    function bidToken(uint256 _tokenId, uint256 _price) external  {
        require(!paused(), "Market is paused");
        require(_price > 0, "Price must be greater than zero");
        require(tokenSeller[_tokenId] != address(0), "Token is not for sale");
        require(tokenSeller[_tokenId] != msg.sender, "Seller cannot bid");
        
        if (tokenBidderPrice[_tokenId][msg.sender] == 0) {
            // 新的出价
            tokenBidders[_tokenId].push(msg.sender);
            tokenBidderIndex[_tokenId][msg.sender] = tokenBidders[_tokenId].length - 1;
            
            // 添加到用户出价列表
            if (userBidTokenIdIndex[msg.sender][_tokenId] == 0 && userBidTokenIds[msg.sender].length == 0) {
                userBidTokenIds[msg.sender].push(_tokenId);
                userBidTokenIdIndex[msg.sender][_tokenId] = 0;
            } else if (userBidTokenIdIndex[msg.sender][_tokenId] == 0) {
                userBidTokenIds[msg.sender].push(_tokenId);
                userBidTokenIdIndex[msg.sender][_tokenId] = userBidTokenIds[msg.sender].length - 1;
            }
        }
        
        tokenBidderPrice[_tokenId][msg.sender] = _price;
        
        emit Bid(msg.sender, _tokenId, _price);
    }
    
    // 更新出价
    function updateBidPrice(uint256 _tokenId, uint256 _price) external  {
        require(!paused(), "Market is paused");
        require(tokenBidderPrice[_tokenId][msg.sender] > 0, "No existing bid");
        require(_price > 0, "Price must be greater than zero");
        
        tokenBidderPrice[_tokenId][msg.sender] = _price;
        
        emit Bid(msg.sender, _tokenId, _price);
    }
    
    // 取消出价
    function cancelBidToken(uint256 _tokenId) external  {
        require(tokenBidderPrice[_tokenId][msg.sender] > 0, "No existing bid");
        
        _removeBidForToken(_tokenId, msg.sender);
        
        emit CancelBidToken(msg.sender, _tokenId);
    }
    
    // 获取所有在售列表
    function getAsks() external view  returns (CodeSwapMarket.AskEntry[] memory) {
        CodeSwapMarket.AskEntry[] memory asks = new CodeSwapMarket.AskEntry[](askTokenIds.length);
        
        for (uint256 i = 0; i < askTokenIds.length; i++) {
            asks[i] = CodeSwapMarket.AskEntry({
                tokenId: askTokenIds[i],
                price: tokenPrice[askTokenIds[i]]
            });
        }
        
        return asks;
    }
    
    // 获取所有在售列表（降序）
    function getAsksDesc() external view  returns (CodeSwapMarket.AskEntry[] memory) {
        CodeSwapMarket.AskEntry[] memory asks = new CodeSwapMarket.AskEntry[](askTokenIds.length);
        
        for (uint256 i = 0; i < askTokenIds.length; i++) {
            asks[i] = CodeSwapMarket.AskEntry({
                tokenId: askTokenIds[askTokenIds.length - 1 - i],
                price: tokenPrice[askTokenIds[askTokenIds.length - 1 - i]]
            });
        }
        
        return asks;
    }
    
    // 分页获取在售列表
    function getAsksByPage(uint256 page, uint256 size) external view  returns (CodeSwapMarket.AskEntry[] memory) {
        uint256 start = page * size;
        uint256 end = start + size;
        
        if (start >= askTokenIds.length) {
            return new CodeSwapMarket.AskEntry[](0);
        }
        
        if (end > askTokenIds.length) {
            end = askTokenIds.length;
        }
        
        CodeSwapMarket.AskEntry[] memory asks = new CodeSwapMarket.AskEntry[](end - start);
        
        for (uint256 i = start; i < end; i++) {
            asks[i - start] = CodeSwapMarket.AskEntry({
                tokenId: askTokenIds[i],
                price: tokenPrice[askTokenIds[i]]
            });
        }
        
        return asks;
    }
    
    // 分页获取在售列表（降序）
    function getAsksByPageDesc(uint256 page, uint256 size) external view  returns (CodeSwapMarket.AskEntry[] memory) {
        uint256 start = page * size;
        uint256 end = start + size;
        
        if (start >= askTokenIds.length) {
            return new CodeSwapMarket.AskEntry[](0);
        }
        
        if (end > askTokenIds.length) {
            end = askTokenIds.length;
        }
        
        CodeSwapMarket.AskEntry[] memory asks = new CodeSwapMarket.AskEntry[](end - start);
        
        for (uint256 i = start; i < end; i++) {
            asks[i - start] = CodeSwapMarket.AskEntry({
                tokenId: askTokenIds[askTokenIds.length - 1 - i],
                price: tokenPrice[askTokenIds[askTokenIds.length - 1 - i]]
            });
        }
        
        return asks;
    }
    
    // 获取用户在售列表
    function getAsksByUser(address user) external view  returns (CodeSwapMarket.AskEntry[] memory) {
        CodeSwapMarket.AskEntry[] memory asks = new CodeSwapMarket.AskEntry[](userAskTokenIds[user].length);
        
        for (uint256 i = 0; i < userAskTokenIds[user].length; i++) {
            asks[i] = CodeSwapMarket.AskEntry({
                tokenId: userAskTokenIds[user][i],
                price: tokenPrice[userAskTokenIds[user][i]]
            });
        }
        
        return asks;
    }
    
    // 获取用户在售列表（降序）
    function getAsksByUserDesc(address user) external view  returns (CodeSwapMarket.AskEntry[] memory) {
        CodeSwapMarket.AskEntry[] memory asks = new CodeSwapMarket.AskEntry[](userAskTokenIds[user].length);
        
        for (uint256 i = 0; i < userAskTokenIds[user].length; i++) {
            asks[i] = CodeSwapMarket.AskEntry({
                tokenId: userAskTokenIds[user][userAskTokenIds[user].length - 1 - i],
                price: tokenPrice[userAskTokenIds[user][userAskTokenIds[user].length - 1 - i]]
            });
        }
        
        return asks;
    }
    
    // 获取在售列表长度
    function getAskLength() external view  returns (uint256) {
        return askTokenIds.length;
    }
    
    // 获取某个NFT的所有出价
    function getBids(uint256 _tokenId) external view  returns (CodeSwapMarket.BidEntry[] memory) {
        CodeSwapMarket.BidEntry[] memory bids = new CodeSwapMarket.BidEntry[](tokenBidders[_tokenId].length);
        
        for (uint256 i = 0; i < tokenBidders[_tokenId].length; i++) {
            address bidder = tokenBidders[_tokenId][i];
            bids[i] = CodeSwapMarket.BidEntry({
                bidder: bidder,
                price: tokenBidderPrice[_tokenId][bidder]
            });
        }
        
        return bids;
    }
    
    // 获取某个NFT的出价数量
    function getBidsLength(uint256 _tokenId) external view  returns (uint256) {
        return tokenBidders[_tokenId].length;
    }
    
    // 获取用户所有出价
    function getUserBids(address user) external view  returns (CodeSwapMarket.UserBidEntry[] memory) {
        CodeSwapMarket.UserBidEntry[] memory bids = new CodeSwapMarket.UserBidEntry[](userBidTokenIds[user].length);
        
        for (uint256 i = 0; i < userBidTokenIds[user].length; i++) {
            uint256 tokenId = userBidTokenIds[user][i];
            bids[i] = CodeSwapMarket.UserBidEntry({
                tokenId: tokenId,
                price: tokenBidderPrice[tokenId][user]
            });
        }
        
        return bids;
    }
    
    // 设置手续费百分比
    function setFeePercent(uint256 _feePercent) external  onlyOwner {
        require(_feePercent <= 10000, "Fee percent cannot exceed 100%");
        uint256 oldFeePercent = feePercent;
        feePercent = _feePercent;
        emit SetFeePercent(msg.sender, oldFeePercent, _feePercent);
    }
    
    // 转移手续费接收地址
    function transferFeeAddress(address _feeAddr) external  onlyOwner {
        require(_feeAddr != address(0), "Fee address cannot be zero");
        address oldFeeAddr = feeAddr;
        feeAddr = _feeAddr;
        emit FeeAddressTransferred(oldFeeAddr, _feeAddr);
    }
    
    // 暂停市场
    function pause() external onlyOwner {
        _pause();
    }
    
    // 恢复市场
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // 内部函数：清除NFT的所有出价
    function _clearBidsForToken(uint256 _tokenId) private {
        for (uint256 i = 0; i < tokenBidders[_tokenId].length; i++) {
            address bidder = tokenBidders[_tokenId][i];
            
            // 从用户出价列表移除
            uint256 userLastIndex = userBidTokenIds[bidder].length - 1;
            uint256 userTokenIndex = userBidTokenIdIndex[bidder][_tokenId];
            
            if (userTokenIndex < userLastIndex) {
                uint256 lastTokenId = userBidTokenIds[bidder][userLastIndex];
                userBidTokenIds[bidder][userTokenIndex] = lastTokenId;
                userBidTokenIdIndex[bidder][lastTokenId] = userTokenIndex;
            }
            
            if (userBidTokenIds[bidder].length > 0) {
                userBidTokenIds[bidder].pop();
            }
            delete userBidTokenIdIndex[bidder][_tokenId];
            
            delete tokenBidderPrice[_tokenId][bidder];
        }
        
        delete tokenBidders[_tokenId];
    }
    
    // 内部函数：移除特定用户对NFT的出价
    function _removeBidForToken(uint256 _tokenId, address bidder) private {
        // 从代币出价者列表移除
        uint256 lastIndex = tokenBidders[_tokenId].length - 1;
        uint256 bidderIndex = tokenBidderIndex[_tokenId][bidder];
        
        if (bidderIndex < lastIndex) {
            address lastBidder = tokenBidders[_tokenId][lastIndex];
            tokenBidders[_tokenId][bidderIndex] = lastBidder;
            tokenBidderIndex[_tokenId][lastBidder] = bidderIndex;
        }
        
        if (tokenBidders[_tokenId].length > 0) {
            tokenBidders[_tokenId].pop();
        }
        delete tokenBidderIndex[_tokenId][bidder];
        
        // 从用户出价列表移除
        uint256 userLastIndex = userBidTokenIds[bidder].length - 1;
        uint256 userTokenIndex = userBidTokenIdIndex[bidder][_tokenId];
        
        if (userTokenIndex < userLastIndex) {
            uint256 lastTokenId = userBidTokenIds[bidder][userLastIndex];
            userBidTokenIds[bidder][userTokenIndex] = lastTokenId;
            userBidTokenIdIndex[bidder][lastTokenId] = userTokenIndex;
        }
        
        if (userBidTokenIds[bidder].length > 0) {
            userBidTokenIds[bidder].pop();
        }
        delete userBidTokenIdIndex[bidder][_tokenId];
        
        delete tokenBidderPrice[_tokenId][bidder];
    }
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }
} 