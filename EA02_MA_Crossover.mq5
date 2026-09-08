// EA02_MA_Crossover.mq5
// Simple trend-following moving-average crossover.
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



input int FastMA=20;
input int SlowMA=50;
input ENUM_MA_METHOD MAMethod=MODE_EMA;
input ENUM_APPLIED_PRICE PriceType=PRICE_CLOSE;
int hf,hs;
int OnInit(){ hf=iMA(_Symbol,_Period,FastMA,0,MAMethod,PriceType); hs=iMA(_Symbol,_Period,SlowMA,0,MAMethod,PriceType); return (hf<0||hs<0)?INIT_FAILED:INIT_SUCCEEDED; }
void OnTick(){
 if(!IsNewBar() || (InpOnePosition&&HasPosition())) return;
 double f[3],s[3]; if(CopyBuffer(hf,0,0,3,f)<3||CopyBuffer(hs,0,0,3,s)<3)return;
 if(f[2]<=s[2] && f[1]>s[1]) Buy();
 if(f[2]>=s[2] && f[1]<s[1]) Sell();
}

