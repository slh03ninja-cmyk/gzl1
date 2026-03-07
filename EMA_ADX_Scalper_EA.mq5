//+------------------------------------------------------------------+
//|                                       EMA_ADX_Scalper_EA.mq5    |
//|                    Expert Advisor - Version 1.1                  |
//|                                                                  |
//|  LOGIQUE IDENTIQUE A L INDICATEUR :                             |
//|                                                                  |
//|  PHASE 1 : ADX <= 12  (consolidation)                           |
//|  PHASE 2 : ADX >  12  (arme - attend croisement)               |
//|  PHASE 3 : Premier croisement ADX/DI EN HAUSSE apres remontee   |
//|    BUY  : ADX croise -DI + ADX en hausse + EMA21>EMA36>EMA150   |
//|    SELL : ADX croise +DI + ADX en hausse + EMA150>EMA36>EMA21   |
//|                                                                  |
//|  GESTION :                                                       |
//|    - SL fixe en USD (dollars) - adapte a XAUUSDm                |
//|    - TP fixe en USD (dollars) - adapte a XAUUSDm                |
//|    - 1 seule position a la fois                                  |
//|    - Filtre session Londres + New York (GMT+2)                   |
//|                                                                  |
//|  IMPORTANT XAUUSDm : _Point = 0.01                              |
//|    SL 10 USD = 1000 points  (ne pas utiliser les points !)      |
//|    SL 15 USD = 1500 points                                       |
//+------------------------------------------------------------------+
#property copyright "EMA_ADX_Scalper_EA v1.1"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
input group "=== EMAs ==="
input int    InpEMA21        = 21;
input int    InpEMA36        = 36;
input int    InpEMA150       = 150;

input group "=== ADX ==="
input int    InpADX_Period   = 21;
input double InpADX_Under    = 12.0;   // Seuil consolidation (<=)
input double InpADX_Confirm  = 12.0;   // Seuil sortie (>)

input group "=== Gestion du Risque ==="
input double InpLotSize      = 0.01;   // Taille du lot
input double InpSL_USD       = 15.0;   // Stop Loss en USD  (ex: 15.0 = 15$)
input double InpTP_USD       = 30.0;   // Take Profit en USD (ex: 30.0 = 30$)
input int    InpCooldown     = 6;      // Barres minimum entre signaux
input bool   InpOneTradeOnly = true;   // Une seule position a la fois

input group "=== Sessions GMT+2 Exness ==="
input bool   InpUseSession   = true;
input int    InpLondon_Start = 10;
input int    InpLondon_End   = 14;
input int    InpNY_Start     = 15;
input int    InpNY_End       = 22;

input group "=== Magic Number ==="
input int    InpMagic        = 202410;

//+------------------------------------------------------------------+
int h_EMA21  = INVALID_HANDLE;
int h_EMA36  = INVALID_HANDLE;
int h_EMA150 = INVALID_HANDLE;
int h_ADX    = INVALID_HANDLE;

// Machine a etats ADX
int      g_adxState  = 0;   // 0=neutre 1=consolidation 2=arme
int      g_lastBar   = 0;   // index barre du dernier signal
datetime g_lastTime  = 0;   // temps du dernier signal

//+------------------------------------------------------------------+
int OnInit()
  {
   // PRICE_WEIGHTED = HLCC/4
   h_EMA21  = iMA(_Symbol, PERIOD_CURRENT, InpEMA21,  0, MODE_EMA, PRICE_WEIGHTED);
   h_EMA36  = iMA(_Symbol, PERIOD_CURRENT, InpEMA36,  0, MODE_EMA, PRICE_WEIGHTED);
   h_EMA150 = iMA(_Symbol, PERIOD_CURRENT, InpEMA150, 0, MODE_EMA, PRICE_WEIGHTED);
   h_ADX    = iADXWilder(_Symbol, PERIOD_CURRENT, InpADX_Period);

   if(h_EMA21==INVALID_HANDLE || h_EMA36==INVALID_HANDLE ||
      h_EMA150==INVALID_HANDLE || h_ADX==INVALID_HANDLE)
     {
      Print("Erreur creation handles : ", GetLastError());
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   Print("EMA ADX Scalper EA initialise | ",
         _Symbol, " | ", EnumToString(Period()));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h_EMA21  != INVALID_HANDLE) IndicatorRelease(h_EMA21);
   if(h_EMA36  != INVALID_HANDLE) IndicatorRelease(h_EMA36);
   if(h_EMA150 != INVALID_HANDLE) IndicatorRelease(h_EMA150);
   if(h_ADX    != INVALID_HANDLE) IndicatorRelease(h_ADX);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   // Travailler uniquement sur la nouvelle barre fermee
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   // Lire les valeurs sur la barre precedente (index 1 = barre fermee)
   double ema21  = GetBuffer(h_EMA21,  0, 1);
   double ema36  = GetBuffer(h_EMA36,  0, 1);
   double ema150 = GetBuffer(h_EMA150, 0, 1);
   double adxCur = GetBuffer(h_ADX,    0, 1);
   double dipCur = GetBuffer(h_ADX,    1, 1);
   double dimCur = GetBuffer(h_ADX,    2, 1);

   // Barre d avant (index 2) pour detecter croisement
   double ema21_p  = GetBuffer(h_EMA21,  0, 2);
   double ema36_p  = GetBuffer(h_EMA36,  0, 2);
   double ema150_p = GetBuffer(h_EMA150, 0, 2);
   double adxPrev  = GetBuffer(h_ADX,    0, 2);
   double dipPrev  = GetBuffer(h_ADX,    1, 2);
   double dimPrev  = GetBuffer(h_ADX,    2, 2);

   if(adxCur <= 0 || ema21 <= 0) return;

   //================================================================
   // MACHINE A ETATS ADX
   //================================================================

   // Phase 1 : consolidation (ADX <= seuil, 12.00 inclus)
   if(adxCur <= InpADX_Under)
     {
      g_adxState = 1;
     }
   // Phase 2 : sortie consolidation -> on arme
   else if(g_adxState == 1 && adxCur > InpADX_Confirm)
     {
      g_adxState = 2;
     }
   // Retour phase 1 si ADX redescend alors qu on etait arme
   else if(g_adxState == 2 && adxCur <= InpADX_Under)
     {
      g_adxState = 1;
     }

   // Signal uniquement si arme
   if(g_adxState != 2) return;

   //================================================================
   // FILTRE SESSION GMT+2
   //================================================================
   if(InpUseSession)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int curMin    = dt.hour * 60 + dt.min;
      int londonStart = InpLondon_Start * 60;
      int londonEnd   = InpLondon_End   * 60;
      int nyStart     = InpNY_Start     * 60;
      int nyEnd       = InpNY_End       * 60;
      bool inSession  = (curMin >= londonStart && curMin < londonEnd) ||
                        (curMin >= nyStart     && curMin < nyEnd);
      if(!inSession) return;
     }

   //================================================================
   // COOLDOWN - eviter signaux trop rapproches
   //================================================================
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   int periodSec    = PeriodSeconds(PERIOD_CURRENT);
   if((int)((barTime - g_lastTime) / periodSec) < InpCooldown) return;

   //================================================================
   // POSITION EXISTANTE
   //================================================================
   if(InpOneTradeOnly && PositionsTotal() > 0)
     {
      // Verifier si une position de cet EA existe
      for(int p = 0; p < PositionsTotal(); p++)
        {
         ulong ticket = PositionGetTicket(p);
         if(PositionSelectByTicket(ticket))
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
               return;
        }
     }

   //================================================================
   // ALIGNEMENT EMAs
   //================================================================
   bool emaBull = (ema21 > ema36 && ema36 > ema150);
   bool emaBear = (ema150 > ema36 && ema36 > ema21);
   if(!emaBull && !emaBear) return;

   //================================================================
   // ADX EN HAUSSE au moment du croisement
   //================================================================
   bool adxRising = (adxCur > adxPrev);
   if(!adxRising) return;

   //================================================================
   // CROISEMENT DI
   // BUY  : ADX croise -DI vers le haut
   // SELL : ADX croise +DI vers le haut
   //================================================================
   bool crossBuy  = emaBull && (adxCur > dimCur) && (adxPrev <= dimPrev);
   bool crossSell = emaBear && (adxCur > dipCur) && (adxPrev <= dipPrev);

   if(!crossBuy && !crossSell) return;

   //================================================================
   // CALCUL SL / TP EN USD (direct, indépendant de _Point)
   //================================================================
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Sur XAUUSDm : 1 USD de mouvement = 1 dollar
   // On convertit les USD en ecart de prix
   // Pour l or : prix en USD/oz donc 1 USD = 1 unite de prix
   double sl_dist = NormalizeDouble(InpSL_USD, _Digits);
   double tp_dist = NormalizeDouble(InpTP_USD, _Digits);

   //================================================================
   // EXECUTION
   //================================================================
   if(crossBuy)
     {
      double sl = NormalizeDouble(ask - sl_dist, _Digits);
      double tp = NormalizeDouble(ask + tp_dist, _Digits);
      if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp,
                   StringFormat("EMA ADX BUY | ADX:%.1f -DI:%.1f", adxCur, dimCur)))
        {
         g_adxState = 0;  // reset cycle
         g_lastTime = barTime;
         Print(StringFormat("[BUY]  Prix:%.2f | SL:%.2f (+%.1f$) | TP:%.2f (+%.1f$) | ADX:%.1f | -DI:%.1f",
               ask, sl, InpSL_USD, tp, InpTP_USD, adxCur, dimCur));
        }
      else
         Print("Erreur BUY : ", trade.ResultRetcodeDescription());
     }
   else if(crossSell)
     {
      double sl = NormalizeDouble(bid + sl_dist, _Digits);
      double tp = NormalizeDouble(bid - tp_dist, _Digits);
      if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp,
                    StringFormat("EMA ADX SELL | ADX:%.1f +DI:%.1f", adxCur, dipCur)))
        {
         g_adxState = 0;  // reset cycle
         g_lastTime = barTime;
         Print(StringFormat("[SELL] Prix:%.2f | SL:%.2f (+%.1f$) | TP:%.2f (+%.1f$) | ADX:%.1f | +DI:%.1f",
               bid, sl, InpSL_USD, tp, InpTP_USD, adxCur, dipCur));
        }
      else
         Print("Erreur SELL : ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
// Lecture securisee d un buffer indicateur
//+------------------------------------------------------------------+
double GetBuffer(int handle, int buffer, int shift)
  {
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) <= 0)
     {
      Print("GetBuffer erreur : handle=", handle,
            " buf=", buffer, " shift=", shift,
            " err=", GetLastError());
      return 0;
     }
   return arr[0];
  }

//+------------------------------------------------------------------+
//  FIN - EMA_ADX_Scalper_EA v1.0
//+------------------------------------------------------------------+
