// EA06_DonchianBreakout.mq5
// Donchian-channel breakout, inspired by classic Turtle-style trend following.
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



input int ChannelPeriod=20;
double Highest(int shift){ double a[]; ArraySetAsSeries(a,true); if(CopyHigh(_Symbol,_Period,shift,ChannelPeriod,a)<ChannelPeriod)return 0; return a[ArrayMaximum(a)]; }
double Lowest(int shift){ double a[]; ArraySetAsSeries(a,true); if(CopyLow(_Symbol,_Period,shift,ChannelPeriod,a)<ChannelPeriod)return 0; return a[ArrayMinimum(a)]; }
void OnTick(){
 if(!IsNewBar() || (InpOnePosition&&HasPosition())) return;
 double hi=Highest(2),lo=Lowest(2),c=iClose(_Symbol,_Period,1);
 if(hi>0&&c>hi) Buy(); else if(lo>0&&c<lo) Sell();
}

