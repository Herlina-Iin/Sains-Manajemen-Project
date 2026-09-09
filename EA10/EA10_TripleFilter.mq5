// EA10_TripleFilter.mq5
// Composite trend strategy: EMA direction + RSI filter + MACD confirmation.
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



input int EMAperiod=50; input int RSIPeriod=14; input double RSIMid=50; input int MACDFast=12; input int MACDSlow=26; input int MACDSignal=9;
int he,hr,hm;
int OnInit(){ he=iMA(_Symbol,_Period,EMAperiod,0,MODE_EMA,PRICE_CLOSE); hr=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE); hm=iMACD(_Symbol,_Period,MACDFast,MACDSlow,MACDSignal,PRICE_CLOSE); return (he<0||hr<0||hm<0)?INIT_FAILED:INIT_SUCCEEDED; }
void OnTick(){
 if(!IsNewBar() || (InpOnePosition&&HasPosition()))return;
 double e[2],r[2],m[2],s[2]; if(CopyBuffer(he,0,0,2,e)<2||CopyBuffer(hr,0,0,2,r)<2||CopyBuffer(hm,0,0,2,m)<2||CopyBuffer(hm,1,0,2,s)<2)return;
 double c=iClose(_Symbol,_Period,1);
 if(c>e[1]&&r[1]>RSIMid&&m[1]>s[1])Buy();
 else if(c<e[1]&&r[1]<RSIMid&&m[1]<s[1])Sell();
}

