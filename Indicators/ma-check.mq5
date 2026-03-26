//+------------------------------------------------------------------+
//|                                     MA_Slope_Color_Evaluator.mq5 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   1

// Định nghĩa màu sắc
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrDodgerBlue, clrRed, clrGray // 0: Tăng, 1: Giảm, 2: Đi ngang
#property indicator_width1  3

// Inputs
input int      InpMAPeriod   = 20;    // Chu kỳ MA
input int      InpSlopeLook  = 3;     // Số nến để tính độ dốc (Slope)
input double   InpThreshold  = 15.0;  // Ngưỡng "Đi ngang" (Tính bằng Points)

// Buffers
double         MABuffer[];
double         ColorBuffer[];

int            handleMA;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, MABuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);
   
   handleMA = iMA(_Symbol, _Period, InpMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const datetime &time[],
                const double &open[], const double &high[], const double &low[],
                const double &close[], const long &tick_volume[], const long &volume[],
                const int &spread[])
{
   if(rates_total < InpMAPeriod + InpSlopeLook) return(0);

   int limit = prev_calculated - 1;
   if(limit < InpSlopeLook) limit = InpSlopeLook;

   // Lấy dữ liệu MA
   double tempMA[];
   ArraySetAsSeries(tempMA, true);
   CopyBuffer(handleMA, 0, 0, rates_total, tempMA);
   ArraySetAsSeries(MABuffer, false); // Đảm bảo đồng bộ với rates_total

   for(int i = limit; i < rates_total; i++)
   {
      MABuffer[i] = tempMA[rates_total - 1 - i];
      
      // Tính độ dốc (So sánh với nến cách đó 'InpSlopeLook')
      double diff = MABuffer[i] - MABuffer[i - InpSlopeLook];
      double threshold_points = InpThreshold * _Point;

      if(diff > threshold_points) 
         ColorBuffer[i] = 0; // Xanh - Xu hướng Tăng
      else if(diff < -threshold_points) 
         ColorBuffer[i] = 1; // Đỏ - Xu hướng Giảm
      else 
         ColorBuffer[i] = 2; // Xám - ĐI NGANG (TRADING RANGE)
   }

   return(rates_total);
}