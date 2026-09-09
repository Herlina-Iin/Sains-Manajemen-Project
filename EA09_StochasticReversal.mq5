// EA09_StochasticReversal.mq5
// Stochastic oscillator reversal with configurable zones.
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



input int KPeriod=14; input int DPeriod=3; input int Slowing=3; input double LowZone=20; input double HighZone=80;
int hs;
int OnInit(){ hs=iStochastic(_Symbol,_Period,KPeriod,DPeriod,Slowing,MODE_SMA,STO_LOWHIGH); return hs<0?INIT_FAILED:INIT_SUCCEEDED; }
void OnTick(){
 if(!IsNewBar() || (InpOnePosition&&HasPosition()))return;
 double k[3],d[3]; if(CopyBuffer(hs,0,0,3,k)<3||CopyBuffer(hs,1,0,3,d)<3)return;
 if(k[2]<LowZone&&k[1]>k[2]&&k[1]>d[1])Buy();
 if(k[2]>HighZone&&k[1]<k[2]&&k[1]<d[1])Sell();
}

