//+------------------------------------------------------------------+
//|                                    EMA_ADX_Scalper_EA.mq5       |
//|                          Expert Advisor — Version 1.5            |
//|                                                                  |
//|  ════════════════════════════════════════════════════════════    |
//|  LOGIQUE DE BASE (inchangee depuis v1.4) :                      |
//|    Phase 1 : ADX <= seuil consolidation                         |
//|    Phase 2 : ADX >  seuil sortie  → arme                       |
//|    Phase 3 : Croisement ADX/DI + ADX en hausse + EMAs alignes   |
//|                                                                  |
//|  NOUVEAUTES v1.5 — 3 couches optionnelles :                     |
//|                                                                  |
//|  COUCHE 1 — RSI (InpUseRSI)                                     |
//|    BUY  valide si : InpRSI_BuyMin  < RSI < InpRSI_BuyMax        |
//|    SELL valide si : InpRSI_SellMin < RSI < InpRSI_SellMax       |
//|                                                                  |
//|  COUCHE 2 — ATR SL/TP dynamique (InpUseATR)                     |
//|    SL = ATR(periode) x InpSL_ATR                                |
//|    TP = ATR(periode) x InpTP_ATR                                |
//|    Si false : SL/TP fixes en pips (comportement v1.4)           |
//|                                                                  |
//|  COUCHE 3 — Breakeven + Trailing ATR (independants)             |
//|    InpUseBreakeven : SL au prix entree quand profit >= BE_ATR    |
//|    InpUseTrail     : trail SL a Trail_ATR x ATR derriere prix   |
//|                      demarre quand profit >= TrailStart x ATR    |
//|                                                                  |
//|  Toutes les couches sont independantes (true/false)             |
//+------------------------------------------------------------------+
#property copyright "EMA_ADX_Scalper_EA v1.5.1"
#property version   "1.51"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//  INPUTS
//+------------------------------------------------------------------+

input group "=== EMAs ==="
input int    InpEMA21        = 20;
input int    InpEMA36        = 46;
input int    InpEMA150       = 200;
input bool   InpUseEMA200    = true;    // true=EMA20>EMA46>EMA200 | false=EMA20>EMA46 seulement

input group "=== ADX ==="
input int    InpADX_Period   = 20;
input double InpADX_Under    = 10.0;   // Seuil consolidation (<=)
input double InpADX_Confirm  = 13.0;   // Seuil sortie (>)

input group "=== COUCHE 1 : Filtre RSI ==="
input bool   InpUseRSI       = true;   // Activer filtre RSI
input int    InpRSI_Period   = 14;     // Periode RSI
input double InpRSI_BuyMin   = 50.0;  // RSI minimum pour BUY  (momentum haussier)
input double InpRSI_BuyMax   = 70.0;  // RSI maximum pour BUY  (eviter surachat)
input double InpRSI_SellMin  = 30.0;  // RSI minimum pour SELL (eviter survente)
input double InpRSI_SellMax  = 50.0;  // RSI maximum pour SELL (momentum baissier)

input group "=== COUCHE 2 : ATR SL/TP Dynamique ==="
input bool   InpUseATR       = true;   // true=SL/TP bases sur ATR | false=pips fixes
input int    InpATR_Period   = 14;     // Periode ATR
input double InpSL_ATR       = 1.5;   // SL = ATR x ce multiplicateur
input double InpTP_ATR       = 3.0;   // TP = ATR x ce multiplicateur (ratio 1:2)

input group "=== Gestion du Risque (SL/TP fixes si ATR desactive) ==="
input double InpLotSize      = 0.01;   // Taille du lot
input int    InpSL_Pips      = 3000;   // Stop Loss en pips  (si InpUseATR=false)
input int    InpTP_Pips      = 3000;   // Take Profit en pips (si InpUseATR=false)
input int    InpCooldown     = 6;      // Barres minimum entre signaux
input bool   InpOneTradeOnly = true;   // Une seule position a la fois

input group "=== COUCHE 3a : Breakeven Automatique ==="
input bool   InpUseBreakeven = true;   // Activer breakeven automatique
input double InpBE_ATR       = 1.0;   // Declencher BE quand profit >= ATR x valeur
input int    InpBE_Buffer    = 5;      // Points buffer au-dela du prix d entree

input group "=== COUCHE 3b : Trailing Stop ATR ==="
input bool   InpUseTrail     = true;   // Activer trailing stop ATR
input double InpTrailStart   = 1.5;   // Commencer trail quand profit >= ATR x valeur
input double InpTrail_ATR    = 1.0;   // Distance trail = ATR x ce multiplicateur

input group "=== Sessions GMT+2 Exness ==="
input bool   InpUseAsie      = true;   // Session Asie    (02h - 10h)
input int    InpAsie_Start   = 2;      // Asie heure debut
input int    InpAsie_End     = 10;     // Asie heure fin
input bool   InpUseLondres   = true;   // Session Londres (10h - 14h)
input int    InpLondres_Start= 10;     // Londres heure debut
input int    InpLondres_End  = 14;     // Londres heure fin
input bool   InpUseNY        = true;   // Session NY      (14h - 21h)
input int    InpNY_Start     = 14;     // NY heure debut
input int    InpNY_End       = 21;     // NY heure fin

input group "=== Magic Number ==="
input int    InpMagic        = 202410;

//+------------------------------------------------------------------+
//  HANDLES GLOBAUX
//+------------------------------------------------------------------+
int h_EMA21  = INVALID_HANDLE;
int h_EMA36  = INVALID_HANDLE;
int h_EMA150 = INVALID_HANDLE;
int h_ADX    = INVALID_HANDLE;
int h_RSI    = INVALID_HANDLE;
int h_ATR    = INVALID_HANDLE;

// Machine a etats ADX
int      g_adxState = 0;
datetime g_lastTime = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   h_EMA21  = iMA(_Symbol, PERIOD_CURRENT, InpEMA21,  0, MODE_EMA, PRICE_WEIGHTED);
   h_EMA36  = iMA(_Symbol, PERIOD_CURRENT, InpEMA36,  0, MODE_EMA, PRICE_WEIGHTED);
   h_EMA150 = iMA(_Symbol, PERIOD_CURRENT, InpEMA150, 0, MODE_EMA, PRICE_WEIGHTED);
   h_ADX    = iADXWilder(_Symbol, PERIOD_CURRENT, InpADX_Period);

   if(h_EMA21==INVALID_HANDLE || h_EMA36==INVALID_HANDLE ||
      h_EMA150==INVALID_HANDLE || h_ADX==INVALID_HANDLE)
     {
      Print("Erreur handles EMA/ADX : ", GetLastError());
      return INIT_FAILED;
     }

   // RSI — cree seulement si utilise
   if(InpUseRSI)
     {
      h_RSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
      if(h_RSI == INVALID_HANDLE)
        { Print("Erreur handle RSI : ", GetLastError()); return INIT_FAILED; }
     }

   // ATR — cree si utilise par ATR SL/TP OU par Breakeven/Trail
   if(InpUseATR || InpUseBreakeven || InpUseTrail)
     {
      h_ATR = iATR(_Symbol, PERIOD_CURRENT, InpATR_Period);
      if(h_ATR == INVALID_HANDLE)
        { Print("Erreur handle ATR : ", GetLastError()); return INIT_FAILED; }
     }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   if(!InpUseAsie && !InpUseLondres && !InpUseNY)
      Print("ATTENTION : Aucune session activee ! L EA ne prendra aucun trade.");

   Print("=====================================================");
   Print("EMA ADX Scalper EA v1.5 | ", _Symbol, " | ", EnumToString(Period()));
   Print("EMA200:", InpUseEMA200?"ON":"OFF",
         " | RSI:", InpUseRSI?"ON":"OFF",
         " | ATR:", InpUseATR?"ON":"OFF",
         " | BE:", InpUseBreakeven?"ON":"OFF",
         " | Trail:", InpUseTrail?"ON":"OFF");
   Print("Sessions: ",
         InpUseAsie    ? StringFormat("Asie(%02d-%02d) ",    InpAsie_Start,    InpAsie_End)    : "",
         InpUseLondres ? StringFormat("Londres(%02d-%02d) ", InpLondres_Start, InpLondres_End) : "",
         InpUseNY      ? StringFormat("NY(%02d-%02d)",       InpNY_Start,      InpNY_End)      : "");
   if(InpUseATR)
      Print("SL=ATR x", InpSL_ATR, " | TP=ATR x", InpTP_ATR);
   else
      Print("SL=", InpSL_Pips, "pips | TP=", InpTP_Pips, "pips");
   Print("=====================================================");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h_EMA21  != INVALID_HANDLE) IndicatorRelease(h_EMA21);
   if(h_EMA36  != INVALID_HANDLE) IndicatorRelease(h_EMA36);
   if(h_EMA150 != INVALID_HANDLE) IndicatorRelease(h_EMA150);
   if(h_ADX    != INVALID_HANDLE) IndicatorRelease(h_ADX);
   if(h_RSI    != INVALID_HANDLE) IndicatorRelease(h_RSI);
   if(h_ATR    != INVALID_HANDLE) IndicatorRelease(h_ATR);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //================================================================
   // COUCHE 3 — GESTION DES TRADES ACTIFS (a chaque tick)
   //================================================================
   if(InpUseBreakeven || InpUseTrail)
      GererTradesActifs();

   //================================================================
   // SIGNAUX D ENTREE — nouvelle barre seulement
   //================================================================
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;

   //================================================================
   // LECTURE INDICATEURS (barre fermee = index 1)
   //================================================================
   double ema21   = GetBuffer(h_EMA21, 0, 1);
   double ema36   = GetBuffer(h_EMA36, 0, 1);
   double ema150  = GetBuffer(h_EMA150, 0, 1);
   double adxCur  = GetBuffer(h_ADX, 0, 1);
   double dipCur  = GetBuffer(h_ADX, 1, 1);
   double dimCur  = GetBuffer(h_ADX, 2, 1);
   double adxPrev = GetBuffer(h_ADX, 0, 2);
   double dipPrev = GetBuffer(h_ADX, 1, 2);
   double dimPrev = GetBuffer(h_ADX, 2, 2);

   if(adxCur <= 0 || ema21 <= 0) return;

   //================================================================
   // MACHINE A ETATS ADX
   //================================================================
   if(adxCur <= InpADX_Under)
      g_adxState = 1;
   else if(g_adxState == 1 && adxCur > InpADX_Confirm)
      g_adxState = 2;
   else if(g_adxState == 2 && adxCur <= InpADX_Under)
      g_adxState = 1;

   if(g_adxState != 2) return;

   //================================================================
   // FILTRE SESSIONS GMT+2
   //================================================================
   if(InpUseAsie || InpUseLondres || InpUseNY)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int h = dt.hour;
      bool inAsie    = InpUseAsie    && (h >= InpAsie_Start    && h < InpAsie_End);
      bool inLondres = InpUseLondres && (h >= InpLondres_Start  && h < InpLondres_End);
      bool inNY      = InpUseNY      && (h >= InpNY_Start       && h < InpNY_End);
      if(!inAsie && !inLondres && !inNY) return;
     }

   //================================================================
   // COOLDOWN
   //================================================================
   datetime barTime = iTime(_Symbol, PERIOD_CURRENT, 1);
   int periodSec    = PeriodSeconds(PERIOD_CURRENT);
   if((int)((barTime - g_lastTime) / periodSec) < InpCooldown) return;

   //================================================================
   // POSITION EXISTANTE
   //================================================================
   if(InpOneTradeOnly && PositionsTotal() > 0)
     {
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
   // InpUseEMA200=true  → EMA20 > EMA46 > EMA200
   // InpUseEMA200=false → EMA20 > EMA46 seulement
   //================================================================
   bool emaBull, emaBear;
   if(InpUseEMA200)
     {
      emaBull = (ema21 > ema36 && ema36 > ema150);
      emaBear = (ema150 > ema36 && ema36 > ema21);
     }
   else
     {
      emaBull = (ema21 > ema36);
      emaBear = (ema36 > ema21);
     }
   if(!emaBull && !emaBear) return;

   //================================================================
   // ADX EN HAUSSE
   //================================================================
   if(adxCur <= adxPrev) return;

   //================================================================
   // CROISEMENT DI
   //================================================================
   bool crossBuy  = emaBull && (adxCur > dimCur) && (adxPrev <= dimPrev);
   bool crossSell = emaBear && (adxCur > dipCur) && (adxPrev <= dipPrev);
   if(!crossBuy && !crossSell) return;

   //================================================================
   // COUCHE 1 — FILTRE RSI
   // BUY  : RSI entre InpRSI_BuyMin  et InpRSI_BuyMax  (ex: 50-70)
   // SELL : RSI entre InpRSI_SellMin et InpRSI_SellMax (ex: 30-50)
   //================================================================
   double rsiVal = 0;
   if(InpUseRSI)
     {
      rsiVal = GetBuffer(h_RSI, 0, 1);
      if(rsiVal <= 0) return;

      if(crossBuy && (rsiVal < InpRSI_BuyMin || rsiVal > InpRSI_BuyMax))
        {
         Print(StringFormat("[RSI BLOQUE BUY]  RSI=%.1f hors [%.0f-%.0f]",
               rsiVal, InpRSI_BuyMin, InpRSI_BuyMax));
         return;
        }
      if(crossSell && (rsiVal < InpRSI_SellMin || rsiVal > InpRSI_SellMax))
        {
         Print(StringFormat("[RSI BLOQUE SELL] RSI=%.1f hors [%.0f-%.0f]",
               rsiVal, InpRSI_SellMin, InpRSI_SellMax));
         return;
        }
     }

   //================================================================
   // COUCHE 2 — CALCUL SL / TP
   // InpUseATR=true  → SL = ATR x InpSL_ATR  /  TP = ATR x InpTP_ATR
   // InpUseATR=false → SL/TP fixes en pips (1 pip = 0.01$)
   //================================================================
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl_dist, tp_dist;
   double atrVal = 0;

   if(InpUseATR || InpUseBreakeven || InpUseTrail)
      atrVal = GetBuffer(h_ATR, 0, 1);

   if(InpUseATR)
     {
      if(atrVal <= 0) return;
      sl_dist = NormalizeDouble(atrVal * InpSL_ATR, _Digits);
      tp_dist = NormalizeDouble(atrVal * InpTP_ATR, _Digits);
     }
   else
     {
      double pip_size = 0.01; // 1 pip = 0.01$ sur XAUUSDm et XAUUSD
      sl_dist = NormalizeDouble(InpSL_Pips * pip_size, _Digits);
      tp_dist = NormalizeDouble(InpTP_Pips * pip_size, _Digits);
     }

   //================================================================
   // EXECUTION
   //================================================================
   if(crossBuy)
     {
      double sl = NormalizeDouble(ask - sl_dist, _Digits);
      double tp = NormalizeDouble(ask + tp_dist, _Digits);
      if(trade.Buy(InpLotSize, _Symbol, ask, sl, tp, "EMA_ADX_BUY"))
        {
         g_adxState = 0;
         g_lastTime = barTime;
         Print(StringFormat(
               "[BUY]  Prix:%.3f | SL:%.3f (-%.3f$) | TP:%.3f (+%.3f$)"
               " | ADX:%.1f | RSI:%.1f | ATR:%.3f | EMA200:%s | BE:%s | Trail:%s",
               ask, sl, sl_dist, tp, tp_dist, adxCur, rsiVal, atrVal,
               InpUseEMA200?"ON":"OFF",
               InpUseBreakeven?"ON":"OFF",
               InpUseTrail?"ON":"OFF"));
        }
      else
         Print("Erreur BUY : ", trade.ResultRetcodeDescription());
     }
   else if(crossSell)
     {
      double sl = NormalizeDouble(bid + sl_dist, _Digits);
      double tp = NormalizeDouble(bid - tp_dist, _Digits);
      if(trade.Sell(InpLotSize, _Symbol, bid, sl, tp, "EMA_ADX_SELL"))
        {
         g_adxState = 0;
         g_lastTime = barTime;
         Print(StringFormat(
               "[SELL] Prix:%.3f | SL:%.3f (+%.3f$) | TP:%.3f (-%.3f$)"
               " | ADX:%.1f | RSI:%.1f | ATR:%.3f | EMA200:%s | BE:%s | Trail:%s",
               bid, sl, sl_dist, tp, tp_dist, adxCur, rsiVal, atrVal,
               InpUseEMA200?"ON":"OFF",
               InpUseBreakeven?"ON":"OFF",
               InpUseTrail?"ON":"OFF"));
        }
      else
         Print("Erreur SELL : ", trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//  COUCHE 3 — GESTION DES TRADES ACTIFS
//  Breakeven et Trailing Stop bases sur l ATR
//  Appele a chaque tick pour reagir rapidement
//+------------------------------------------------------------------+
void GererTradesActifs()
  {
   if(h_ATR == INVALID_HANDLE) return;
   double atr = GetBuffer(h_ATR, 0, 1);
   if(atr <= 0) return;

   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)  continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double curBid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double curAsk    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      ENUM_POSITION_TYPE posType =
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Distance de profit actuelle en prix
      double profit_dist = (posType == POSITION_TYPE_BUY)
                           ? curBid - openPrice
                           : openPrice - curAsk;

      double newSL = currentSL;

      //------------------------------------------------------------
      // BREAKEVEN
      // Declenche quand profit >= InpBE_ATR x ATR
      // SL deplace au prix d entree + buffer en points
      //------------------------------------------------------------
      if(InpUseBreakeven)
        {
         double be_trigger = atr * InpBE_ATR;
         double buf        = InpBE_Buffer * _Point;

         if(posType == POSITION_TYPE_BUY)
           {
            double be_sl = NormalizeDouble(openPrice + buf, _Digits);
            if(profit_dist >= be_trigger && currentSL < be_sl)
              {
               newSL = be_sl;
               Print(StringFormat("[BE BUY]  #%d SL:%.3f → BE:%.3f | profit:%.3f >= trigger:%.3f",
                     ticket, currentSL, newSL, profit_dist, be_trigger));
              }
           }
         else
           {
            double be_sl = NormalizeDouble(openPrice - buf, _Digits);
            if(profit_dist >= be_trigger && (currentSL > be_sl || currentSL == 0))
              {
               newSL = be_sl;
               Print(StringFormat("[BE SELL] #%d SL:%.3f → BE:%.3f | profit:%.3f >= trigger:%.3f",
                     ticket, currentSL, newSL, profit_dist, be_trigger));
              }
           }
        }

      //------------------------------------------------------------
      // TRAILING STOP ATR
      // Demarre quand profit >= InpTrailStart x ATR
      // Trail le SL a InpTrail_ATR x ATR derriere le prix courant
      // Ne recule jamais (ne deplace le SL que dans la bonne direction)
      //------------------------------------------------------------
      if(InpUseTrail)
        {
         double trail_trigger = atr * InpTrailStart;
         double trail_dist    = NormalizeDouble(atr * InpTrail_ATR, _Digits);

         if(posType == POSITION_TYPE_BUY)
           {
            double trail_sl = NormalizeDouble(curBid - trail_dist, _Digits);
            // Seulement si profit suffisant ET nouveau SL plus haut que l actuel
            if(profit_dist >= trail_trigger && trail_sl > newSL)
               newSL = trail_sl;
           }
         else
           {
            double trail_sl = NormalizeDouble(curAsk + trail_dist, _Digits);
            // Seulement si profit suffisant ET nouveau SL plus bas que l actuel
            if(profit_dist >= trail_trigger && (trail_sl < newSL || newSL == 0))
               newSL = trail_sl;
           }
        }

      //------------------------------------------------------------
      // APPLIQUER LE NOUVEAU SL si different de l actuel
      //------------------------------------------------------------
      if(MathAbs(newSL - currentSL) > _Point)
        {
         if(trade.PositionModify(ticket, newSL, currentTP))
            Print(StringFormat("[TRAIL] #%d SL:%.3f → %.3f | profit:%.3f$ | ATR:%.3f",
                  ticket, currentSL, newSL, profit_dist, atr));
         else
            Print(StringFormat("[TRAIL ERR] #%d | %s", ticket,
                  trade.ResultRetcodeDescription()));
        }
     }
  }

//+------------------------------------------------------------------+
//  LECTURE SECURISEE D UN BUFFER INDICATEUR
//+------------------------------------------------------------------+
double GetBuffer(int handle, int buffer, int shift)
  {
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) <= 0)
     {
      Print("GetBuffer erreur handle=", handle,
            " buf=", buffer, " shift=", shift,
            " err=", GetLastError());
      return 0;
     }
   return arr[0];
  }

//+------------------------------------------------------------------+
//  FIN — EMA_ADX_Scalper_EA v1.5
//+------------------------------------------------------------------+
