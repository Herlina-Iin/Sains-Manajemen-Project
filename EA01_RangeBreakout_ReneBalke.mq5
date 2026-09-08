// EA01_RangeBreakout_ReneBalke.mq5
// Rene Balke / BM Trading inspired morning time-range breakout. Rules simplified for academic replication.
// Educational project: backtest before any live use.
#property version "1.00"
#property strict
#include <Trade/Trade.mqh>
CTrade trade;

input double InpLots=0.10;
input int InpStopLossPoints=500;
input int InpTakeProfitPoints=1000;
input int InpMagic=260901;
input bool InpOnePosition=true;

datetime lastBar=0;

bool IsNewBar()
{
   datetime t=iTime(_Symbol,_Period,0);
   if(t==lastBar) return false;
   lastBar=t; return true;
}

bool HasPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
            (int)PositionGetInteger(POSITION_MAGIC)==InpMagic) return true;
   }
   return false;
}

double NormalizePrice(double p){ return NormalizeDouble(p,_Digits); }

bool Buy()
{
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl=(InpStopLossPoints>0)?NormalizePrice(ask-InpStopLossPoints*_Point):0;
   double tp=(InpTakeProfitPoints>0)?NormalizePrice(ask+InpTakeProfitPoints*_Point):0;
   trade.SetExpertMagicNumber(InpMagic);
   return trade.Buy(InpLots,_Symbol,ask,sl,tp);
}
bool Sell()
{
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=(InpStopLossPoints>0)?NormalizePrice(bid+InpStopLossPoints*_Point):0;
   double tp=(InpTakeProfitPoints>0)?NormalizePrice(bid-InpTakeProfitPoints*_Point):0;
   trade.SetExpertMagicNumber(InpMagic);
   return trade.Sell(InpLots,_Symbol,bid,sl,tp);
}



input int InpRangeStartHour=7;
input int InpRangeEndHour=9;
input int InpEntryHour=10;

double rangeHigh=0, rangeLow=0; int rangeDay=-1;

void BuildRange()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   if(d.day!=rangeDay){ rangeDay=d.day; rangeHigh=0; rangeLow=DBL_MAX; }
   if(d.hour>=InpRangeStartHour && d.hour<InpRangeEndHour)
   {
      double h=iHigh(_Symbol,_Period,1), l=iLow(_Symbol,_Period,1);
      if(h>0){ rangeHigh=MathMax(rangeHigh,h); rangeLow=MathMin(rangeLow,l); }
   }
}
void OnTick()
{
   BuildRange();
   if(!IsNewBar() || rangeHigh<=0 || rangeLow==DBL_MAX) return;
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   if(d.hour<InpEntryHour || d.hour>=InpEntryHour+2) return;
   if(InpOnePosition && HasPosition()) return;
   double close=iClose(_Symbol,_Period,1);
   if(close>rangeHigh) Buy();
   else if(close<rangeLow) Sell();
}

