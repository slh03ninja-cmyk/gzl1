//+------------------------------------------------------------------+
//|                                      Quantum_Pressure_Index.mq5 |
//|                         XAUUSD M5 - QPI v1.0                    |
//|  Concept original : 3 pressions convergentes = signal fiable    |
//|                                                                  |
//|  LOGIQUE QPI :                                                   |
//|  Score = P_Structure + P_Momentum + P_Temporelle                |
//|  Signal BUY  si Score > +Seuil sur N bougies consecutives       |
//|  Signal SELL si Score < -Seuil sur N bougies consecutives       |
//|                                                                  |
//|  P_Structure  : Acceleration ALMA (derivee 2e de la moyenne)    |
//|  P_Momentum   : Acceleration RSI  (derivee 2e de l oscillateur) |
//|  P_Temporelle : Poids horaire dans la session de trading         |
//+------------------------------------------------------------------+
#property copyright   "Quantum_Pressure_Index v1.0"
#property version     "1.00"
#property description "QPI : Score de pression convergente sur 3 dimensions"
#property description "Signal = Acceleration ALMA + Acceleration RSI + Poids Session"
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
//|  PARAMETRES                                                       |
//+------------------------------------------------------------------+
input group   "=== Structure (ALMA) ==="
input int     InpALMA_Period   = 18;    // Periode ALMA
input double  InpALMA_Sigma    = 5.0;   // Sigma ALMA
input double  InpALMA_Offset   = 0.85;  // Offset ALMA
input int     InpAccel_Bars    = 3;     // Bougies pour acceleration

input group   "=== Momentum (RSI) ==="
input int     InpRSI_Period    = 8;     // Periode RSI
input int     InpRSI_Smooth    = 3;     // Lissage RSI (EMA)
input int     InpRSI_AccelBars = 3;     // Bougies pour acceleration RSI

input group   "=== Score QPI ==="
input double  InpScoreMin      = 45.0;  // Score minimum pour signal (0-100)
input int     InpConfirmBars   = 2;     // Bougies consecutives au dessus du seuil
input int     InpCooldown      = 5;     // Bougies minimum entre signaux

input group   "=== Filtre Spread ==="
input bool    InpUseSpread     = true;
input int     InpMaxSpread     = 35;    // Spread max en points (XAUUSD standard ~20-30)

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
input int     InpWinBars       = 150;   // Bougies pour calcul win rate

//+------------------------------------------------------------------+
//|  BUFFERS                                                          |
//+------------------------------------------------------------------+
double BufBuy[];       // 0 - Signal BUY (fleche)
double BufSell[];      // 1 - Signal SELL (fleche)
double BufALMA[];      // 2 - ALMA (calcul)
double BufALMA2[];     // 3 - ALMA lisse pour acceleration (calcul)
double BufRSI[];       // 4 - RSI brut (calcul)
double BufRSISmooth[]; // 5 - RSI lisse (calcul)
double BufScore[];     // 6 - Score QPI composite (calcul)
double BufPressure[];  // 7 - Pression nette (calcul)

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
     { Alert("Erreur RSI handle : ", GetLastError()); return INIT_FAILED; }

   int mb = InpALMA_Period + InpAccel_Bars + InpRSI_AccelBars + InpConfirmBars + 10;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, mb);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, mb);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("QPI [Seuil:%.0f | Conf:%d | Cool:%d]",
                   InpScoreMin, InpConfirmBars, InpCooldown));

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
//|  FONCTIONS CORE QPI                                               |
//+------------------------------------------------------------------+

//--- Calcul ALMA (Arnaud Legoux Moving Average)
double CalcALMA(const int idx, const double &price[], const int total)
  {
   int p = InpALMA_Period;
   if(idx < p - 1 || idx >= total) return price[MathMin(idx, total-1)];
   double m    = InpALMA_Offset * (p - 1);
   double s    = p / InpALMA_Sigma;
   double wSum = 0, result = 0;
   for(int k = 0; k < p; k++)
     {
      double w  = MathExp(-MathPow(k - m, 2) / (2.0 * MathPow(s, 2)));
      result   += w * price[idx - (p - 1 - k)];
      wSum     += w;
     }
   return (wSum > 0) ? result / wSum : price[idx];
  }

//--- Pression de Structure : acceleration de l'ALMA
//    = variation de la pente de l'ALMA sur N bougies
//    Score de -100 a +100
double PressionStructure(const int i, const int n)
  {
   if(i < n + 1) return 0;
   // Pente courante vs pente precedente = acceleration
   double slope_now  = BufALMA[i]   - BufALMA[i-1];
   double slope_prev = BufALMA[i-n] - BufALMA[i-n-1];
   double accel      = slope_now - slope_prev;

   // Normalisation : on exprime en points, on borne a [-100,+100]
   double accelPts = accel / _Point;
   double score    = MathMax(-100, MathMin(100, accelPts * 5.0));

   // Bonus si le prix est du bon cote de l'ALMA
   // (renforce le score si structure et prix sont alignes)
   return score;
  }

//--- Pression de Momentum : acceleration du RSI lisse
//    = variation de la vitesse du RSI
//    Score de -100 a +100
double PressionMomentum(const int i, const int n)
  {
   if(i < n + 1) return 0;
   double rsiVel_now  = BufRSISmooth[i]   - BufRSISmooth[i-1];
   double rsiVel_prev = BufRSISmooth[i-n] - BufRSISmooth[i-n-1];
   double rsiAccel    = rsiVel_now - rsiVel_prev;

   // Normalisation : RSI varie de 0 a 100, acceleration bornee
   double score = MathMax(-100, MathMin(100, rsiAccel * 12.0));
   return score;
  }

//--- Pression Temporelle : poids selon position dans la session
//    Debut de session (30 min) = poids max (100)
//    Milieu de session          = poids moyen (50)
//    Hors session               = poids nul (0) - bloque le signal
//    Le poids est TOUJOURS POSITIF (il amplifie le score absolu)
double PressionTemporelle(const datetime t)
  {
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int h = dt.hour;
   int m = dt.min;
   int minOfDay = h * 60 + m;

   // Periodes haute pression (debut de session = mouvements forts)
   int londonOpen = InpLondon_Start * 60;
   int nyOpen     = InpNY_Start * 60;

   // Dans les 45 premieres minutes d'une session = poids max
   if((minOfDay >= londonOpen && minOfDay < londonOpen + 45) ||
      (minOfDay >= nyOpen     && minOfDay < nyOpen + 45))
      return 100.0;

   // Dans la session mais pas l'ouverture = poids moyen
   int londonEnd = InpLondon_End * 60;
   int nyEnd     = InpNY_End * 60;
   if((minOfDay >= londonOpen && minOfDay < londonEnd) ||
      (minOfDay >= nyOpen     && minOfDay < nyEnd))
      return 60.0;

   // Hors session = poids faible (ne bloque pas completement,
   // mais reduit fortement le score)
   return 20.0;
  }

//--- Score QPI composite [-100, +100]
//    Formule : (P_Struct * 0.45) + (P_Momentum * 0.40) + signe * (P_Temp * 0.15)
double CalcQPIScore(const int i, const datetime t,
                    const double &close[], const double &open[])
  {
   double pS = PressionStructure(i, InpAccel_Bars);
   double pM = PressionMomentum(i,  InpRSI_AccelBars);
   double pT = PressionTemporelle(t);

   // La pression temporelle amplifie dans la direction du signal
   double direction = (pS + pM >= 0) ? 1.0 : -1.0;
   double raw = (pS * 0.45) + (pM * 0.40) + (direction * pT * 0.15);

   // Bonus : bougie de confirmation (corps dans le sens du signal)
   double body = close[i] - open[i]; // positif = haussier
   if((raw > 0 && body > 0) || (raw < 0 && body < 0))
      raw *= 1.15; // boost de 15% si bougie confirme

   return MathMax(-100, MathMin(100, raw));
  }

//+------------------------------------------------------------------+
//|  OnCalculate                                                      |
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

   // Copie RSI
   double rsi_raw[];
   ArraySetAsSeries(rsi_raw, false);
   int rsiCopied = CopyBuffer(h_RSI, 0, 0, rates_total, rsi_raw);
   if(rsiCopied <= 0) return prev_calculated;
   int rsiOffset = rates_total - rsiCopied;

   int start = (prev_calculated == 0) ? minReq : MathMax(prev_calculated - 1, minReq);
   if(start >= rates_total) return rates_total;

   //================================================================
   //  PASSE 1 : calcul ALMA + RSI lisse sur toutes les barres
   //================================================================
   for(int i = start; i < rates_total; i++)
     {
      // ALMA
      BufALMA[i]  = CalcALMA(i, close, rates_total);
      // ALMA lisse (EMA de l'ALMA pour avoir une pente plus douce)
      double kA   = 2.0 / (InpAccel_Bars + 1.0);
      BufALMA2[i] = (i > start) ?
                    BufALMA[i] * kA + BufALMA2[i-1] * (1.0 - kA) :
                    BufALMA[i];

      // RSI
      int ri = i - rsiOffset;
      if(ri >= 0 && ri < rsiCopied)
           BufRSI[i] = rsi_raw[ri];
      else BufRSI[i] = 50.0;

      // RSI lisse (EMA)
      double kR      = 2.0 / (InpRSI_Smooth + 1.0);
      BufRSISmooth[i] = (i > start && BufRSISmooth[i-1] != EMPTY_VALUE) ?
                         BufRSI[i] * kR + BufRSISmooth[i-1] * (1.0 - kR) :
                         BufRSI[i];
     }

   //================================================================
   //  PASSE 2 : calcul score QPI + detection signaux
   //================================================================
   for(int i = start; i < rates_total; i++)
     {
      BufBuy[i]  = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;

      if(i < minReq) continue;

      // Score QPI
      double score = CalcQPIScore(i, time[i], close, open);
      BufScore[i]  = score;

      // Pression nette (pour affichage dashboard)
      BufPressure[i] = PressionStructure(i, InpAccel_Bars) +
                       PressionMomentum(i, InpRSI_AccelBars);

      // --- Filtre spread ---
      if(InpUseSpread && spread[i] > InpMaxSpread) continue;

      // --- Filtre session (si hors session AND poids < 40 = pas de signal) ---
      if(InpUseSession && PressionTemporelle(time[i]) < 40.0) continue;

      // --- Cooldown ---
      if((i - g_lastBar) < InpCooldown) continue;

      // --- Confirmation : score au dessus du seuil sur N bougies consecutives ---
      bool confirmBuy  = true;
      bool confirmSell = true;
      for(int c = 0; c < InpConfirmBars; c++)
        {
         if(i - c < 0) { confirmBuy = false; confirmSell = false; break; }
         if(BufScore[i-c] <  InpScoreMin)  confirmBuy  = false;
         if(BufScore[i-c] > -InpScoreMin)  confirmSell = false;
        }

      // --- Condition supplementaire : RSI pas en zone extreme ---
      double rsiNow = BufRSISmooth[i];
      bool rsiOkBuy  = (rsiNow > 30 && rsiNow < 72);
      bool rsiOkSell = (rsiNow > 28 && rsiNow < 70);

      // --- Signal final ---
      bool buySignal  = confirmBuy  && rsiOkBuy;
      bool sellSignal = confirmSell && rsiOkSell;

      if(buySignal)
        {
         BufBuy[i]  = low[i]  - _Point * 130;
         g_lastBar  = i;
        }
      else if(sellSignal)
        {
         BufSell[i] = high[i] + _Point * 130;
         g_lastBar  = i;
        }

      // Alertes
      if(i == rates_total - 1 && time[i] != g_lastAlert)
        {
         if(buySignal || sellSignal)
           {
            string dir = buySignal ? "BUY" : "SELL";
            string msg = StringFormat(
               "[QPI] %s | %s | Prix: %.2f | Score: %.1f | %s",
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
//|  Win Rate                                                         |
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
   double pct = (double)wins / total * 100.0;
   return StringFormat("%.0f%%  [%d/%d]", pct, wins, total);
  }

//+------------------------------------------------------------------+
//|  Dashboard                                                        |
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
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
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
   MakeRect(g_pfx+"bg", x-6, y-6, 290, 270);
   MakeLabel(g_pfx+"title", "  QUANTUM PRESSURE INDEX",    x, y, clrGold, 10, "Arial Bold");
   y+=20; MakeLabel(g_pfx+"sub",  "  Score 3D : Structure+Momentum+Temps", x, y, C'120,120,160', 8);
   y+=16; MakeLabel(g_pfx+"s0",   "---------------------------------",      x, y, C'40,40,90',    8);
   y+=13; MakeLabel(g_pfx+"sym",  "Symbole  : "+_Symbol,                    x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"tf",   "Timeframe: M5",                          x, y, clrSilver, 9);
   y+=15; MakeLabel(g_pfx+"s1",   "---------------------------------",      x, y, C'40,40,90',    8);
   y+=13; MakeLabel(g_pfx+"wrl",  "Win Rate ("+IntegerToString(InpWinBars)+" bougies) :", x, y, clrLightSkyBlue, 9, "Arial Bold");
   y+=15; MakeLabel(g_pfx+"wrv",  "Calcul...",                              x, y, clrYellow, 10, "Arial Bold");
   y+=19; MakeLabel(g_pfx+"s2",   "---------------------------------",      x, y, C'40,40,90',    8);
   y+=13; MakeLabel(g_pfx+"sc",   "Score QPI  : --",                        x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"ps",   "P.Structure: --",                        x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"pm",   "P.Momentum : --",                        x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"pt",   "P.Temps    : --",                        x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"sp",   "Spread     : --",                        x, y, clrSilver, 9);
   y+=16; MakeLabel(g_pfx+"s3",   "---------------------------------",      x, y, C'40,40,90',    8);
   y+=13; MakeLabel(g_pfx+"sig",  "Signal : --",                            x, y, clrSilver, 9);
   y+=14; MakeLabel(g_pfx+"ses",  "Session: --",                            x, y, clrSilver, 9);
   y+=16; MakeLabel(g_pfx+"ver",  "QPI v1.0 | Concept original XAUUSD",    x, y, C'60,60,80', 8);
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

   // Score QPI
   double score = BufScore[last];
   color  scC   = (score > InpScoreMin)  ? clrDeepSkyBlue :
                  (score < -InpScoreMin) ? clrOrangeRed   : clrSilver;
   ObjectSetString(0,  g_pfx+"sc", OBJPROP_TEXT,
      StringFormat("Score QPI  : %.1f / %.0f", score, InpScoreMin));
   ObjectSetInteger(0, g_pfx+"sc", OBJPROP_COLOR, scC);

   // Pression Structure
   double pS = PressionStructure(last, InpAccel_Bars);
   color  pSC = (pS > 10) ? clrLimeGreen : (pS < -10) ? clrOrangeRed : clrSilver;
   ObjectSetString(0,  g_pfx+"ps", OBJPROP_TEXT,
      StringFormat("P.Structure: %.1f", pS));
   ObjectSetInteger(0, g_pfx+"ps", OBJPROP_COLOR, pSC);

   // Pression Momentum
   double pM = PressionMomentum(last, InpRSI_AccelBars);
   color  pMC = (pM > 10) ? clrLimeGreen : (pM < -10) ? clrOrangeRed : clrSilver;
   ObjectSetString(0,  g_pfx+"pm", OBJPROP_TEXT,
      StringFormat("P.Momentum : %.1f  |  RSI: %.1f", pM, BufRSISmooth[last]));
   ObjectSetInteger(0, g_pfx+"pm", OBJPROP_COLOR, pMC);

   // Pression Temporelle
   double pT = PressionTemporelle(time[last]);
   color  pTC = (pT >= 80) ? clrGold : (pT >= 50) ? clrYellow : clrSilver;
   ObjectSetString(0,  g_pfx+"pt", OBJPROP_TEXT,
      StringFormat("P.Temps    : %.0f%%  %s",
                   pT, pT >= 80 ? "[OUVERTURE]" : pT >= 50 ? "[SESSION]" : "[FAIBLE]"));
   ObjectSetInteger(0, g_pfx+"pt", OBJPROP_COLOR, pTC);

   // Spread
   int    spV = spread[last];
   color  spC = (spV <= InpMaxSpread) ? clrLimeGreen : clrOrangeRed;
   ObjectSetString(0,  g_pfx+"sp", OBJPROP_TEXT,
      StringFormat("Spread     : %d pts  %s",
                   spV, spV <= InpMaxSpread ? "[OK]" : "[TROP ELEVE]"));
   ObjectSetInteger(0, g_pfx+"sp", OBJPROP_COLOR, spC);

   // Dernier signal
   string sigTxt = "Aucun signal recent";
   color  sigC   = clrSilver;
   for(int i = last; i >= MathMax(0, last-30); i--)
     {
      if(BufBuy[i] != EMPTY_VALUE)
        { sigTxt = "BUY @ "+TimeToString(time[i], TIME_MINUTES)+
                   "  Score:"+DoubleToString(BufScore[i], 1);
          sigC = clrDeepSkyBlue; break; }
      if(BufSell[i] != EMPTY_VALUE)
        { sigTxt = "SELL @ "+TimeToString(time[i], TIME_MINUTES)+
                   "  Score:"+DoubleToString(BufScore[i], 1);
          sigC = clrOrangeRed; break; }
     }
   ObjectSetString(0,  g_pfx+"sig", OBJPROP_TEXT,  "Signal : "+sigTxt);
   ObjectSetInteger(0, g_pfx+"sig", OBJPROP_COLOR, sigC);

   // Session
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hr = dt.hour, mn = dt.min;
   int minNow = hr * 60 + mn;
   string sS = "Hors session"; color sC = clrOrangeRed;
   if(hr >= InpLondon_Start && hr < InpLondon_End)
     {
      bool isOpen = (minNow < InpLondon_Start*60 + 45);
      sS = isOpen ? "LONDRES [OUVERTURE - FORT]" : "LONDRES [ACTIVE]";
      sC = isOpen ? clrGold : clrLimeGreen;
     }
   else if(hr >= InpNY_Start && hr < InpNY_End)
     {
      bool isOpen = (minNow < InpNY_Start*60 + 45);
      sS = isOpen ? "NEW YORK [OUVERTURE - FORT]" : "NEW YORK [ACTIVE]";
      sC = isOpen ? clrGold : clrLimeGreen;
     }
   ObjectSetString(0,  g_pfx+"ses", OBJPROP_TEXT,  "Session: "+sS);
   ObjectSetInteger(0, g_pfx+"ses", OBJPROP_COLOR, sC);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
//|  FIN - Quantum_Pressure_Index v1.0                               |
//+------------------------------------------------------------------+
