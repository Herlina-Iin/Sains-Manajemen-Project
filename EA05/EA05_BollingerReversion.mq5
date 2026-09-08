// EA05_BollingerReversion.mq5
// Bollinger Band mean-reversion: close back inside the band.
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



input int BBPeriod=20; input double BBDeviation=2.0;
int hb;
int OnInit(){ hb=iBands(_Symbol,_Period,BBPeriod,0,BBDeviation,PRICE_CLOSE); return hb<0?INIT_FAILED:INIT_SUCCEEDED; }
void OnTick(){
 if(!IsNewBar() || (InpOnePosition&&HasPosition())) return;
 double up[3],mid[3],lo[3],c[3];
 if(CopyBuffer(hb,1,0,3,up)<3||CopyBuffer(hb,0,0,3,mid)<3||CopyBuffer(hb,2,0,3,lo)<3||CopyClose(_Symbol,_Period,0,3,c)<3)return;
 if(c[2]<lo[2] && c[1]>lo[1]) Buy();
 if(c[2]>up[2] && c[1]<up[1]) Sell();
}

