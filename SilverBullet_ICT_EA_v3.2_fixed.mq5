//+------------------------------------------------------------------+
//|                    Silver Bullet ICT EA v3.2                     |
//|                     XAUUSD M5 - Exness GMT+2                     |
//|  Top-Down MTF | EMA ou Structure ICT pure | Windows | Jours     |
//+------------------------------------------------------------------+
#property copyright   "ICT Strategy EA"
#property version     "3.20"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//+------------------------------------------------------------------+
//|                     INPUT PARAMETERS                             |
//+------------------------------------------------------------------+

input group "+==================================+"
input group "|    SILVER BULLET ICT v3.2        |"
input group "|  Top-Down MTF | EMA | Structure  |"
input group "+==================================+"
input int      MagicNumber = 20240101;

//--------------------------------------------------------------------
// CHOIX DE METHODE GLOBALE POUR LE BIAIS
// EMA    = croisement d'EMAs configurables par TF
// STRUCT = structure ICT pure (HH/HL/LH/LL + BOS/CHoCH)
//--------------------------------------------------------------------
input group "=== METHODE BIAIS : EMA ou STRUCTURE ICT ==="
input bool   UseBiasEMA   = true;
// true  > Methode EMA   (EMAs configurables par TF)
// false > Methode ICT   (HH/HL/LH/LL + BOS/CHoCH pur)

//====================================================================
// NIVEAU 1 - MACRO FILTER
//====================================================================
input group "=== NIVEAU 1 : MACRO FILTER ==="
input bool             UseMacroFilter    = true;
input ENUM_TIMEFRAMES  MacroTF           = PERIOD_D1;
// Choix : PERIOD_H8 | PERIOD_D1

// -- Si UseBiasEMA = true -----------------------------------------
input int   Macro_EMA1_Period  = 50;   // EMA principale Macro
input int   Macro_EMA2_Period  = 200;  // EMA secondaire Macro (0 = desactive)
// Logique EMA Macro :
//   EMA1 seule  : Prix > EMA1 > Bull | Prix < EMA1 > Bear
//   EMA1 + EMA2 : EMA1 > EMA2 > Bull | EMA1 < EMA2 > Bear

// -- Si UseBiasEMA = false (Structure ICT) ------------------------
input int   Macro_Struct_LB    = 5;    // Lookback swings Macro (bougies)
// Logique Structure :
//   HH + HL = Bullish | LH + LL = Bearish

//====================================================================
// NIVEAU 2 - BIAIS PRINCIPAL
//====================================================================
input group "=== NIVEAU 2 : BIAIS PRINCIPAL ==="
input ENUM_TIMEFRAMES  BiaisTF           = PERIOD_H4;
// Choix : PERIOD_H1 | PERIOD_H4

// -- Si UseBiasEMA = true -----------------------------------------
input int   Biais_EMA1_Period  = 20;   // EMA rapide Biais
input int   Biais_EMA2_Period  = 50;   // EMA lente  Biais
// Logique EMA Biais :
//   EMA1 > EMA2 + BOS confirme > Bull fort  (retourne 1.0)
//   EMA1 > EMA2 sans BOS       > Bull faible (retourne 0.5)
//   EMA1 < EMA2 + BOS confirme > Bear fort  (retourne -1.0)
//   EMA1 < EMA2 sans BOS       > Bear faible (retourne -0.5)

// -- Si UseBiasEMA = false (Structure ICT) ------------------------
input int   Biais_Struct_LB    = 10;   // Lookback swings Biais
// Logique Structure :
//   BOS Bullish  = cloture > dernier swing high > Bull (1.0)
//   BOS Bearish  = cloture < dernier swing low  > Bear (-1.0)
//   CHoCH = inversion de structure confirmee

//====================================================================
// NIVEAU 3 - CONFIRMATION STRUCTURE
//====================================================================
input group "=== NIVEAU 3 : CONFIRMATION STRUCTURE ==="
input bool             UseConfirmFilter  = true;
input ENUM_TIMEFRAMES  ConfirmTF         = PERIOD_M15;
// Choix : PERIOD_M10 | PERIOD_M15

// -- Si UseBiasEMA = true -----------------------------------------
input int   Confirm_EMA1_Period = 9;   // EMA rapide Confirmation
input int   Confirm_EMA2_Period = 21;  // EMA lente  Confirmation
// Logique : EMA9 > EMA21 = confirm bull | EMA9 < EMA21 = confirm bear
// + CHoCH sur ce TF pour double confirmation

// -- Si UseBiasEMA = false (Structure ICT) ------------------------
input int   Confirm_Struct_LB   = 15;  // Lookback CHoCH Confirmation
// Logique Structure pure : CHoCH M15/M10

//====================================================================
// NIVEAU 4 - ENTREE M5 (fixe)
//====================================================================
input group "=== NIVEAU 4 : ENTREE M5 (fixe) ==="
input int    Entry_CHoCH_LB    = 10;
input int    Entry_FVG_LB      = 20;
input double FVG_MinPts        = 5.0;
input bool   FVG_Fresh         = true;

//--------------------------------------------------------------------
// METHODE 1 - SL/TP EN POINTS
// XAUUSDm : 1000 points = 10$ pour 0.01 lot
//--------------------------------------------------------------------
input group "=== METHODE 1 : SL/TP FIXE EN POINTS ==="
input bool   M1_Active       = true;
input int    M1_SL_Points    = 200;   // 200 pts = 2.00$ /0.01lot
input int    M1_TP_Points    = 600;   // 600 pts = 6.00$ /0.01lot

//--------------------------------------------------------------------
// METHODE 2 - SL/TP PAR ATR (actif uniquement si M1 = false)
//--------------------------------------------------------------------
input group "=== METHODE 2 : SL/TP PAR ATR (si M1 OFF) ==="
input bool             M2_Active        = true;
input int              M2_ATR_Period    = 14;
input ENUM_TIMEFRAMES  M2_ATR_TF        = PERIOD_M5;
input double           M2_SL_Mult       = 1.5;
input double           M2_TP_Mult       = 3.0;

//--------------------------------------------------------------------
// METHODE 3 - BREAK EVEN
//--------------------------------------------------------------------
input group "=== METHODE 3 : BREAK EVEN ==="
input bool   M3_Active           = true;
input bool   M3_UseRR            = true;  // true=RR | false=points
input double M3_RR_Trigger       = 1.0;
input int    M3_Points_Trigger   = 200;
input int    M3_Lock_Points      = 5;

//--------------------------------------------------------------------
// METHODE 4 - TRAILING STOP
//--------------------------------------------------------------------
input group "=== METHODE 4 : TRAILING STOP ==="
input bool   M4_Active              = true;
input bool   M4_UseRR               = true;  // true=RR | false=points
input double M4_RR_Activation       = 1.5;
input int    M4_Points_Activation   = 300;
input int    M4_Trail_Distance      = 150;
input int    M4_Trail_Step          = 50;

//--------------------------------------------------------------------
// RISK MANAGEMENT
//--------------------------------------------------------------------
input group "=== RISK MANAGEMENT ==="
input double RiskPercent     = 0.5;
input double MaxLot          = 5.0;
input int    MaxDailyTrades  = 2;
input int    MaxSpread       = 30;

//--------------------------------------------------------------------
// SILVER BULLET WINDOWS - Chaque fenetre activable/desactivable
// Horaires en GMT+2 (Exness) - format HHMM
// GMT+2 = GMT + 2h
// Ex: NY 03:00 GMT = 10:00 GMT+2 > W1_Start=1000
//--------------------------------------------------------------------
input group "=== WINDOW 1 : NY 03:00 (GMT 08:00) ==="
input bool   UseWindow1   = true;    // Activer Window 1
input int    W1_Start     = 1000;    // Debut  W1 GMT+2 (defaut 10:00)
input int    W1_End       = 1100;    // Fin    W1 GMT+2 (defaut 11:00)

input group "=== WINDOW 2 : NY 10:00 (GMT 15:00) ==="
input bool   UseWindow2   = true;    // Activer Window 2
input int    W2_Start     = 1700;    // Debut  W2 GMT+2 (defaut 17:00)
input int    W2_End       = 1800;    // Fin    W2 GMT+2 (defaut 18:00)

input group "=== WINDOW 3 : NY 14:00 (GMT 19:00) ==="
input bool   UseWindow3   = false;   // Activer Window 3
input int    W3_Start     = 2100;    // Debut  W3 GMT+2 (defaut 21:00)
input int    W3_End       = 2200;    // Fin    W3 GMT+2 (defaut 22:00)

input group "=== FILTRE JOURS DE TRADING ==="
input bool   TradeLundi    = true;   // Trader le Lundi
input bool   TradeMardi    = true;   // Trader le Mardi
input bool   TradeMercredi = true;   // Trader le Mercredi
input bool   TradeJeudi    = true;   // Trader le Jeudi
input bool   TradeVendredi = false;  // Trader le Vendredi (deconseille)
input int    VendrediStop  = 1600;   // Heure stop vendredi GMT+2 (defaut 16:00)

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+

struct FVG_Data {
   double   high, low;
   bool     isBullish, isFilled;
   datetime time;
};

struct TradeTrack {
   ulong  ticket;
   bool   BE_Done;
   bool   Trail_Active;
   double Trail_LastSL;
};

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                               |
//+------------------------------------------------------------------+

FVG_Data   g_FVG;
bool       g_HasFVG       = false;
bool       g_CHoCH_Bull   = false;
bool       g_CHoCH_Bear   = false;

// Resultats Top-Down
double     g_MacroBias    = 0;    //  1=bull | -1=bear | 0=neutre
double     g_MainBias     = 0;    //  1=bull | -1=bear | 0=neutre
bool       g_ConfirmBull  = false;
bool       g_ConfirmBear  = false;

int        g_DailyTrades  = 0;
datetime   g_LastDay      = 0;
datetime   g_LastBarTime  = 0;
int        g_ATR_Handle   = INVALID_HANDLE;

TradeTrack g_Trades[10];
int        g_TradesCount  = 0;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Period != PERIOD_M5) {
      Alert("[ERR] Veuillez placer l'EA sur le timeframe M5 !");
      return INIT_FAILED;
   }

   // Verifier les timeframes choisis
   if(BiaisTF != PERIOD_H1 && BiaisTF != PERIOD_H4) {
      Print("[WARN] BiaisTF recommande : H1 ou H4");
   }
   if(ConfirmTF != PERIOD_M10 && ConfirmTF != PERIOD_M15) {
      Print("[WARN] ConfirmTF recommande : M10 ou M15");
   }
   if(MacroTF != PERIOD_H8 && MacroTF != PERIOD_D1) {
      Print("[WARN] MacroTF recommande : H8 ou D1");
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   g_ATR_Handle = iATR(_Symbol, M2_ATR_TF, M2_ATR_Period);
   if(g_ATR_Handle == INVALID_HANDLE) {
      Print("[ERR] Impossible de creer l'indicateur ATR");
      return INIT_FAILED;
   }

   PrintConfig();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_ATR_Handle != INVALID_HANDLE)
      IndicatorRelease(g_ATR_Handle);
   Comment("");
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ManageOpenTrades();
   UpdateComment();

   datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
   if(barTime == g_LastBarTime) return;
   g_LastBarTime = barTime;

   ResetDailyCounter();

   if(!IsSilverBulletWindow())        return;
   if(g_DailyTrades >= MaxDailyTrades) return;
   if(HasOpenPosition())               return;
   if(IsSpreadTooHigh())               return;

   // ==============================================================-
   // TOP-DOWN ANALYSIS CASCADE
   // ==============================================================-

   // Niveau 1 : Macro (H8 ou D1)
   if(UseMacroFilter) {
      g_MacroBias = GetMacroBias();
      if(g_MacroBias == 0) {
         Print("[--] Macro neutre > pas de trade");
         return;
      }
   }

   // Niveau 2 : Biais principal (H1 ou H4)
   g_MainBias = GetMainBias();
   if(g_MainBias == 0) {
      Print("[--] Biais principal neutre > pas de trade");
      return;
   }

   // Verifier alignement Macro + Biais
   if(UseMacroFilter && g_MacroBias != 0 && g_MacroBias != g_MainBias) {
      Print(StringFormat("[WARN] Conflit Macro(%s) vs Biais(%s) > pas de trade",
            g_MacroBias > 0 ? "Bull" : "Bear",
            g_MainBias  > 0 ? "Bull" : "Bear"));
      return;
   }

   // Niveau 3 : Confirmation structure (M15 ou M10)
   if(UseConfirmFilter) {
      g_ConfirmBull = GetConfirmCHoCH(true);
      g_ConfirmBear = GetConfirmCHoCH(false);
   } else {
      // Si filtre desactive > laisser passer
      g_ConfirmBull = (g_MainBias > 0);
      g_ConfirmBear = (g_MainBias < 0);
   }

   // Niveau 4 : Entree M5 (CHoCH + FVG)
   g_CHoCH_Bull = DetectCHoCH_M5(true);
   g_CHoCH_Bear = DetectCHoCH_M5(false);
   g_HasFVG     = DetectFVG();

   // Verifier la cascade complete avant entree
   if(g_HasFVG) CheckEntry();
}

//+------------------------------------------------------------------+
//| ==============================================================  |
//|   METHODES BIAIS - EMA ou STRUCTURE ICT selon UseBiasEMA       |
//| ==============================================================  |
//+------------------------------------------------------------------+

//--------------------------------------------------------------------
// OUTIL : Lire une EMA sur un TF donne
//--------------------------------------------------------------------
double GetEMA(ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   int h = iMA(_Symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return 0;
   double buf[]; ArraySetAsSeries(buf, true);
   bool ok = (CopyBuffer(h, 0, shift, 1, buf) >= 1);
   IndicatorRelease(h);
   return ok ? buf[0] : 0;
}

//--------------------------------------------------------------------
// OUTIL : Detecter swing High / Low sur un TF
//--------------------------------------------------------------------
double GetSwingHigh(ENUM_TIMEFRAMES tf, int lookback, int startBar = 2)
{
   int bar = iHighest(_Symbol, tf, MODE_HIGH, lookback, startBar);
   return (bar >= 0) ? iHigh(_Symbol, tf, bar) : 0;
}
double GetSwingLow(ENUM_TIMEFRAMES tf, int lookback, int startBar = 2)
{
   int bar = iLowest(_Symbol, tf, MODE_LOW, lookback, startBar);
   return (bar >= 0) ? iLow(_Symbol, tf, bar) : 0;
}

//--------------------------------------------------------------------
// OUTIL : Detecter la structure ICT (HH/HL ou LH/LL)
// Retourne :  1.0 = Bullish structure
//            -1.0 = Bearish structure
//             0.0 = Indefini
//--------------------------------------------------------------------
double GetICTStructure(ENUM_TIMEFRAMES tf, int lb)
{
   // On analyse les 3 derniers swings
   double h1 = GetSwingHigh(tf, lb, 2);
   double h2 = GetSwingHigh(tf, lb, lb / 2 + 2);
   double l1 = GetSwingLow (tf, lb, 2);
   double l2 = GetSwingLow (tf, lb, lb / 2 + 2);

   bool higherHigh = (h1 > h2 && h2 > 0);
   bool higherLow  = (l1 > l2 && l2 > 0);
   bool lowerHigh  = (h1 < h2 && h2 > 0);
   bool lowerLow   = (l1 < l2 && l2 > 0);

   // Bullish : HH + HL
   if(higherHigh && higherLow)  return  1.0;
   // Bearish : LH + LL
   if(lowerHigh  && lowerLow)   return -1.0;
   // Transition bullish : HL seulement (CHoCH potentiel)
   if(higherLow  && !higherHigh) return  0.5;
   // Transition bearish : LH seulement
   if(lowerHigh  && !lowerLow)   return -0.5;

   return 0;
}

//--------------------------------------------------------------------
// NIVEAU 1 - BIAIS MACRO (H8 ou D1)
//--------------------------------------------------------------------
double GetMacroBias()
{
   if(UseBiasEMA)
   {
      // --- Methode EMA -------------------------------------------
      double ema1 = GetEMA(MacroTF, Macro_EMA1_Period);
      if(ema1 == 0) return 0;

      // Si EMA2 activee : croisement EMA1/EMA2
      if(Macro_EMA2_Period > 0 && Macro_EMA2_Period != Macro_EMA1_Period)
      {
         double ema2 = GetEMA(MacroTF, Macro_EMA2_Period);
         if(ema2 == 0) return 0;
         if(ema1 > ema2 * 1.0001) return  1.0;
         if(ema1 < ema2 * 0.9999) return -1.0;
         return 0;
      }
      // Si EMA1 seule : prix vs EMA
      else
      {
         double closeM = iClose(_Symbol, MacroTF, 1);
         if(closeM > ema1 * 1.0001) return  1.0;
         if(closeM < ema1 * 0.9999) return -1.0;
         return 0;
      }
   }
   else
   {
      // --- Methode Structure ICT pure ----------------------------
      double str = GetICTStructure(MacroTF, Macro_Struct_LB);
      // BOS confirmation
      double swHigh = GetSwingHigh(MacroTF, Macro_Struct_LB);
      double swLow  = GetSwingLow (MacroTF, Macro_Struct_LB);
      double close1 = iClose(_Symbol, MacroTF, 1);

      if(str >= 0.5 && close1 > swHigh) return  1.0;  // BOS Bull confirme
      if(str <= -0.5 && close1 < swLow) return -1.0;  // BOS Bear confirme
      if(str >= 0.5)  return  0.5;  // Structure bull sans BOS
      if(str <= -0.5) return -0.5;  // Structure bear sans BOS
      return 0;
   }
}

//--------------------------------------------------------------------
// NIVEAU 2 - BIAIS PRINCIPAL (H1 ou H4)
//--------------------------------------------------------------------
double GetMainBias()
{
   if(UseBiasEMA)
   {
      // --- Methode EMA -------------------------------------------
      double ema1 = GetEMA(BiaisTF, Biais_EMA1_Period);
      double ema2 = GetEMA(BiaisTF, Biais_EMA2_Period);
      if(ema1 == 0 || ema2 == 0) return 0;

      bool emaBull = (ema1 > ema2);
      bool emaBear = (ema1 < ema2);

      // Confirmation BOS sur ce TF
      bool bosBull = DetectBOS_HTF(true,  BiaisTF);
      bool bosBear = DetectBOS_HTF(false, BiaisTF);

      if(emaBull && bosBull) return  1.0;   // EMA + BOS alignes bull
      if(emaBear && bosBear) return -1.0;   // EMA + BOS alignes bear
      if(emaBull)            return  0.5;   // EMA bull sans BOS
      if(emaBear)            return -0.5;   // EMA bear sans BOS
      return 0;
   }
   else
   {
      // --- Methode Structure ICT pure ----------------------------
      double str    = GetICTStructure(BiaisTF, Biais_Struct_LB);
      double swHigh = GetSwingHigh(BiaisTF, Biais_Struct_LB);
      double swLow  = GetSwingLow (BiaisTF, Biais_Struct_LB);
      double close1 = iClose(_Symbol, BiaisTF, 1);

      // BOS = cassure confirmee = signal fort
      if(str >= 0.5 && close1 > swHigh) return  1.0;
      if(str <= -0.5 && close1 < swLow) return -1.0;
      // Structure sans BOS = signal faible
      if(str >= 0.5)  return  0.5;
      if(str <= -0.5) return -0.5;
      return 0;
   }
}

//--------------------------------------------------------------------
// NIVEAU 3 - CONFIRMATION (M15 ou M10)
//--------------------------------------------------------------------
bool GetConfirmCHoCH(bool bullish)
{
   if(UseBiasEMA)
   {
      // --- Methode EMA -------------------------------------------
      double ema1 = GetEMA(ConfirmTF, Confirm_EMA1_Period);
      double ema2 = GetEMA(ConfirmTF, Confirm_EMA2_Period);
      if(ema1 == 0 || ema2 == 0) return false;

      bool emaOK = bullish ? (ema1 > ema2) : (ema1 < ema2);
      if(!emaOK) return false;

      // Double confirmation : EMA + CHoCH structure sur ce TF
      return GetConfirmStructure(bullish);
   }
   else
   {
      // --- Methode Structure ICT pure ----------------------------
      return GetConfirmStructure(bullish);
   }
}

// Detection CHoCH structure sur ConfirmTF (utilisee par les deux methodes)
bool GetConfirmStructure(bool bullish)
{
   int lb = Confirm_Struct_LB;

   if(bullish)
   {
      int lowestBar  = iLowest (_Symbol, ConfirmTF, MODE_LOW,  lb, 2);
      int highestBar = iHighest(_Symbol, ConfirmTF, MODE_HIGH, lb, 2);
      if(lowestBar < 0 || highestBar < 0) return false;

      double swHigh = iHigh (_Symbol, ConfirmTF, highestBar);
      double lastLL = iLow  (_Symbol, ConfirmTF, lowestBar);
      double close1 = iClose(_Symbol, ConfirmTF, 1);
      double low1   = iLow  (_Symbol, ConfirmTF, 1);

      if(close1 > swHigh && low1 <= lastLL * 1.002) return true;
      double prevH2 = iHigh(_Symbol, ConfirmTF, 2);
      if(close1 > prevH2) return true;
   }
   else
   {
      int highestBar = iHighest(_Symbol, ConfirmTF, MODE_HIGH, lb, 2);
      int lowestBar  = iLowest (_Symbol, ConfirmTF, MODE_LOW,  lb, 2);
      if(highestBar < 0 || lowestBar < 0) return false;

      double swLow  = iLow  (_Symbol, ConfirmTF, lowestBar);
      double lastHH = iHigh (_Symbol, ConfirmTF, highestBar);
      double close1 = iClose(_Symbol, ConfirmTF, 1);
      double high1  = iHigh (_Symbol, ConfirmTF, 1);

      if(close1 < swLow && high1 >= lastHH * 0.998) return true;
      double prevL2 = iLow(_Symbol, ConfirmTF, 2);
      if(close1 < prevL2) return true;
   }
   return false;
}

//--------------------------------------------------------------------
// OUTIL : Detection BOS sur TF superieur
//--------------------------------------------------------------------
bool DetectBOS_HTF(bool bullish, ENUM_TIMEFRAMES tf)
{
   int lb = 10;
   if(bullish) {
      int bar = iHighest(_Symbol, tf, MODE_HIGH, lb, 2);
      return (iClose(_Symbol, tf, 1) > iHigh(_Symbol, tf, bar));
   } else {
      int bar = iLowest(_Symbol, tf, MODE_LOW, lb, 2);
      return (iClose(_Symbol, tf, 1) < iLow(_Symbol, tf, bar));
   }
}

//+------------------------------------------------------------------+
//| NIVEAU 4 - CHoCH M5 (Entree)                                   |
//+------------------------------------------------------------------+
bool DetectCHoCH_M5(bool bullish)
{
   int lb = Entry_CHoCH_LB;

   if(bullish)
   {
      int lowestBar  = iLowest (_Symbol, PERIOD_M5, MODE_LOW,  lb, 2);
      int highestBar = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, lb, 2);
      if(lowestBar < 0 || highestBar < 0) return false;

      double swHigh  = iHigh (_Symbol, PERIOD_M5, highestBar);
      double lastLL  = iLow  (_Symbol, PERIOD_M5, lowestBar);
      double close1  = iClose(_Symbol, PERIOD_M5, 1);
      double low1    = iLow  (_Symbol, PERIOD_M5, 1);

      if(close1 > swHigh && low1 <= lastLL * 1.001) return true;

      double prevH2 = iHigh(_Symbol, PERIOD_M5, 2);
      double prevL3 = iLow (_Symbol, PERIOD_M5, 3);
      double prevL1 = iLow (_Symbol, PERIOD_M5, 1);
      if(close1 > prevH2 && prevL3 < prevL1)        return true;
   }
   else
   {
      int highestBar = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, lb, 2);
      int lowestBar  = iLowest (_Symbol, PERIOD_M5, MODE_LOW,  lb, 2);
      if(highestBar < 0 || lowestBar < 0) return false;

      double swLow  = iLow  (_Symbol, PERIOD_M5, lowestBar);
      double lastHH = iHigh (_Symbol, PERIOD_M5, highestBar);
      double close1 = iClose(_Symbol, PERIOD_M5, 1);
      double high1  = iHigh (_Symbol, PERIOD_M5, 1);

      if(close1 < swLow && high1 >= lastHH * 0.999) return true;

      double prevL2 = iLow (_Symbol, PERIOD_M5, 2);
      double prevH3 = iHigh(_Symbol, PERIOD_M5, 3);
      double prevH1 = iHigh(_Symbol, PERIOD_M5, 1);
      if(close1 < prevL2 && prevH3 > prevH1)        return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| DETECTION FVG M5                                                |
//+------------------------------------------------------------------+
bool DetectFVG()
{
   g_HasFVG = false;

   for(int i = 1; i <= Entry_FVG_LB; i++)
   {
      double h1 = iHigh(_Symbol, PERIOD_M5, i + 2);
      double l1 = iLow (_Symbol, PERIOD_M5, i + 2);
      double h3 = iHigh(_Symbol, PERIOD_M5, i);
      double l3 = iLow (_Symbol, PERIOD_M5, i);

      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Bullish FVG
      if(l3 > h1 && (l3 - h1) / _Point >= FVG_MinPts)
      {
         if(FVG_Fresh) {
            bool filled = false;
            for(int j = i - 1; j >= 1; j--)
               if(iLow(_Symbol, PERIOD_M5, j) <= h1) { filled = true; break; }
            if(filled) continue;
         }
         if(ask >= h1 && ask <= l3) {
            g_FVG.isBullish = true;
            g_FVG.low = h1; g_FVG.high = l3;
            g_FVG.time = iTime(_Symbol, PERIOD_M5, i + 1);
            return true;
         }
      }

      // Bearish FVG
      if(h3 < l1 && (l1 - h3) / _Point >= FVG_MinPts)
      {
         if(FVG_Fresh) {
            bool filled = false;
            for(int j = i - 1; j >= 1; j--)
               if(iHigh(_Symbol, PERIOD_M5, j) >= l1) { filled = true; break; }
            if(filled) continue;
         }
         if(bid >= h3 && bid <= l1) {
            g_FVG.isBullish = false;
            g_FVG.low = h3; g_FVG.high = l1;
            g_FVG.time = iTime(_Symbol, PERIOD_M5, i + 1);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| VERIFIER ALIGNEMENT CASCADE ET ENTRER                          |
//+------------------------------------------------------------------+
void CheckEntry()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl, tp, slDist;

   // ==- VALIDATION CASCADE COMPLETE ==============================
   // BUY : tous les niveaux doivent etre bullish
   bool buyValid  = (g_MainBias > 0)
                  && g_ConfirmBull
                  && g_CHoCH_Bull
                  && g_FVG.isBullish;

   // SELL : tous les niveaux doivent etre bearish
   bool sellValid = (g_MainBias < 0)
                  && g_ConfirmBear
                  && g_CHoCH_Bear
                  && !g_FVG.isBullish;

   // Verifier coherence macro si active
   if(UseMacroFilter) {
      if(buyValid  && g_MacroBias < 0) buyValid  = false;
      if(sellValid && g_MacroBias > 0) sellValid = false;
   }

   // ==- BUY ======================================================
   if(buyValid && ask >= g_FVG.low && ask <= g_FVG.high)
   {
      if(!GetSLTP(true, ask, sl, tp, slDist)) return;
      double lot = CalcLotSize(slDist);
      if(lot <= 0) return;

      LogCascade("BUY");
      LogEntry("BUY", ask, sl, tp, lot, slDist);

      if(trade.Buy(lot, _Symbol, ask, sl, tp, "SB_ICT_BUY_v3"))
      {
         g_DailyTrades++;
         RegisterTrade(trade.ResultOrder());
         Print("[OK] BUY #", trade.ResultOrder());
      }
      else Print("[ERR] Erreur BUY : ", trade.ResultRetcodeDescription());
   }

   // ==- SELL ====================================================-
   if(sellValid && bid >= g_FVG.low && bid <= g_FVG.high)
   {
      if(!GetSLTP(false, bid, sl, tp, slDist)) return;
      double lot = CalcLotSize(slDist);
      if(lot <= 0) return;

      LogCascade("SELL");
      LogEntry("SELL", bid, sl, tp, lot, slDist);

      if(trade.Sell(lot, _Symbol, bid, sl, tp, "SB_ICT_SELL_v3"))
      {
         g_DailyTrades++;
         RegisterTrade(trade.ResultOrder());
         Print("[OK] SELL #", trade.ResultOrder());
      }
      else Print("[ERR] Erreur SELL : ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| CALCUL SL/TP                                                    |
//+------------------------------------------------------------------+
bool GetSLTP(bool isBuy, double entry,
             double &sl, double &tp, double &slDist)
{
   double sdist = 0, tdist = 0;

   if(M1_Active) {
      sdist = M1_SL_Points * _Point;
      tdist = M1_TP_Points * _Point;
   }
   else if(M2_Active) {
      double atr[]; ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_ATR_Handle, 0, 1, 1, atr) < 1) return false;
      sdist = atr[0] * M2_SL_Mult;
      tdist = atr[0] * M2_TP_Mult;
      Print(StringFormat("[INFO] ATR=%.5f SL=%.5f TP=%.5f", atr[0], sdist, tdist));
   }
   else { Print("[ERR] M1 et M2 desactives"); return false; }

   if(isBuy)  { sl = entry - sdist; tp = entry + tdist; }
   else       { sl = entry + sdist; tp = entry - tdist; }

   slDist = sdist;
   return true;
}

//+------------------------------------------------------------------+
//| CALCUL LOT                                                      |
//+------------------------------------------------------------------+
double CalcLotSize(double slDist)
{
   if(slDist <= 0) return 0;
   double riskAmt = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal == 0 || tickSz == 0) return 0;

   double ptVal   = tickVal * (_Point / tickSz);
   double lot     = riskAmt / ((slDist / _Point) * ptVal);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), MaxLot);

   lot = MathFloor(lot / step) * step;
   return MathMax(minLot, MathMin(maxLot, lot));
}

//+------------------------------------------------------------------+
//| GESTION DES TRADES (BE + Trail)                                |
//+------------------------------------------------------------------+
void ManageOpenTrades()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!posInfo.SelectByIndex(i))      continue;
      if(posInfo.Magic() != MagicNumber) continue;
      if(posInfo.Symbol() != _Symbol)    continue;

      ulong  ticket    = posInfo.Ticket();
      double openPrice = posInfo.PriceOpen();
      double curSL     = posInfo.StopLoss();
      double curTP     = posInfo.TakeProfit();
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      ENUM_POSITION_TYPE type = posInfo.PositionType();

      double slDist  = MathAbs(openPrice - curSL);
      if(slDist < _Point) continue;

      double curPrice   = (type == POSITION_TYPE_BUY) ? bid : ask;
      double profitPts  = (type == POSITION_TYPE_BUY)
                          ? (curPrice - openPrice) / _Point
                          : (openPrice - curPrice) / _Point;
      double slPts      = slDist / _Point;

      int trIdx = GetTradeTrackIndex(ticket);
      if(trIdx < 0) continue;

      // -- METHODE 3 : BREAK EVEN --------------------------------
      if(M3_Active && !g_Trades[trIdx].BE_Done)
      {
         bool trig = M3_UseRR
                     ? (profitPts >= slPts * M3_RR_Trigger)
                     : (profitPts >= M3_Points_Trigger);
         if(trig)
         {
            double newSL = (type == POSITION_TYPE_BUY)
                           ? openPrice + M3_Lock_Points * _Point
                           : openPrice - M3_Lock_Points * _Point;

            bool ok = (type == POSITION_TYPE_BUY  && newSL > curSL + _Point)
                   || (type == POSITION_TYPE_SELL && newSL < curSL - _Point);
            if(ok && trade.PositionModify(ticket, newSL, curTP))
            {
               g_Trades[trIdx].BE_Done = true;
               Print(StringFormat("BE active #%d > %.5f [%s]", ticket, newSL,
                     M3_UseRR ? StringFormat("RR%.1f", M3_RR_Trigger)
                              : StringFormat("%dpts", M3_Points_Trigger)));
            }
         }
      }

      // -- METHODE 4 : TRAILING STOP -----------------------------
      if(M4_Active)
      {
         if(!g_Trades[trIdx].Trail_Active)
         {
            bool activate = M4_UseRR
                            ? (profitPts >= slPts * M4_RR_Activation)
                            : (profitPts >= M4_Points_Activation);
            if(activate) {
               g_Trades[trIdx].Trail_Active = true;
               Print(StringFormat("Trail active #%d [%s]", ticket,
                     M4_UseRR ? StringFormat("RR%.1f", M4_RR_Activation)
                              : StringFormat("%dpts", M4_Points_Activation)));
            }
         }

         if(g_Trades[trIdx].Trail_Active)
         {
            double newSL = 0;
            bool   upd   = false;

            if(type == POSITION_TYPE_BUY) {
               newSL = bid - M4_Trail_Distance * _Point;
               upd   = (newSL > curSL + M4_Trail_Step * _Point && newSL > openPrice);
            } else {
               newSL = ask + M4_Trail_Distance * _Point;
               upd   = (newSL < curSL - M4_Trail_Step * _Point && newSL < openPrice);
            }

            if(upd && trade.PositionModify(ticket, newSL, curTP))
               Print(StringFormat("Trail SL #%d > %.5f", ticket, newSL));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| TRACKING TRADES                                                 |
//+------------------------------------------------------------------+
void RegisterTrade(ulong ticket)
{
   if(g_TradesCount >= 10) return;
   g_Trades[g_TradesCount].ticket       = ticket;
   g_Trades[g_TradesCount].BE_Done      = false;
   g_Trades[g_TradesCount].Trail_Active = false;
   g_Trades[g_TradesCount].Trail_LastSL = 0;
   g_TradesCount++;
}

// Retourne l'index dans g_Trades, -1 si non trouve
int GetTradeTrackIndex(ulong ticket)
{
   for(int i = 0; i < g_TradesCount; i++)
      if(g_Trades[i].ticket == ticket) return i;
   // Auto-enregistrement si nouveau ticket
   RegisterTrade(ticket);
   for(int i = 0; i < g_TradesCount; i++)
      if(g_Trades[i].ticket == ticket) return i;
   return -1;
}

void CleanClosedTrades()
{
   for(int i = g_TradesCount - 1; i >= 0; i--)
      if(!PositionSelectByTicket(g_Trades[i].ticket)) {
         for(int j = i; j < g_TradesCount - 1; j++)
            g_Trades[j] = g_Trades[j + 1];
         g_TradesCount--;
      }
}

//+------------------------------------------------------------------+
//| UTILITAIRES                                                     |
//+------------------------------------------------------------------+
// --- Verifier si le jour actuel est autorise ----------------------
bool IsTradingDayAllowed()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int t = dt.hour * 100 + dt.min;

   switch(dt.day_of_week)
   {
      case 1: return TradeLundi;
      case 2: return TradeMardi;
      case 3: return TradeMercredi;
      case 4: return TradeJeudi;
      case 5:
         // Vendredi : verifier l'heure limite
         if(!TradeVendredi) return false;
         return (t < VendrediStop);
      default: return false; // Samedi=6, Dimanche=0
   }
}

// --- Verifier si on est dans une fenetre Silver Bullet ------------
bool IsSilverBulletWindow()
{
   // Verifier d'abord si le jour est autorise
   if(!IsTradingDayAllowed()) return false;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int t = dt.hour * 100 + dt.min;

   bool w1 = UseWindow1 && (t >= W1_Start && t < W1_End);
   bool w2 = UseWindow2 && (t >= W2_Start && t < W2_End);
   bool w3 = UseWindow3 && (t >= W3_Start && t < W3_End);

   return (w1 || w2 || w3);
}

// --- Nom de la fenetre active -------------------------------------
string GetWindowName()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int t = dt.hour * 100 + dt.min;

   if(UseWindow1 && t >= W1_Start && t < W1_End)
      return StringFormat("W1 [%04d-%04d]", W1_Start, W1_End);
   if(UseWindow2 && t >= W2_Start && t < W2_End)
      return StringFormat("W2 [%04d-%04d]", W2_Start, W2_End);
   if(UseWindow3 && t >= W3_Start && t < W3_End)
      return StringFormat("W3 [%04d-%04d]", W3_Start, W3_End);
   return "Hors fenetre";
}

// --- Nom du jour actuel -------------------------------------------
string GetDayName()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string days[] = {"Dimanche","Lundi","Mardi","Mercredi","Jeudi","Vendredi","Samedi"};
   return days[dt.day_of_week];
}

// --- Prochain jour de trading -------------------------------------
string GetNextTradingDay()
{
   bool days[7] = {false,
                   TradeLundi,
                   TradeMardi,
                   TradeMercredi,
                   TradeJeudi,
                   TradeVendredi,
                   false};
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string dayNames[] = {"Dim","Lun","Mar","Mer","Jeu","Ven","Sam"};
   for(int i = 1; i <= 7; i++) {
      int next = (dt.day_of_week + i) % 7;
      if(days[next]) return dayNames[next];
   }
   return "?";
}

bool HasOpenPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == MagicNumber && posInfo.Symbol() == _Symbol)
            return true;
   return false;
}

bool IsSpreadTooHigh()
{ return (SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > MaxSpread); }

void ResetDailyCounter()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(
      StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));
   if(g_LastDay != today) {
      g_DailyTrades = 0; g_LastDay = today; CleanClosedTrades();
   }
}

string TFtoStr(ENUM_TIMEFRAMES tf)
{
   switch(tf) {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M10: return "M10";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_H8:  return "H8";
      case PERIOD_D1:  return "D1";
      default:         return "?";
   }
}

void LogCascade(string dir)
{
   Print("---------------------------------------");
   Print("-  CASCADE TOP-DOWN > SIGNAL " + dir + "       -");
   Print("---------------------------------------");
   Print(StringFormat("- Macro   (%s) : %s",
         TFtoStr(MacroTF),
         g_MacroBias > 0 ? " Bullish" : g_MacroBias < 0 ? " Bearish" : " OFF"));
   Print(StringFormat("- Biais   (%s) : %s",
         TFtoStr(BiaisTF),
         g_MainBias  > 0 ? " Bullish" : " Bearish"));
   Print(StringFormat("- Confirm (%s): %s",
         TFtoStr(ConfirmTF),
         dir == "BUY" ? (g_ConfirmBull  ? "ON"  : "OFF")
                      : (g_ConfirmBear  ? "ON"  : "OFF")));
   Print(StringFormat("- CHoCH   (M5) : %s",
         dir == "BUY" ? (g_CHoCH_Bull  ? "ON"  : "OFF")
                      : (g_CHoCH_Bear  ? "ON"  : "OFF")));
   Print(StringFormat("- FVG     (M5) : ON %.5f-%.5f",
         g_FVG.low, g_FVG.high));
   Print("---------------------------------------");
}

void LogEntry(string dir, double price, double sl, double tp,
              double lot, double slDist)
{
   string meth = M1_Active ? "Points" : "ATR";
   Print(StringFormat("[INFO] %s | %s | Prix:%.5f SL:%.5f TP:%.5f Lots:%.2f",
         dir, meth, price, sl, tp, lot));
   Print(StringFormat("   SL = %.0f points = %.2f$ par 0.01 lot",
         slDist/_Point, slDist/_Point * 0.01));
}

void PrintConfig()
{
   string macroTFs  = TFtoStr(MacroTF);
   string biaisTFs  = TFtoStr(BiaisTF);
   string confirmTFs= TFtoStr(ConfirmTF);
   Print("===========================================");
   Print("   Silver Bullet ICT EA v3.2              ");
   Print("   Top-Down MTF | Windows | Jours         ");
   Print("===========================================");
   Print(StringFormat("| W1 : %s  [%04d-%04d GMT+2]",
         UseWindow1  ? "ON"  : "OFF", W1_Start, W1_End));
   Print(StringFormat("| W2 : %s  [%04d-%04d GMT+2]",
         UseWindow2  ? "ON"  : "OFF", W2_Start, W2_End));
   Print(StringFormat("| W3 : %s  [%04d-%04d GMT+2]",
         UseWindow3  ? "ON"  : "OFF", W3_Start, W3_End));
   Print(StringFormat("| Jours : Lun:%s Mar:%s Mer:%s Jeu:%s Ven:%s",
         TradeLundi     ? "ON"  : "OFF",
         TradeMardi     ? "ON"  : "OFF",
         TradeMercredi  ? "ON"  : "OFF",
         TradeJeudi     ? "ON"  : "OFF",
         TradeVendredi ? StringFormat("ON(<%04d)", VendrediStop)  : "OFF"));
   Print("===========================================");
   Print(StringFormat("| L1 Macro    (%s)  : %s",
         macroTFs,   UseMacroFilter   ? "[OK] ACTIF" : "[ERR] OFF"));
   Print(StringFormat("|| L2 Biais    (%s)  : ON ACTIF  EMA%d/EMA%d",
         biaisTFs, Biais_EMA1_Period, Biais_EMA2_Period));
   Print(StringFormat("| L3 Confirm  (%s) : %s",
         confirmTFs, UseConfirmFilter ? "[OK] ACTIF" : "[ERR] OFF"));
   Print("| L4 Entree   (M5)  : ON FVG + CHoCH");
   Print("===========================================");
   Print(StringFormat("| M1 Points   : %s | SL=%d TP=%d",
         M1_Active  ? "ON"  : "OFF", M1_SL_Points, M1_TP_Points));
   Print(StringFormat("| M2 ATR      : %s | x%.1f / x%.1f",
         M2_Active && !M1_Active  ? "ON" : "WAIT", M2_SL_Mult, M2_TP_Mult));
   Print(StringFormat("| M3 BE       : %s | %s",
         M3_Active  ? "ON"  : "OFF",
         M3_UseRR ? StringFormat("RR %.1f", M3_RR_Trigger)
                  : StringFormat("%d pts", M3_Points_Trigger)));
   Print(StringFormat("| M4 Trail    : %s | %s dist:%dpts",
         M4_Active  ? "ON"  : "OFF",
         M4_UseRR ? StringFormat("RR %.1f", M4_RR_Activation)
                  : StringFormat("%d pts", M4_Points_Activation),
         M4_Trail_Distance));
   Print(StringFormat("| Risque: %.1f%% | MaxTrades/j: %d",
         RiskPercent, MaxDailyTrades));
   Print("===========================================");
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                       |
//+------------------------------------------------------------------+
void UpdateComment()
{
   string methode = UseBiasEMA ? "EMA" : "STRUCTURE ICT";

   // Infos EMA par TF selon methode active
   string macroInfo, biaisInfo, confInfo;
   if(UseBiasEMA) {
      macroInfo = Macro_EMA2_Period > 0
         ? StringFormat("EMA%d/EMA%d", Macro_EMA1_Period, Macro_EMA2_Period)
         : StringFormat("EMA%d vs Prix", Macro_EMA1_Period);
      biaisInfo = StringFormat("EMA%d/EMA%d+BOS",
                  Biais_EMA1_Period, Biais_EMA2_Period);
      confInfo  = StringFormat("EMA%d/EMA%d+CHoCH",
                  Confirm_EMA1_Period, Confirm_EMA2_Period);
   } else {
      macroInfo = StringFormat("HH/HL/LH/LL lb:%d", Macro_Struct_LB);
      biaisInfo = StringFormat("BOS/CHoCH lb:%d",   Biais_Struct_LB);
      confInfo  = StringFormat("CHoCH lb:%d",        Confirm_Struct_LB);
   }

   string macroS  = !UseMacroFilter ? "OFF"
                  : g_MacroBias > 0 ? "Bull"
                  : g_MacroBias < 0 ? "Bear" : "?";
   string biaisS  = g_MainBias > 0  ? "Bull"
                  : g_MainBias < 0  ? "Bear" : "?";
   string confBS  = g_ConfirmBull   ? "OK" : "NO";
   string confBrS = g_ConfirmBear   ? "OK" : "NO";
   string chBullS = g_CHoCH_Bull    ? "OK" : "NO";
   string chBearS = g_CHoCH_Bear    ? "OK" : "NO";

   // Windows status
   string w1s = UseWindow1
      ? StringFormat("[OK] %04d-%04d GMT+2", W1_Start, W1_End)
      : "[ERR] OFF";
   string w2s = UseWindow2
      ? StringFormat("[OK] %04d-%04d GMT+2", W2_Start, W2_End)
      : "[ERR] OFF";
   string w3s = UseWindow3
      ? StringFormat("[OK] %04d-%04d GMT+2", W3_Start, W3_End)
      : "[ERR] OFF";

   // Jours autorises
   string daysStr = "";
   if(TradeLundi)    daysStr += "Lun ";
   if(TradeMardi)    daysStr += "Mar ";
   if(TradeMercredi) daysStr += "Mer ";
   if(TradeJeudi)    daysStr += "Jeu ";
   if(TradeVendredi) daysStr += StringFormat("Ven(<%04d) ", VendrediStop);

   bool dayOk  = IsTradingDayAllowed();
   string winS = IsSilverBulletWindow()
      ? "[OK] " + GetWindowName()
      : (!dayOk ? "[ERR] " + GetDayName() + " non autorise"
                : "[ERR] Hors fenetre");

   Comment(StringFormat(
      "=================================\n"
      "  SILVER BULLET ICT  v3.2\n"
      "  Methode Biais : %s\n"
      "=================================\n"
      " W1 NY-03h : %s\n"
      " W2 NY-10h : %s\n"
      " W3 NY-14h : %s\n"
      " Jours     : %s\n"
      "=================================\n"
      " L1 Macro (%s)\n"
      "    %s >> %s\n"
      " L2 Biais (%s)\n"
      "    %s >> %s\n"
      " L3 Conf  (%s)\n"
      "    %s >> BUY:%s SELL:%s\n"
      " L4 CHoCH M5 >> BUY:%s SELL:%s\n"
      " L4 FVG   M5 >> %s\n"
      "=================================\n"
      " M1 SL/TP Points : %s\n"
      " M2 SL/TP ATR    : %s\n"
      " M3 Break Even   : %s\n"
      " M4 Trail Stop   : %s\n"
      "=================================\n"
      " Statut   : %s\n"
      " Trades/j : %d/%d\n"
      " Spread   : %d pts\n"
      " Balance  : %.2f USD\n"
      "=================================",
      methode,
      w1s, w2s, w3s, daysStr,
      TFtoStr(MacroTF),   macroInfo, macroS,
      TFtoStr(BiaisTF),   biaisInfo, biaisS,
      TFtoStr(ConfirmTF), confInfo,  confBS, confBrS,
      chBullS, chBearS,
      g_HasFVG ? StringFormat("%.2f-%.2f %s",
         g_FVG.low, g_FVG.high, g_FVG.isBullish ? "BUY" : "SELL") : "NO",
      M1_Active ? StringFormat("ON SL:%d TP:%d", M1_SL_Points, M1_TP_Points) : "OFF",
      M2_Active && !M1_Active ? StringFormat("ON ATR(%d)", M2_ATR_Period) : "standby",
      M3_Active ? (M3_UseRR ? StringFormat("ON RR%.1f", M3_RR_Trigger)
                            : StringFormat("ON %dpts", M3_Points_Trigger)) : "OFF",
      M4_Active ? (M4_UseRR ? StringFormat("ON RR%.1f dist:%d", M4_RR_Activation, M4_Trail_Distance)
                            : StringFormat("ON %dpts dist:%d", M4_Points_Activation, M4_Trail_Distance)) : "OFF",
      winS,
      g_DailyTrades, MaxDailyTrades,
      (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
      AccountInfoDouble(ACCOUNT_BALANCE)
   ));
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)
      HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY) {
      double p = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      Print(p >= 0 ? StringFormat(" Profit : +%.2f $", p)
                   : StringFormat(" Perte  :  %.2f $", p));
      CleanClosedTrades();
   }
}
//+------------------------------------------------------------------+
