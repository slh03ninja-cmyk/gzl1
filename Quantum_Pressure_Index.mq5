//+------------------------------------------------------------------+
//|                                      Quantum_Pressure_Index.mq5 |
//|                         XAUUSD M5 - QPI v1.1                    |
//|  Concept original : 3 pressions convergentes = signal fiable    |
//|                                                                  |
//|  LOGIQUE QPI :                                                   |
//|  Score = P_Structure(45%) + P_Momentum(40%) + P_Temps(15%)      |
//|  Signal BUY  si Score > +Seuil sur N bougies consecutives       |
//|  Signal SELL si Score < -Seuil sur N bougies consecutives       |
//|                                                                  |
//|  P_Structure : direction + acceleration relative de l ALMA      |
//|  P_Momentum  : direction + position + acceleration du RSI       |
//|  P_Temps     : poids horaire dans la session (ouverture=max)    |
//+------------------------------------------------------------------+
#property copyright   "Quantum_Pressure_Index v1.1"
#property version     "1.10"
#property description "QPI : Score de pression convergente sur 3 dimensions"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   2

#property indicator_label1  "QPI BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  4

#property indicator_label2  "QPI SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

//+------------------------------------------------------------------+
input group   "=== Structure (ALMA) ==="
input int     InpALMA_Period   = 18;
input double  InpALMA_Sigma    = 5.0;
input double  InpALMA_Offset   = 0.85;
input int     InpAccel_Bars    = 3;

input group   "=== Momentum (RSI) ==="
input int     InpRSI_Period    = 8;
input int     InpRSI_Smooth    = 3;
input int     InpRSI_AccelBars = 3;

input group   "=== Score QPI ==="
input double  InpScoreMin      = 35.0;  // Seuil signal (0-100)
input int     InpConfirmBars   = 1;     // Bougies confirmation
input int     InpCooldown      = 5;     // Cooldown entre signaux

input group   "=== Filtre Spread ==="
input bool    InpUseSpread     = true;
input int     InpMaxSpread     = 80;    // Points spread max

input group   "=== Sessions GMT+2 Exness ==="
input bool    InpUseSession    = true;
input int     InpLondon_Start  = 10;
input int     InpLondon_End    = 14;
input int     InpNY_Start      = 15;
input int     InpNY_End        = 22;

input group   "=== Alertes ==="
input bool    InpAlertPopup    = true;
input bool    InpAlertSound    = true;
input bool    InpAlertPush     = false;

input group   "=== Dashboard ==="
input bool    InpDashboard     = true;
input int     InpDashX         = 15;
input int     InpDashY         = 20;
input int     InpWinBars       = 150;

//+------------------------------------------------------------------+
double BufBuy[];
double BufSell[];
double BufALMA[];
double BufALMA2[];
double BufRSI[];
double BufRSISmooth[];
double BufScore[];
double BufPressure[];

int      h_RSI       = INVALID_HANDLE;
datetime g_lastAlert = 0;
int      g_lastBar   = 0;
string   g_pfx       = "QPI_";

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBuy,       INDICATOR_DATA);
   SetIndexBuffer(1, BufSell,      INDICATOR_DATA);
   SetIndexBuffer(2, BufALMA,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufALMA2,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(4, BufRSI,       INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, BufRSISmooth, INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, BufScore,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, BufPressure,  INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -15);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  15);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1,  PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ArrayInitialize(BufBuy,       EMPTY_VALUE);
   ArrayInitialize(BufSell,      EMPTY_VALUE);
   ArrayInitialize(BufALMA,      0.0);
   ArrayInitialize(BufALMA2,     0.0);
   ArrayInitialize(BufRSI,       50.0);
   ArrayInitialize(BufRSISmooth, 50.0);
   ArrayInitialize(BufScore,     0.0);
   ArrayInitialize(BufPressure,  0.0);

   h_RSI = iRSI(_Symbol, PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
   if(h_RSI == INVALID_HANDLE)
     { Alert("Erreur RSI : ", GetLastError()); return INIT_FAILED; }

   int mb = InpALMA_Period + InpAccel_Bars + InpRSI_AccelBars + InpConfirmBars + 10;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, mb);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, mb);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("QPI v1.1 [Seuil:%.0f | Conf:%d]", InpScoreMin, InpConfirmBars));

   if(InpDashboard) CreateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h_RSI != INVALID_HANDLE) IndicatorRelease(h_RSI);
   ObjectsDeleteAll(0, g_pfx);
  }

//+------------------------------------------------------------------+
//  ALMA
//+------------------------------------------------------------------+
double CalcALMA(const int idx, const double &price[], const int total)
  {
   int p = InpALMA_Period;
   if(idx < p - 1 || idx >= total) return price[MathMin(idx, total-1)];
   double m = InpALMA_Offset * (p - 1);
   double s = p / InpALMA_Sigma;
   double wSum = 0, result = 0;
   for(int k = 0; k < p; k++)
     {
      double w  = MathExp(-MathPow(k - m, 2) / (2.0 * MathPow(s, 2)));
      result   += w * price[idx - (p - 1 - k)];
      wSum     += w;
     }
   return (wSum > 0) ? result / wSum : price[idx];
  }

//+------------------------------------------------------------------+
//  PRESSION STRUCTURE
//  Direction ALMA (50%) + Acceleration relative (50%)
//  Score -100 a +100
//+------------------------------------------------------------------+
double PressionStructure(const int i, const int n)
  {
   if(i < n + 2) return 0;

   double slope_now  = BufALMA[i]   - BufALMA[i-1];
   double slope_prev = BufALMA[i-n] - BufALMA[i-n-1];

   // Composante direction : +50 si pente positive, -50 si negative
   double dirScore = (slope_now > 0) ? 50.0 : -50.0;

   // Composante acceleration relative : est-ce que la pente s'amplifie ?
   double accelScore = 0;
   if(MathAbs(slope_prev) > 0.0001)
     {
      double ratio = (MathAbs(slope_now) - MathAbs(slope_prev))
                     / MathAbs(slope_prev);
      // ratio > 0 = accel, < 0 = decel, borne a [-1, +1]
      ratio = MathMax(-1.0, MathMin(1.0, ratio));
      accelScore = ratio * 50.0;
      // Garde le signe de la direction
      if(slope_now < 0) accelScore = -MathAbs(accelScore);
      else              accelScore =  MathAbs(accelScore);
     }

   return MathMax(-100, MathMin(100, dirScore + accelScore));
  }

//+------------------------------------------------------------------+
//  PRESSION MOMENTUM
//  Direction RSI (40%) + Position RSI (30%) + Acceleration (30%)
//  Score -100 a +100
//+------------------------------------------------------------------+
double PressionMomentum(const int i, const int n)
  {
   if(i < n + 2) return 0;

   double rsi      = BufRSISmooth[i];
   double vel_now  = BufRSISmooth[i]   - BufRSISmooth[i-1];
   double vel_prev = BufRSISmooth[i-n] - BufRSISmooth[i-n-1];

   // Direction RSI
   double dirScore = (vel_now > 0) ? 40.0 : -40.0;

   // Position par rapport a 50 : RSI 70 montant = fort bullish
   double posScore = MathMax(-30, MathMin(30, (rsi - 50.0) * 0.6));

   // Acceleration de la vitesse RSI
   double accelScore = 0;
   if(MathAbs(vel_prev) > 0.01)
     {
      double ratio = (MathAbs(vel_now) - MathAbs(vel_prev)) / MathAbs(vel_prev);
      ratio = MathMax(-1.0, MathMin(1.0, ratio));
      accelScore = ratio * 30.0;
      if(vel_now < 0) accelScore = -MathAbs(accelScore);
      else            accelScore =  MathAbs(accelScore);
     }

   return MathMax(-100, MathMin(100, dirScore + posScore + accelScore));
  }

//+------------------------------------------------------------------+
//  PRESSION TEMPORELLE
//  Ouverture session (45min) = 100
//  Session active            = 60
//  Hors session              = 20
//+------------------------------------------------------------------+
double PressionTemporelle(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int minOfDay = dt.hour * 60 + dt.min;
   int londonOpen = InpLondon_Start * 60;
   int londonEnd  = InpLondon_End   * 60;
   int nyOpen     = InpNY_Start     * 60;
   int nyEnd      = InpNY_End       * 60;

   if((minOfDay >= londonOpen && minOfDay < londonOpen + 45) ||
      (minOfDay >= nyOpen     && minOfDay < nyOpen + 45))
      return 100.0;

   if((minOfDay >= londonOpen && minOfDay < londonEnd) ||
      (minOfDay >= nyOpen     && minOfDay < nyEnd))
      return 60.0;

   return 20.0;
  }

//+------------------------------------------------------------------+
//  SCORE QPI COMPOSITE
//+------------------------------------------------------------------+
double CalcQPIScore(const int i, const datetime t,
                    const double &close[], const double &open[])
  {
   double pS = PressionStructure(i, InpAccel_Bars);
   double pM = PressionMomentum(i,  InpRSI_AccelBars);
   double pT = PressionTemporelle(t);

   // pT amplifie le score dans la direction dominante
   double direction = ((pS * 0.45 + pM * 0.40) >= 0) ? 1.0 : -1.0;
   double raw = (pS * 0.45) + (pM * 0.40) + (direction * pT * 0.15);

   // Bonus bougie de confirmation (+10%)
   double body = close[i] - open[i];
   if((raw > 0 && body > 0) || (raw < 0 && body < 0))
      raw *= 1.10;

   return MathMax(-100, MathMin(100, raw));
  }

//+------------------------------------------------------------------+
//  OnCalculate
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
   int minReq = InpALMA_Period + InpAccel_Bars + InpRSI_AccelBars + InpConfirmBars + 10;
   if(rates_total < minReq) return 0;

   double rsi_raw[];
   ArraySetAsSeries(rsi_raw, false);
   int rsiCopied = CopyBuffer(h_RSI, 0, 0, rates_total, rsi_raw);
   if(rsiCopied <= 0) return prev_calculated;
   int rsiOffset = rates_total - rsiCopied;

   int start = (prev_calculated == 0) ? minReq : MathMax(prev_calculated - 1, minReq);
   if(start >= rates_total) return rates_total;

   // PASSE 1 : ALMA + RSI lisse
   for(int i = start; i < rates_total; i++)
     {
      BufALMA[i] = CalcALMA(i, close, rates_total);

      double kA = 2.0 / (InpAccel_Bars + 1.0);
      BufALMA2[i] = (i > start) ?
                    BufALMA[i] * kA + BufALMA2[i-1] * (1.0 - kA) :
                    BufALMA[i];

      int ri = i - rsiOffset;
      BufRSI[i] = (ri >= 0 && ri < rsiCopied) ? rsi_raw[ri] : 50.0;

      double kR = 2.0 / (InpRSI_Smooth + 1.0);
      BufRSISmooth[i] = (i > start) ?
                         BufRSI[i] * kR + BufRSISmooth[i-1] * (1.0 - kR) :
                         BufRSI[i];
     }

   // PASSE 2 : Score QPI + signaux
   for(int i = start; i < rates_total; i++)
     {
      BufBuy[i]  = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;
      if(i < minReq) continue;

      double score     = CalcQPIScore(i, time[i], close, open);
      BufScore[i]      = score;
      BufPressure[i]   = PressionStructure(i, InpAccel_Bars) +
                         PressionMomentum(i, InpRSI_AccelBars);

      // Filtre spread
      if(InpUseSpread && spread[i] > InpMaxSpread) continue;

      // Filtre session
      if(InpUseSession && PressionTemporelle(time[i]) < 40.0) continue;

      // Cooldown
      if((i - g_lastBar) < InpCooldown) continue;

      // Confirmation N bougies consecutives
      bool confirmBuy  = true;
      bool confirmSell = true;
      for(int c = 0; c < InpConfirmBars; c++)
        {
         if(i - c < 0) { confirmBuy = false; confirmSell = false; break; }
         if(BufScore[i-c] <  InpScoreMin) confirmBuy  = false;
         if(BufScore[i-c] > -InpScoreMin) confirmSell = false;
        }

      // Filtre RSI pas en zone extremement opposee
      double rsiNow = BufRSISmooth[i];
      bool rsiOkBuy  = (rsiNow < 75);
      bool rsiOkSell = (rsiNow > 25);

      bool buySignal  = confirmBuy  && rsiOkBuy;
      bool sellSignal = confirmSell && rsiOkSell;

      if(buySignal)
        { BufBuy[i]  = low[i]  - _Point * 130; g_lastBar = i; }
      else if(sellSignal)
        { BufSell[i] = high[i] + _Point * 130; g_lastBar = i; }

      // Alertes
      if(i == rates_total - 1 && time[i] != g_lastAlert)
        {
         if(buySignal || sellSignal)
           {
            string dir = buySignal ? "BUY" : "SELL";
            string msg = StringFormat("[QPI] %s | %s | %.2f | Score:%.1f | %s",
                         _Symbol, dir, close[i], score,
                         TimeToString(time[i], TIME_MINUTES));
            if(InpAlertPopup) Alert(msg);
            if(InpAlertSound) PlaySound("alert.wav");
            if(InpAlertPush)  SendNotification(msg);
            g_lastAlert = time[i];
           }
        }
     }

   if(InpDashboard && rates_total > 1)
      UpdateDashboard(rates_total, time, open, close, high, low, spread);

   return rates_total;
  }

//+------------------------------------------------------------------+
//  Win Rate
//+------------------------------------------------------------------+
string CalcWinRate(const int rates_total, const double &close[])
  {
   int wins = 0, total = 0;
   int lb = MathMin(InpWinBars, rates_total - 2);
   int si = rates_total - 1 - lb;
   if(si < 1) si = 1;
   for(int i = si; i < rates_total - 1; i++)
     {
      double mv = close[i+1] - close[i];
      if(BufBuy[i]  != EMPTY_VALUE){ total++; if(mv > 0) wins++; }
      if(BufSell[i] != EMPTY_VALUE){ total++; if(mv < 0) wins++; }
     }
   if(total == 0) return "-- (pas encore de signaux)";
   return StringFormat("%.0f%%  [%d/%d]", (double)wins/total*100.0, wins, total);
  }

//+------------------------------------------------------------------+
//  Dashboard helpers
//+------------------------------------------------------------------+
void MakeLabel(const string name, const string txt,
               const int x, const int y, const color clr,
               const int sz = 9, const string font = "Arial")
  {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetString(0,  name, OBJPROP_FONT,       font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   sz);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetString(0,  name, OBJPROP_TEXT,       txt);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

void MakeRect(const string name, const int x, const int y,
              const int w, const int h)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     C'8,10,20');
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       C'40,40,90');
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
   ObjectSetInteger(0, name, OBJPROP_BACK,        true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
  }

void CreateDashboard()
  {
   int x = InpDashX, y = InpDashY;
   MakeRect(g_pfx+"bg", x-6, y-6, 295, 275);
   MakeLabel(g_pfx+"title", "  QUANTUM PRESSURE INDEX",            x, y, clrGold, 10, "Arial Bold");
   y+=18; MakeLabel(g_pfx+"sub", "  Score 3D : Structure+Momentum+Temps", x, y, C'100,100,150', 8);
   y+=15; MakeLabel(g_pfx+"s0", "----------------------------------",  x, y, C'40,40,90', 8);
   y+=12; MakeLabel(g_pfx+"sym", "Symbole  : "+_Symbol,               x, y, clrSilver, 9);
   y+=13; MakeLabel(g_pfx+"tf",  "Timeframe: M5",                     x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"s1", "----------------------------------",  x, y, C'40,40,90', 8);
   y+=12; MakeLabel(g_pfx+"wrl", "Win Rate ("+IntegerToString(InpWinBars)+" bougies) :", x, y, clrLightSkyBlue, 9, "Arial Bold");
   y+=14; MakeLabel(g_pfx+"wrv", "Calcul...",                         x, y, clrYellow, 10, "Arial Bold");
   y+=18; MakeLabel(g_pfx+"s2", "----------------------------------",  x, y, C'40,40,90', 8);
   y+=12; MakeLabel(g_pfx+"sc",  "Score QPI  : --",                   x, y, clrSilver, 9);
   y+=13; MakeLabel(g_pfx+"ps",  "P.Structure: --",                   x, y, clrSilver, 9);
   y+=13; MakeLabel(g_pfx+"pm",  "P.Momentum : --",                   x, y, clrSilver, 9);
   y+=13; MakeLabel(g_pfx+"pt",  "P.Temps    : --",                   x, y, clrSilver, 9);
   y+=13; MakeLabel(g_pfx+"sp",  "Spread     : --",                   x, y, clrSilver, 9);
   y+=15; MakeLabel(g_pfx+"s3", "----------------------------------",  x, y, C'40,40,90', 8);
   y+=12; MakeLabel(g_pfx+"sig", "Signal : --",                       x, y, clrSilver, 9);
   y+=13; MakeLabel(g_pfx+"ses", "Session: --",                       x, y, clrSilver, 9);
   y+=15; MakeLabel(g_pfx+"ver", "QPI v1.1 | Concept original XAUUSD", x, y, C'60,60,80', 8);
   ChartRedraw();
  }

void UpdateDashboard(const int rates_total,
                     const datetime &time[],
                     const double   &open[],
                     const double   &close[],
                     const double   &high[],
                     const double   &low[],
                     const int      &spread[])
  {
   int last = rates_total - 1;
   if(last < 5) return;

   // Win Rate
   string wr  = CalcWinRate(rates_total, close);
   double wrN = StringToDouble(StringSubstr(wr, 0, 3));
   color  wrC = (wrN >= 60) ? clrLimeGreen : (wrN >= 50) ? clrYellow : clrOrangeRed;
   ObjectSetString(0,  g_pfx+"wrv", OBJPROP_TEXT,  wr);
   ObjectSetInteger(0, g_pfx+"wrv", OBJPROP_COLOR, wrC);

   // Score
   double score = BufScore[last];
   color  scC   = (score >  InpScoreMin) ? clrDeepSkyBlue :
                  (score < -InpScoreMin) ? clrOrangeRed   : clrSilver;
   ObjectSetString(0,  g_pfx+"sc", OBJPROP_TEXT,
      StringFormat("Score QPI  : %.1f / %.0f", score, InpScoreMin));
   ObjectSetInteger(0, g_pfx+"sc", OBJPROP_COLOR, scC);

   // P. Structure
   double pS = PressionStructure(last, InpAccel_Bars);
   color  pSC = (pS > 15) ? clrLimeGreen : (pS < -15) ? clrOrangeRed : clrSilver;
   ObjectSetString(0,  g_pfx+"ps", OBJPROP_TEXT,
      StringFormat("P.Structure: %.1f", pS));
   ObjectSetInteger(0, g_pfx+"ps", OBJPROP_COLOR, pSC);

   // P. Momentum
   double pM = PressionMomentum(last, InpRSI_AccelBars);
   color  pMC = (pM > 15) ? clrLimeGreen : (pM < -15) ? clrOrangeRed : clrSilver;
   ObjectSetString(0,  g_pfx+"pm", OBJPROP_TEXT,
      StringFormat("P.Momentum : %.1f  RSI: %.1f", pM, BufRSISmooth[last]));
   ObjectSetInteger(0, g_pfx+"pm", OBJPROP_COLOR, pMC);

   // P. Temps
   double pT = PressionTemporelle(time[last]);
   color  pTC = (pT >= 90) ? clrGold : (pT >= 50) ? clrYellow : clrSilver;
   ObjectSetString(0,  g_pfx+"pt", OBJPROP_TEXT,
      StringFormat("P.Temps    : %.0f%%  %s",
                   pT, pT >= 90 ? "[OUVERTURE]" : pT >= 50 ? "[SESSION]" : "[FAIBLE]"));
   ObjectSetInteger(0, g_pfx+"pt", OBJPROP_COLOR, pTC);

   // Spread
   int   spV = spread[last];
   color spC = (spV <= InpMaxSpread) ? clrLimeGreen : clrOrangeRed;
   ObjectSetString(0,  g_pfx+"sp", OBJPROP_TEXT,
      StringFormat("Spread     : %d pts  %s",
                   spV, spV <= InpMaxSpread ? "[OK]" : "[TROP ELEVE]"));
   ObjectSetInteger(0, g_pfx+"sp", OBJPROP_COLOR, spC);

   // Dernier signal
   string sigTxt = "Aucun signal recent"; color sigC = clrSilver;
   for(int i = last; i >= MathMax(0, last-50); i--)
     {
      if(BufBuy[i] != EMPTY_VALUE)
        { sigTxt = "BUY @ "+TimeToString(time[i], TIME_MINUTES)+
                   "  Sc:"+DoubleToString(BufScore[i],1);
          sigC = clrDeepSkyBlue; break; }
      if(BufSell[i] != EMPTY_VALUE)
        { sigTxt = "SELL @ "+TimeToString(time[i], TIME_MINUTES)+
                   "  Sc:"+DoubleToString(BufScore[i],1);
          sigC = clrOrangeRed; break; }
     }
   ObjectSetString(0,  g_pfx+"sig", OBJPROP_TEXT,  "Signal : "+sigTxt);
   ObjectSetInteger(0, g_pfx+"sig", OBJPROP_COLOR, sigC);

   // Session
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int minNow = dt.hour * 60 + dt.min;
   string sS = "Hors session"; color sC = clrOrangeRed;
   if(dt.hour >= InpLondon_Start && dt.hour < InpLondon_End)
     {
      sS = (minNow < InpLondon_Start*60+45) ?
           "LONDRES [OUVERTURE]" : "LONDRES [ACTIVE]";
      sC = (minNow < InpLondon_Start*60+45) ? clrGold : clrLimeGreen;
     }
   else if(dt.hour >= InpNY_Start && dt.hour < InpNY_End)
     {
      sS = (minNow < InpNY_Start*60+45) ?
           "NEW YORK [OUVERTURE]" : "NEW YORK [ACTIVE]";
      sC = (minNow < InpNY_Start*60+45) ? clrGold : clrLimeGreen;
     }
   ObjectSetString(0,  g_pfx+"ses", OBJPROP_TEXT,  "Session: "+sS);
   ObjectSetInteger(0, g_pfx+"ses", OBJPROP_COLOR, sC);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
//|  FIN - Quantum_Pressure_Index v1.1                               |
//+------------------------------------------------------------------+
