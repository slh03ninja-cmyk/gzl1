//+------------------------------------------------------------------+
//|                                         Quantum_Scalper_Pro.mq5 |
//|               Scalping HF - XAUUSD M1/M5                        |
//|   Confluence : ALMA + RVOL + RSI Lisse (Crossover)              |
//+------------------------------------------------------------------+
#property copyright   "Quantum_Scalper_Pro v1.0"
#property version     "1.00"
#property description "Indicateur scalping haute frequence XAUUSD"
#property description "Signal = ALMA Trend + RVOL Filter + RSI Signal Cross"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   2
#property indicator_label1  "BUY Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3
#property indicator_label2  "SELL Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

input group              "=== ALMA ==="
input int                InpALMA_Period    = 20;
input double             InpALMA_Sigma     = 6.0;
input double             InpALMA_Offset    = 0.85;
input group              "=== RSI Lisse ==="
input int                InpRSI_Period     = 7;
input int                InpRSI_Signal     = 3;
input int                InpRSI_OB         = 80;
input int                InpRSI_OS         = 20;
input group              "=== RVOL ==="
input int                InpRVOL_Period    = 10;
input double             InpRVOL_Mult      = 1.5;
input group              "=== Sessions GMT+0 ==="
input bool               InpUseTimeFilter  = true;
input int                InpLondon_Start   = 8;
input int                InpLondon_End     = 12;
input int                InpNewYork_Start  = 13;
input int                InpNewYork_End    = 20;
input group              "=== Alertes ==="
input bool               InpAlertSound     = true;
input bool               InpAlertPush      = true;
input bool               InpAlertPopup     = true;
input group              "=== Dashboard ==="
input bool               InpShowDashboard  = true;
input int                InpWinRateBars    = 100;
input ENUM_BASE_CORNER   InpDashCorner     = CORNER_LEFT_UPPER;
input int                InpDashX          = 15;
input int                InpDashY          = 20;

double BufferBuy[];
double BufferSell[];
double BufferALMA[];
double BufferRSI[];
double BufferRSISig[];
double BufferSlope[];

int      h_RSI       = INVALID_HANDLE;
datetime g_lastAlert = 0;
string   g_pfx       = "QSP_";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpALMA_Period < 2 || InpRSI_Period < 2 || InpRVOL_Period < 2)
     { Alert("Parametres invalides"); return INIT_PARAMETERS_INCORRECT; }

   SetIndexBuffer(0, BufferBuy,     INDICATOR_DATA);
   SetIndexBuffer(1, BufferSell,    INDICATOR_DATA);
   SetIndexBuffer(2, BufferALMA,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufferRSI,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufferRSISig,  INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, BufferSlope,   INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -12);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  12);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1,  PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // FIX : initialisation explicite de tous les buffers
   ArrayInitialize(BufferBuy,    EMPTY_VALUE);
   ArrayInitialize(BufferSell,   EMPTY_VALUE);
   ArrayInitialize(BufferRSI,    EMPTY_VALUE);
   ArrayInitialize(BufferRSISig, EMPTY_VALUE);
   ArrayInitialize(BufferALMA,   0.0);
   ArrayInitialize(BufferSlope,  0.0);

   h_RSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   if(h_RSI == INVALID_HANDLE)
     { Alert("Echec creation handle RSI : ", GetLastError()); return INIT_FAILED; }

   int mb = InpALMA_Period + InpRSI_Period + InpRSI_Signal + InpRVOL_Period + 5;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, mb);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, mb);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("QSP [ALMA:%d|RSI:%d|RVOL:%.1fx]",
                   InpALMA_Period, InpRSI_Period, InpRVOL_Mult));

   if(InpShowDashboard) CreateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h_RSI != INVALID_HANDLE) IndicatorRelease(h_RSI);
   ObjectsDeleteAll(0, g_pfx);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   int minReq = InpALMA_Period + InpRSI_Period + InpRSI_Signal + InpRVOL_Period + 5;
   if(rates_total < minReq) return 0;

   // Copie buffer RSI (ordre chronologique, NON-series)
   double rsi_raw[];
   ArraySetAsSeries(rsi_raw, false);
   int rsiCopied = CopyBuffer(h_RSI, 0, 0, rates_total, rsi_raw);
   if(rsiCopied <= 0) return prev_calculated;

   // FIX : offset entre rates_total et rsiCopied
   // rsi_raw[0] = barre la plus ancienne copiée
   // rsi_raw[rsiCopied-1] = barre la plus récente
   int rsiOffset = rates_total - rsiCopied;

   int start = (prev_calculated == 0) ? minReq : MathMax(prev_calculated - 1, minReq);
   if(start >= rates_total) return rates_total;

   for(int i = start; i < rates_total; i++)
     {
      // ALMA
      double alma = CalcALMA(i, close, rates_total);
      BufferALMA[i]  = alma;
      BufferSlope[i] = (i > 0) ? alma - BufferALMA[i - 1] : 0.0;

      bool condA_Buy  = (close[i] > alma) && (BufferSlope[i] > 0);
      bool condA_Sell = (close[i] < alma) && (BufferSlope[i] < 0);

      // RVOL
      bool condB = false;
      if(i >= InpRVOL_Period)
        {
         double vs = 0;
         for(int v = 1; v <= InpRVOL_Period; v++) vs += (double)tick_volume[i - v];
         double va = vs / InpRVOL_Period;
         condB = (va > 0) && ((double)tick_volume[i] >= InpRVOL_Mult * va);
        }

      // FIX : mapping RSI robuste
      int ri = i - rsiOffset;
      if(ri < 1 || ri >= rsiCopied)
        {
         BufferRSI[i]    = 50.0;
         BufferRSISig[i] = 50.0;
         BufferBuy[i]    = EMPTY_VALUE;
         BufferSell[i]   = EMPTY_VALUE;
         continue;
        }
      BufferRSI[i] = rsi_raw[ri];

      // FIX : seed EMA RSI sur la premiere barre valide
      if(i <= minReq || BufferRSISig[i - 1] == EMPTY_VALUE)
        {
         BufferRSISig[i] = BufferRSI[i];
        }
      else
        {
         double k = 2.0 / (InpRSI_Signal + 1.0);
         BufferRSISig[i] = BufferRSI[i] * k + BufferRSISig[i - 1] * (1.0 - k);
        }

      double rN = BufferRSI[i],    rP = BufferRSI[i - 1];
      double sN = BufferRSISig[i], sP = BufferRSISig[i - 1];

      bool rsiBuy  = (rP <= sP) && (rN > sN) && (rN < InpRSI_OB);
      bool rsiSell = (rP >= sP) && (rN < sN) && (rN > InpRSI_OS);

      // Filtre session
      bool condTime = true;
      if(InpUseTimeFilter)
        {
         MqlDateTime dt;
         TimeToStruct(time[i], dt);
         int h = dt.hour;
         condTime = (h >= InpLondon_Start  && h < InpLondon_End) ||
                    (h >= InpNewYork_Start && h < InpNewYork_End);
        }

      BufferBuy[i]  = EMPTY_VALUE;
      BufferSell[i] = EMPTY_VALUE;

      bool buySignal  = condA_Buy  && condB && rsiBuy  && condTime;
      bool sellSignal = condA_Sell && condB && rsiSell && condTime;

      if(buySignal)       BufferBuy[i]  = low[i]  - _Point * 150;
      else if(sellSignal) BufferSell[i] = high[i] + _Point * 150;

      // Alertes (derniere barre uniquement)
      if(i == rates_total - 1 && time[i] != g_lastAlert)
        {
         if(buySignal || sellSignal)
           {
            string dir = buySignal ? "BUY UP" : "SELL DOWN";
            string msg = StringFormat("[QSP] %s | %s | %s | %.2f",
                         _Symbol, dir,
                         TimeToString(time[i], TIME_DATE | TIME_MINUTES),
                         close[i]);
            if(InpAlertPopup) Alert(msg);
            if(InpAlertSound) PlaySound("alert.wav");
            if(InpAlertPush)  SendNotification(msg);
            g_lastAlert = time[i];
           }
        }
     }

   if(InpShowDashboard && rates_total > 1)
      UpdateDashboard(rates_total, time, close, high, low, tick_volume);

   return rates_total;
  }

//+------------------------------------------------------------------+
double CalcALMA(const int idx, const double &price[], const int total)
  {
   int p = InpALMA_Period;
   if(idx < p - 1 || idx >= total) return price[idx];
   double m    = InpALMA_Offset * (p - 1);
   double s    = p / InpALMA_Sigma;
   double wSum = 0, result = 0;
   for(int k = 0; k < p; k++)
     {
      double w = MathExp(-MathPow(k - m, 2) / (2.0 * MathPow(s, 2)));
      result += w * price[idx - (p - 1 - k)];
      wSum   += w;
     }
   return (wSum > 0) ? result / wSum : price[idx];
  }

//+------------------------------------------------------------------+
string CalcWinRate(const int rates_total, const double &close[])
  {
   int wins = 0, total = 0;
   int lb = MathMin(InpWinRateBars, rates_total - 2);
   int si = rates_total - 1 - lb;
   if(si < 1) si = 1;
   for(int i = si; i < rates_total - 1; i++)
     {
      bool hB = (BufferBuy[i]  != EMPTY_VALUE);
      bool hS = (BufferSell[i] != EMPTY_VALUE);
      if(!hB && !hS) continue;
      total++;
      double mv = close[i + 1] - close[i];
      if(hB && mv > 0) wins++;
      if(hS && mv < 0) wins++;
     }
   if(total == 0) return "-- (pas de signaux)";
   return StringFormat("%.1f%%  [%d/%d]", (double)wins / total * 100.0, wins, total);
  }

//+------------------------------------------------------------------+
void MakeLabel(const string name, const string txt,
               const int x, const int y,
               const color clr, const int sz = 9,
               const string font = "Arial")
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     InpDashCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetString(0,  name, OBJPROP_FONT,       font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   sz);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetString(0,  name, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

//+------------------------------------------------------------------+
void MakeRect(const string name, const int x, const int y,
              const int w, const int h)
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      InpDashCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     C'10,12,22');
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       C'50,50,100');
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, name, OBJPROP_BACK,        true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
  }

//+------------------------------------------------------------------+
string PeriodStr()
  {
   switch(Period())
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return "??";
     }
  }

//+------------------------------------------------------------------+
void CreateDashboard()
  {
   int x = InpDashX, y = InpDashY;
   MakeRect(g_pfx + "bg", x - 6, y - 6, 268, 245);
   MakeLabel(g_pfx + "title", "  QUANTUM SCALPER PRO",                      x, y, clrGold, 10, "Arial Bold");
   y += 20; MakeLabel(g_pfx + "s1",  "------------------------------",       x, y, C'50,50,100', 8);
   y += 14; MakeLabel(g_pfx + "sym", "Symbole  : " + _Symbol,                x, y, clrSilver, 9);
   y += 15; MakeLabel(g_pfx + "tf",  "Timeframe: " + PeriodStr(),            x, y, clrSilver, 9);
   y += 16; MakeLabel(g_pfx + "s2",  "------------------------------",       x, y, C'50,50,100', 8);
   y += 14; MakeLabel(g_pfx + "wrl", "Win Rate (" + IntegerToString(InpWinRateBars) + " bougies):",
                                                                               x, y, clrLightSkyBlue, 9, "Arial Bold");
   y += 16; MakeLabel(g_pfx + "wrv", "Calcul...",                            x, y, clrYellow, 10, "Arial Bold");
   y += 20; MakeLabel(g_pfx + "s3",  "------------------------------",       x, y, C'50,50,100', 8);
   y += 14; MakeLabel(g_pfx + "alv", "ALMA   : --",                          x, y, clrSilver, 9);
   y += 15; MakeLabel(g_pfx + "rvv", "RVOL   : --",                          x, y, clrSilver, 9);
   y += 15; MakeLabel(g_pfx + "rsv", "RSI    : --",                          x, y, clrSilver, 9);
   y += 18; MakeLabel(g_pfx + "s4",  "------------------------------",       x, y, C'50,50,100', 8);
   y += 14; MakeLabel(g_pfx + "ses", "Session: --",                          x, y, clrSilver, 9);
   y += 18; MakeLabel(g_pfx + "ver", "v1.0 | Optimise XAUUSD",               x, y, C'60,60,80', 8);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void UpdateDashboard(const int rates_total,
                     const datetime &time[],
                     const double   &close[],
                     const double   &high[],
                     const double   &low[],
                     const long     &tick_volume[])
  {
   int last = rates_total - 1;
   if(last < 1) return;

   // Win Rate
   string wr  = CalcWinRate(rates_total, close);
   double wrN = StringToDouble(StringSubstr(wr, 0, 4));
   color  wrC = (wrN >= 60) ? clrLimeGreen : (wrN >= 50) ? clrYellow : clrOrangeRed;
   ObjectSetString(0,  g_pfx + "wrv", OBJPROP_TEXT,  wr);
   ObjectSetInteger(0, g_pfx + "wrv", OBJPROP_COLOR, wrC);

   // ALMA
   double av = BufferALMA[last], sl = BufferSlope[last];
   string aS = (close[last] > av && sl > 0) ? "[UP]" :
               (close[last] < av && sl < 0) ? "[DOWN]" : "[FLAT]";
   color  aC = (aS == "[UP]")   ? clrLimeGreen :
               (aS == "[DOWN]") ? clrOrangeRed : clrYellow;
   ObjectSetString(0,  g_pfx + "alv", OBJPROP_TEXT,
      StringFormat("ALMA(%d): %.2f  %s", InpALMA_Period, av, aS));
   ObjectSetInteger(0, g_pfx + "alv", OBJPROP_COLOR, aC);

   // FIX : déclaration explicite long[] pour CopyTickVolume
   long tvols[];
   if(CopyTickVolume(_Symbol, PERIOD_CURRENT, 1, InpRVOL_Period + 1, tvols) > 0)
     {
      int    sz  = ArraySize(tvols);
      double vs  = 0;
      for(int v = 0; v < sz - 1; v++) vs += (double)tvols[v];
      double va  = vs / (sz - 1);
      double cur = (double)tvols[sz - 1];
      double rv  = (va > 0) ? cur / va : 0.0;
      string rS  = (rv >= InpRVOL_Mult) ? "[ACTIF]" : "[FAIBLE]";
      color  rC  = (rv >= InpRVOL_Mult) ? clrLimeGreen : clrOrangeRed;
      ObjectSetString(0,  g_pfx + "rvv", OBJPROP_TEXT,
         StringFormat("RVOL: %.2fx / %.1fx  %s", rv, InpRVOL_Mult, rS));
      ObjectSetInteger(0, g_pfx + "rvv", OBJPROP_COLOR, rC);
     }

   // RSI
   if(BufferRSI[last] != EMPTY_VALUE && BufferRSISig[last] != EMPTY_VALUE)
     {
      double rV = BufferRSI[last], sV = BufferRSISig[last];
      string rS = (rV > InpRSI_OB) ? "[SURCH.]" : (rV < InpRSI_OS) ? "[SURV.]" : "[OK]";
      color  rC = (rV > InpRSI_OB || rV < InpRSI_OS) ? clrOrangeRed : clrLimeGreen;
      ObjectSetString(0,  g_pfx + "rsv", OBJPROP_TEXT,
         StringFormat("RSI(%d): %.1f | Sig: %.1f  %s", InpRSI_Period, rV, sV, rS));
      ObjectSetInteger(0, g_pfx + "rsv", OBJPROP_COLOR, rC);
     }

   // Session
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int    hr = dt.hour;
   string sS = "Hors session";
   color  sC = clrOrangeRed;
   if(hr >= InpLondon_Start  && hr < InpLondon_End)
     { sS = "LONDRES  [ACTIVE]"; sC = clrLimeGreen; }
   else if(hr >= InpNewYork_Start && hr < InpNewYork_End)
     { sS = "NEW YORK [ACTIVE]"; sC = clrLimeGreen; }
   ObjectSetString(0,  g_pfx + "ses", OBJPROP_TEXT,  "Session: " + sS);
   ObjectSetInteger(0, g_pfx + "ses", OBJPROP_COLOR, sC);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
//| FIN - Quantum_Scalper_Pro.mq5                                    |
//+------------------------------------------------------------------+
