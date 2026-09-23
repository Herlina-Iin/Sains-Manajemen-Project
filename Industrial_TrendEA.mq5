//+------------------------------------------------------------------+
//|                                        Industrial_TrendEA.mq5     |
//|  Industrial-grade multi-asset trend-following EA                 |
//|  Constraints honored:                                            |
//|   - NO Martingale, NO Grid, NO HFT (bar-based signals only)       |
//|   - NO leverage assumed in position sizing (lot sized as if 1:1)  |
//|   - Risk-per-trade based money management                        |
//|   - Monthly drawdown circuit breaker                              |
//|   - One position per symbol at a time                             |
//+------------------------------------------------------------------+
#property copyright "Industrial Grade Project"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Inputs: Strategy
input group "=== Trend Filter ==="
input int      InpFastEMA        = 50;      // Fast EMA period
input int      InpSlowEMA        = 200;     // Slow EMA period
input int      InpRSIPeriod      = 14;      // RSI period
input double   InpRSIBuyLevel    = 55.0;    // RSI must be above this to buy
input double   InpRSISellLevel   = 45.0;    // RSI must be below this to sell
input ENUM_TIMEFRAMES InpSignalTF = PERIOD_H4; // Signal timeframe (bar-close only, no tick entries)

input group "=== Volatility / Exit ==="
input int      InpATRPeriod      = 14;      // ATR period
input double   InpSL_ATR_Mult    = 2.0;     // Stop Loss = ATR * this
input double   InpTP_ATR_Mult    = 3.0;     // Take Profit = ATR * this
input bool     InpUseTrailing    = true;    // Use ATR trailing stop after 1R profit
input double   InpTrail_ATR_Mult = 1.5;     // Trailing distance = ATR * this

input group "=== Money Management (NO leverage, NO martingale) ==="
input double   InpRiskPercent    = 1.0;     // Risk per trade, % of equity (FIXED - never increases after loss)
input double   InpMaxLeverage    = 1.0;     // Position sizing capped as if leverage = 1:1
input int      InpMaxOpenPositionsPerSymbol = 1; // Hard cap, prevents grid-like stacking

input group "=== Drawdown Circuit Breaker ==="
input double   InpMonthlyLossStopPercent = 6.0;  // Stop trading rest of month if monthly loss exceeds this %
input double   InpMaxAccountDDStopPercent = 28.0;// Stop EA entirely if equity DD from peak exceeds this %

input group "=== Trade Frequency Guard (anti-HFT) ==="
input int      InpMinBarsBetweenTrades = 3; // Minimum closed bars between two entries (same symbol)

input group "=== Session Filter ==="
input bool     InpUseSessionFilter = false; // Restrict entries to a time window (broker server time)
input int      InpSessionStartHour = 7;
input int      InpSessionEndHour   = 20;

//--- Globals
double   g_equityPeakForMonth;
double   g_accountPeakEquity;
datetime g_currentMonthStart;
bool     g_monthlyStopHit = false;
bool     g_accountStopHit = false;
datetime g_lastTradeBarTime = 0;

int hFastEMA, hSlowEMA, hRSI, hATR;

//+------------------------------------------------------------------+
int OnInit()
  {
   hFastEMA = iMA(_Symbol, InpSignalTF, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEMA = iMA(_Symbol, InpSignalTF, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRSI     = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);
   hATR     = iATR(_Symbol, InpSignalTF, InpATRPeriod);

   if(hFastEMA==INVALID_HANDLE || hSlowEMA==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE)
     {
      Print("Indicator handle creation failed");
      return INIT_FAILED;
     }

   g_accountPeakEquity   = AccountInfoDouble(ACCOUNT_EQUITY);
   g_equityPeakForMonth  = g_accountPeakEquity;
   g_currentMonthStart   = CurrentMonthStart();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   IndicatorRelease(hFastEMA);
   IndicatorRelease(hSlowEMA);
   IndicatorRelease(hRSI);
   IndicatorRelease(hATR);
  }

//+------------------------------------------------------------------+
//| Helper: start of current month (server time)                      |
//+------------------------------------------------------------------+
datetime CurrentMonthStart()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.day = 1; dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Drawdown / circuit breaker checks                                  |
//+------------------------------------------------------------------+
void UpdateDrawdownGuards()
  {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Account-level peak & DD (permanent stop, never resets)
   if(equity > g_accountPeakEquity) g_accountPeakEquity = equity;
   double accountDD = (g_accountPeakEquity - equity) / g_accountPeakEquity * 100.0;
   if(accountDD >= InpMaxAccountDDStopPercent)
      g_accountStopHit = true;

   // Monthly reset
   datetime monthStart = CurrentMonthStart();
   if(monthStart != g_currentMonthStart)
     {
      g_currentMonthStart  = monthStart;
      g_equityPeakForMonth = equity;
      g_monthlyStopHit     = false;
     }

   if(equity > g_equityPeakForMonth) g_equityPeakForMonth = equity;
   double monthlyLoss = (g_equityPeakForMonth - equity) / g_equityPeakForMonth * 100.0;
   if(monthlyLoss >= InpMonthlyLossStopPercent)
      g_monthlyStopHit = true;
  }

//+------------------------------------------------------------------+
//| Session filter                                                     |
//+------------------------------------------------------------------+
bool InSession()
  {
   if(!InpUseSessionFilter) return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
   else
      return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
  }

//+------------------------------------------------------------------+
//| Position sizing - risk based, leverage capped at 1:1               |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePoints)
  {
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney  = equity * (InpRiskPercent / 100.0);

   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0) return 0.0;

   double slValuePerLot = (slDistancePoints / tickSize) * tickValue;
   if(slValuePerLot <= 0) return 0.0;

   double lot = riskMoney / slValuePerLot;

   // Leverage cap: notional exposure <= equity * InpMaxLeverage (i.e. no real leverage)
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double price         = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double maxNotional    = equity * InpMaxLeverage;
   double maxLotByNotional = (contractSize>0 && price>0) ? maxNotional/(contractSize*price) : lot;
   lot = MathMin(lot, maxLotByNotional);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = MathFloor(lot/lotStep)*lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));
   return lot;
  }

//+------------------------------------------------------------------+
//| Count open positions for this symbol/EA                            |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int cnt=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==(long)MagicNumber())
         cnt++;
     }
   return cnt;
  }

int MagicNumber(){ return 990045; }

//+------------------------------------------------------------------+
//| Entry logic - evaluated ONLY on new closed bar (anti-HFT)          |
//+------------------------------------------------------------------+
void CheckForEntry()
  {
   if(CountOpenPositions() >= InpMaxOpenPositionsPerSymbol) return;
   if(!InSession()) return;
   if(g_monthlyStopHit || g_accountStopHit) return;

   double emaFast[2], emaSlow[2], rsi[2], atr[2];
   if(CopyBuffer(hFastEMA,0,1,2,emaFast)<2) return;
   if(CopyBuffer(hSlowEMA,0,1,2,emaSlow)<2) return;
   if(CopyBuffer(hRSI,0,1,2,rsi)<2)         return;
   if(CopyBuffer(hATR,0,1,2,atr)<2)         return;

   double atrVal = atr[1];
   if(atrVal<=0) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   bool trendUp   = emaFast[1] > emaSlow[1];
   bool trendDown = emaFast[1] < emaSlow[1];
   bool rsiBuyOK  = rsi[1] >= InpRSIBuyLevel;
   bool rsiSellOK = rsi[1] <= InpRSISellLevel;

   double slDist = atrVal * InpSL_ATR_Mult;
   double tpDist = atrVal * InpTP_ATR_Mult;

   if(trendUp && rsiBuyOK)
     {
      double sl = ask - slDist;
      double tp = ask + tpDist;
      double lot = CalcLotSize(slDist);
      if(lot>0)
        {
         trade.SetExpertMagicNumber(MagicNumber());
         trade.Buy(lot, _Symbol, ask, sl, tp, "TrendEA-Buy");
         g_lastTradeBarTime = iTime(_Symbol, InpSignalTF, 0);
        }
     }
   else if(trendDown && rsiSellOK)
     {
      double sl = bid + slDist;
      double tp = bid - tpDist;
      double lot = CalcLotSize(slDist);
      if(lot>0)
        {
         trade.SetExpertMagicNumber(MagicNumber());
         trade.Sell(lot, _Symbol, bid, sl, tp, "TrendEA-Sell");
         g_lastTradeBarTime = iTime(_Symbol, InpSignalTF, 0);
        }
     }
  }

//+------------------------------------------------------------------+
//| ATR trailing stop management                                       |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   if(!InpUseTrailing) return;
   double atr[1];
   if(CopyBuffer(hATR,0,1,1,atr)<1) return;
   double trailDist = atr[0]*InpTrail_ATR_Mult;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC)!=(long)MagicNumber()) continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      if(type==POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = bid - trailDist;
         double oneR = MathAbs(openPrice - curSL);
         if(bid - openPrice > oneR && newSL > curSL)
            trade.PositionModify(ticket, newSL, curTP);
        }
      else if(type==POSITION_TYPE_SELL)
        {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = ask + trailDist;
         double oneR = MathAbs(curSL - openPrice);
         if(openPrice - ask > oneR && (curSL==0 || newSL < curSL))
            trade.PositionModify(ticket, newSL, curTP);
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert tick function                                                |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDrawdownGuards();
   ManageTrailing();

   // Bar-close only evaluation => not HFT, not tick-scalping
   datetime barTime = iTime(_Symbol, InpSignalTF, 0);
   if(barTime == g_lastTradeBarTime) return; // already acted this bar for entries guard below

   static datetime lastEvalBar = 0;
   if(barTime == lastEvalBar) return;
   lastEvalBar = barTime;

   // Minimum bar spacing between trades (anti-HFT / anti-overtrading)
   int barsSinceLastTrade = iBarShift(_Symbol, InpSignalTF, g_lastTradeBarTime);
   if(g_lastTradeBarTime>0 && barsSinceLastTrade < InpMinBarsBetweenTrades) return;

   CheckForEntry();
  }
//+------------------------------------------------------------------+
