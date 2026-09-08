// EA04_MACD_Trend.mq5
// MACD zero-line / signal crossover trend strategy.
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



input int Fast=12; input int Slow=26; input int Signal=9;
int hm;
int OnInit(){ hm=iMACD(_Symbol,_Period,Fast,Slow,Signal,PRICE_CLOSE); return hm<0?INIT_FAILED:INIT_SUCCEEDED; }
void OnTick(){
 if(!IsNewBar() || (InpOnePosition&&HasPosition())) return;
 double m[3],s[3]; if(CopyBuffer(hm,0,0,3,m)<3||CopyBuffer(hm,1,0,3,s)<3)return;
 if(m[2]<=s[2] && m[1]>s[1]) Buy();
 if(m[2]>=s[2] && m[1]<s[1]) Sell();
}

