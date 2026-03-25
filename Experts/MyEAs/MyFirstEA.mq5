//+------------------------------------------------------------------+
//|                                               TradeCopierEA.mq5  |
//|                        Copyright 2024, Eston                     |
//|               A simple EA to copy trades from a master account   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Eston"
#property link      ""
#property version   "1.00"
#property description "Sao chép giao dịch từ tài khoản Master sang tài khoản Slave"

#include <Trade\Trade.mqh>

//--- Cài đặt đầu vào cho EA
input ulong  InpMasterAccountNumber = 12345678; // << NHẬP SỐ TÀI KHOẢN MASTER
input double InpLotMultiplier       = 1.0;      // Hệ số nhân khối lượng (1.0 = sao chép y hệt)
input int    InpMaxSlippage         = 30;       // Độ trượt giá tối đa cho phép (tính bằng point)
input int    InpMagicNumber         = 668899;   // Magic Number để EA nhận diện lệnh của chính nó

//--- Khai báo đối tượng và biến toàn cục
CTrade trade;
ulong  g_last_trade_ticket = 0; // Lưu ticket của lệnh master cuối cùng đã xử lý

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Thiết lập Magic Number cho đối tượng CTrade
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(InpMaxSlippage);

   Print("Trade Copier EA đã khởi tạo.");
   Print("Theo dõi tài khoản Master: ", InpMasterAccountNumber);
   Print("Hệ số Lot: ", InpLotMultiplier);
   Print("Magic Number: ", InpMagicNumber);
   
   //--- Kiểm tra xem có thể truy cập lịch sử giao dịch của tài khoản khác không
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("Giao dịch tự động chưa được cho phép trên terminal!");
      return(INIT_FAILED);
   }
   
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO)
      Print("EA đang chạy trên tài khoản Demo.");
   else
      Print("EA đang chạy trên tài khoản Live.");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Trade Copier EA đã dừng. Lý do: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function (hàm chạy mỗi khi có tick giá mới)          |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Chỉ chạy logic sao chép trên một chart duy nhất để tránh trùng lặp
   if(_Symbol != "EURUSD") // Bạn có thể đổi thành bất kỳ cặp tiền chính nào
   {
      // Comment(StringFormat("Chỉ chạy logic trên chart EURUSD. Chart hiện tại: %s", _Symbol));
      return;
   }
   
   //--- Sao chép các lệnh mới được mở
   CopyNewTrades();
   
   //--- Đồng bộ hóa các lệnh đang mở (đóng lệnh)
   SyncOpenTrades();
}

//+------------------------------------------------------------------+
//| Sao chép các lệnh mới từ tài khoản Master                        |
//+------------------------------------------------------------------+
void CopyNewTrades()
{
   //--- Chọn lịch sử giao dịch của tài khoản Master
   if(!HistorySelectByAccount(InpMasterAccountNumber, 0, TimeCurrent()))
   {
      Print("Lỗi khi truy cập lịch sử tài khoản Master: ", InpMasterAccountNumber, ". Error: ", GetLastError());
      return;
   }

   //--- Lấy tổng số giao dịch trong lịch sử đã chọn
   uint total_deals = HistoryDealsTotal();

   //--- Duyệt qua tất cả các giao dịch (deals)
   for(uint i = 0; i < total_deals; i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;

      //--- Chỉ xử lý các giao dịch "vào lệnh" (in)
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
         continue;

      //--- Kiểm tra xem lệnh này đã được sao chép chưa
      if(IsDealAlreadyCopied(deal_ticket))
         continue;

      //--- Lấy thông tin chi tiết của giao dịch
      long    order_type   = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
      long    position_id  = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
      string  symbol       = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
      double  volume       = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
      double  price        = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
      double  sl           = HistoryDealGetDouble(deal_ticket, DEAL_SL);
      double  tp           = HistoryDealGetDouble(deal_ticket, DEAL_TP);
      
      //--- Tính toán khối lượng cho tài khoản slave
      double slave_volume = NormalizeDouble(volume * InpLotMultiplier, 2);
      if(slave_volume < SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
         slave_volume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      //--- Thực hiện sao chép lệnh
      Print("Phát hiện lệnh mới từ Master. Ticket: ", deal_ticket, ", Loại: ", EnumToString((ENUM_ORDER_TYPE)order_type));
      
      bool result = false;
      switch(order_type)
      {
         case ORDER_TYPE_BUY:
         case ORDER_TYPE_SELL:
            // Đây là lệnh thị trường
            result = trade.PositionOpen(symbol, (ENUM_ORDER_TYPE)order_type, slave_volume, (order_type == ORDER_TYPE_BUY ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID)), sl, tp);
            break;
         
         case ORDER_TYPE_BUY_LIMIT:
         case ORDER_TYPE_SELL_LIMIT:
         case ORDER_TYPE_BUY_STOP:
         case ORDER_TYPE_SELL_STOP:
            // Đây là lệnh chờ
            result = trade.OrderSend(symbol, (ENUM_ORDER_TYPE)order_type, slave_volume, price, sl, tp);
            break;
      }
      
      if(result)
      {
         Print("Sao chép thành công lệnh ", deal_ticket, " sang tài khoản Slave. Symbol: ", symbol, ", Volume: ", slave_volume);
         // Lưu lại thông tin để không sao chép lại
         SaveCopiedDeal(deal_ticket, trade.ResultPositionID());
      }
      else
      {
         Print("Sao chép thất bại lệnh ", deal_ticket, ". Lỗi: ", trade.ResultComment());
      }
   }
}

//+------------------------------------------------------------------+
//| Đồng bộ hóa trạng thái đóng lệnh                                 |
//+------------------------------------------------------------------+
void SyncOpenTrades()
{
   //--- Duyệt qua các lệnh đang mở trên tài khoản Slave do EA này tạo ra
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong position_ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      //--- Lấy ID của lệnh gốc từ Master
      ulong master_position_id = GetMasterPositionID(position_ticket);
      if(master_position_id == 0)
         continue;

      //--- Kiểm tra xem lệnh gốc trên tài khoản Master còn tồn tại không
      if(!HistorySelectByAccount(InpMasterAccountNumber, 0, TimeCurrent()))
         continue;
      
      // HistoryOrderSelect trả về false nếu không tìm thấy, có nghĩa là lệnh đã bị đóng hoặc xóa
      if(!HistoryOrderSelect(master_position_id))
      {
         // Lệnh gốc đã bị đóng, tiến hành đóng lệnh trên tài khoản Slave
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         
         Print("Phát hiện lệnh Master (ID: ", master_position_id, ") đã đóng. Đang đóng lệnh Slave (Ticket: ", position_ticket, ")");
         
         if(trade.PositionClose(position_ticket))
         {
            Print("Đóng thành công lệnh Slave: ", position_ticket);
         }
         else
         {
            Print("Đóng lệnh Slave thất bại. Lỗi: ", trade.ResultComment());
         }
      }
   }
}


//--- Các hàm tiện ích ---

//--- Hàm này cần được phát triển thêm để lưu trữ thông tin sao chép một cách bền bỉ (ví dụ: dùng file hoặc biến toàn cục)
//--- Phiên bản đơn giản này chỉ lưu vào Comment của lệnh
void SaveCopiedDeal(ulong master_deal_ticket, ulong slave_position_id)
{
   if(slave_position_id > 0)
   {
      string comment = StringFormat("Copied from Deal %d / Pos %d", master_deal_ticket, HistoryDealGetInteger(master_deal_ticket, DEAL_POSITION_ID));
      trade.PositionModify(slave_position_id, 0, 0, comment);
   }
}

bool IsDealAlreadyCopied(ulong master_deal_ticket)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetInteger(i, POSITION_MAGIC) == InpMagicNumber)
      {
         string comment = PositionGetString(i, POSITION_COMMENT);
         if(StringFind(comment, StringFormat("Copied from Deal %d", master_deal_ticket)) != -1)
         {
            return true;
         }
      }
   }
   return false;
}

ulong GetMasterPositionID(ulong slave_position_ticket)
{
   string comment = PositionGetString(slave_position_ticket, POSITION_COMMENT);
   // Comment có dạng "Copied from Deal 12345 / Pos 67890"
   int pos_start = StringFind(comment, "/ Pos ") + 6;
   if(pos_start > 5)
   {
      string pos_id_str = StringSubstr(comment, pos_start);
      return (ulong)StringToInteger(pos_id_str);
   }
   return 0;
}
