//+------------------------------------------------------------------+
//|                                          SMC_Gold_Scalper.mq5   |
//|              Smart Money Concepts - Style LuxAlgo               |
//|                    XAUUSD M5 - Version 1.0                      |
//|                                                                  |
//|  LOGIQUE EXACTE LUXALGO :                                        |
//|  - Swing Structure  : BOS / CHoCH (HH HL LH LL)                |
//|  - Internal Structure : BOS / CHoCH internes                    |
//|  - Order Blocks     : Swing OB + Internal OB + mitigation       |
//|  - Fair Value Gaps  : FVG bullish/bearish + auto threshold      |
//|  - EQH / EQL        : Equal Highs / Equal Lows                  |
//|  - Premium/Discount : Zones au dessus/dessous equilibre         |
//|  - Signal BUY/SELL  : Confluence de tous les elements           |
//+------------------------------------------------------------------+
#property copyright   "SMC_Gold_Scalper v1.0"
#property version     "1.00"
#property description "Smart Money Concepts complet - Style LuxAlgo"
#property description "BOS + CHoCH + Order Block + FVG + EQH/EQL + Premium/Discount"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "SMC BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  4

#property indicator_label2  "SMC SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  4

//+------------------------------------------------------------------+
//  PARAMETRES
//+------------------------------------------------------------------+
input group "=== Structure de Marche ==="
input int    InpSwing        = 5;    // Swing length (barres pivot)
input int    InpInternal     = 3;    // Internal structure length
input bool   InpShowSwing    = true; // Afficher swing BOS/CHoCH
input bool   InpShowInternal = true; // Afficher internal BOS/CHoCH

input group "=== Order Blocks ==="
input bool   InpShowOB       = true;
input int    InpOB_Last      = 3;    // Nb d OB a afficher
input bool   InpShowIOB      = true; // Internal OB
input int    InpIOB_Last     = 3;
input bool   InpOB_HlightMit = true; // Griser OB mitiges

input group "=== Fair Value Gaps ==="
input bool   InpShowFVG      = true;
input bool   InpFVG_Auto     = true; // Filtre auto (ignore petits FVG)
input int    InpFVG_Extend   = 8;    // Barres extension FVG

input group "=== Equal Highs / Lows ==="
input bool   InpShowEQ       = true;
input int    InpEQ_Bars      = 3;    // Barres confirmation EQH/EQL
input double InpEQ_Thresh    = 0.5;  // Seuil USD pour egalite

input group "=== Premium / Discount ==="
input bool   InpShowPD       = true;
input int    InpPD_Len       = 50;   // Longueur calcul P/D

input group "=== Signal BUY/SELL ==="
input bool   InpGenSignals   = true;
input int    InpCooldown     = 5;
input bool   InpNeedFVG      = true;  // FVG requis pour signal
input bool   InpNeedOB       = true;  // OB requis pour signal

input group "=== Sessions GMT+2 ==="
input bool   InpUseSession   = true;
input int    InpLondon_Start = 10;
input int    InpLondon_End   = 14;
input int    InpNY_Start     = 15;
input int    InpNY_End       = 22;

input group "=== Alertes ==="
input bool   InpAlertBOS     = true;
input bool   InpAlertCHoCH   = true;
input bool   InpAlertOB      = true;
input bool   InpAlertFVG     = false;
input bool   InpAlertSignal  = true;
input bool   InpAlertPush    = false;

input group "=== Affichage ==="
input bool   InpDashboard    = true;
input int    InpDashX        = 15;
input int    InpDashY        = 20;
input int    InpWinBars      = 200;

//+------------------------------------------------------------------+
//  BUFFERS
//+------------------------------------------------------------------+
double BufBuy[];
double BufSell[];

// Variables etat structure
int    g_swing_trend   = 0;  // 1=bull -1=bear
int    g_int_trend     = 0;
double g_swing_top     = 0, g_swing_btm = DBL_MAX;
double g_int_top       = 0, g_int_btm   = DBL_MAX;
int    g_top_x         = -1, g_btm_x    = -1;
int    g_itop_x        = -1, g_ibtm_x   = -1;
bool   g_top_cross     = false, g_btm_cross = false;
bool   g_itop_cross    = false, g_ibtm_cross = false;

datetime g_lastAlert  = 0;
int      g_lastBar    = 0;
string   g_pfx        = "SMC_";

// FVG arrays
#define MAX_FVG 50
double   g_fvg_top[MAX_FVG], g_fvg_btm[MAX_FVG];
datetime g_fvg_t1[MAX_FVG],  g_fvg_t2[MAX_FVG];
int      g_fvg_dir[MAX_FVG]; // 1=bull -1=bear
int      g_fvg_count = 0;
bool     g_fvg_mit[MAX_FVG];

// OB arrays
#define MAX_OB 20
double   g_ob_top[MAX_OB], g_ob_btm[MAX_OB];
datetime g_ob_t1[MAX_OB],  g_ob_t2[MAX_OB];
int      g_ob_dir[MAX_OB];
bool     g_ob_mit[MAX_OB];
int      g_ob_count = 0;

// Dashboard counters
int g_cnt_bos_bull=0, g_cnt_bos_bear=0;
int g_cnt_choch_bull=0, g_cnt_choch_bear=0;
int g_cnt_fvg_bull=0, g_cnt_fvg_bear=0;
string g_last_signal = "Aucun";
color  g_last_signal_clr = clrSilver;

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBuy,  INDICATOR_DATA);
   SetIndexBuffer(1, BufSell, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(0, PLOT_ARROW_SHIFT, -20);
   PlotIndexSetInteger(1, PLOT_ARROW_SHIFT,  20);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   ArrayInitialize(BufBuy,  EMPTY_VALUE);
   ArrayInitialize(BufSell, EMPTY_VALUE);

   int mb = InpSwing * 2 + 20;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, mb);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, mb);

   IndicatorSetString(INDICATOR_SHORTNAME, "SMC Gold Scalper [LuxAlgo Style]");

   ArrayInitialize(g_fvg_mit, false);
   ArrayInitialize(g_ob_mit,  false);
   ArrayInitialize(g_fvg_dir, 0);
   ArrayInitialize(g_ob_dir,  0);
   ArrayInitialize(g_fvg_top, 0); ArrayInitialize(g_fvg_btm, 0);
   ArrayInitialize(g_ob_top,  0); ArrayInitialize(g_ob_btm,  0);

   if(InpDashboard) CreateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  { ObjectsDeleteAll(0, g_pfx); }

//+------------------------------------------------------------------+
//  HELPERS STRUCTURE
//+------------------------------------------------------------------+
bool IsSwingHigh(const int i, const double &h[], const int total, const int n)
  {
   if(i < n || i + n >= total) return false;
   for(int k=1;k<=n;k++) if(h[i]<=h[i-k]||h[i]<=h[i+k]) return false;
   return true;
  }
bool IsSwingLow(const int i, const double &l[], const int total, const int n)
  {
   if(i < n || i + n >= total) return false;
   for(int k=1;k<=n;k++) if(l[i]>=l[i-k]||l[i]>=l[i+k]) return false;
   return true;
  }

//--- ATR approx pour filtre FVG auto
double ATR_approx(const int i, const double &h[], const double &l[], const double &c[], const int p)
  {
   if(i < p) return 1.0;
   double atr = 0;
   for(int k=1;k<=p;k++)
     atr += MathMax(h[i-k+1], c[i-k]) - MathMin(l[i-k+1], c[i-k]);
   return atr / p;
  }

//+------------------------------------------------------------------+
//  DESSIN OBJETS
//+------------------------------------------------------------------+
void DrawLine(const string name, const datetime t1, const double p1,
              const datetime t2, const double p2, const color clr,
              const int width=1, const ENUM_LINE_STYLE style=STYLE_SOLID)
  {
   string n = g_pfx + name;
   if(ObjectFind(0,n)>=0) ObjectDelete(0,n);
   ObjectCreate(0, n, OBJ_TREND, 0, t1, p1, t2, p2);
   ObjectSetInteger(0,n,OBJPROP_COLOR,    clr);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,    width);
   ObjectSetInteger(0,n,OBJPROP_STYLE,    style);
   ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_BACK,     false);
  }

void DrawLabel(const string name, const datetime t, const double p,
               const string txt, const color clr, const int anchor=ANCHOR_BOTTOM)
  {
   string n = g_pfx + name;
   if(ObjectFind(0,n)>=0) ObjectDelete(0,n);
   ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,n, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,n, OBJPROP_FONTSIZE,  8);
   ObjectSetString(0, n, OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,n, OBJPROP_ANCHOR,    anchor);
   ObjectSetInteger(0,n, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n, OBJPROP_BACK,      false);
  }

void DrawRect(const string name, const datetime t1, const double hi,
              const datetime t2, const double lo, const color clr,
              const color bg, const ENUM_LINE_STYLE style=STYLE_SOLID)
  {
   string n = g_pfx + name;
   if(ObjectFind(0,n)>=0) ObjectDelete(0,n);
   ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0,n,OBJPROP_COLOR,      clr);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0,n,OBJPROP_STYLE,      style);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,      1);
   ObjectSetInteger(0,n,OBJPROP_FILL,       true);
   ObjectSetInteger(0,n,OBJPROP_BACK,       true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//  OnCalculate PRINCIPAL
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
   int minReq = MathMax(InpSwing, InpInternal) * 2 + InpPD_Len + 10;
   if(rates_total < minReq) return 0;

   int start = (prev_calculated == 0) ? minReq : MathMax(prev_calculated-1, minReq);
   if(start >= rates_total) return rates_total;

   // Sur recalcul complet on remet les etats a zero
   if(prev_calculated == 0)
     {
      g_swing_trend=0; g_int_trend=0;
      g_swing_top=0; g_swing_btm=DBL_MAX;
      g_int_top=0;   g_int_btm=DBL_MAX;
      g_top_x=-1; g_btm_x=-1; g_itop_x=-1; g_ibtm_x=-1;
      g_top_cross=false; g_btm_cross=false;
      g_itop_cross=false; g_ibtm_cross=false;
      g_fvg_count=0; g_ob_count=0;
      g_lastBar=0;
      g_cnt_bos_bull=0; g_cnt_bos_bear=0;
      g_cnt_choch_bull=0; g_cnt_choch_bear=0;
      g_cnt_fvg_bull=0; g_cnt_fvg_bear=0;
     }

   for(int i = start; i < rates_total; i++)
     {
      BufBuy[i]  = EMPTY_VALUE;
      BufSell[i] = EMPTY_VALUE;
      if(i < minReq) continue;

      int half = rates_total - InpSwing;

      //================================================================
      //  1. SWING STRUCTURE (HH HL LH LL + BOS / CHoCH)
      //================================================================
      if(i < half)
        {
         // Nouveau Swing High confirme
         if(IsSwingHigh(i, high, rates_total, InpSwing))
           {
            if(InpShowSwing)
               DrawLabel("SH_"+IntegerToString(i), time[i], high[i]+_Point*50,
                         "HH", (high[i]>g_swing_top)?clrLimeGreen:clrOrangeRed,
                         ANCHOR_BOTTOM);
            g_top_x    = i;
            g_top_cross= true;
            if(high[i] > g_swing_top) g_swing_top = high[i];
           }

         // Nouveau Swing Low confirme
         if(IsSwingLow(i, low, rates_total, InpSwing))
           {
            if(InpShowSwing)
               DrawLabel("SL_"+IntegerToString(i), time[i], low[i]-_Point*50,
                         "LL", (low[i]<g_swing_btm)?clrOrangeRed:clrLimeGreen,
                         ANCHOR_TOP);
            g_btm_x    = i;
            g_btm_cross= true;
            if(low[i] < g_swing_btm) g_swing_btm = low[i];
           }

         // BOS / CHoCH Bullish : close depasse le dernier swing top
         if(g_top_cross && g_top_x >= 0 && close[i] > g_swing_top && g_swing_top > 0)
           {
            bool choch = (g_swing_trend < 0); // CHoCH si tendance etait bearish
            string lbl = choch ? "CHoCH" : "BOS";
            color  clr = choch ? clrMagenta : clrDeepSkyBlue;
            if(InpShowSwing)
              {
               DrawLine("SBOS_B_"+IntegerToString(i),
                        time[g_top_x], g_swing_top, time[i], g_swing_top, clr, 2);
               DrawLabel("SBOS_BL_"+IntegerToString(i), time[i], g_swing_top+_Point*30,
                         lbl, clr, ANCHOR_BOTTOM);
              }
            g_swing_trend = 1;
            g_top_cross   = false;
            if(choch) { g_cnt_choch_bull++;
               if(InpAlertCHoCH) DoAlert("CHoCH BULL", close[i], time[i]); }
            else      { g_cnt_bos_bull++;
               if(InpAlertBOS)   DoAlert("BOS BULL",   close[i], time[i]); }

            // OB associe au BOS bullish : derniere bougie baissiere avant le BOS
            if(InpShowOB || InpShowIOB) AddOB_Bull(i, open, close, high, low, time, rates_total);
           }

         // BOS / CHoCH Bearish
         if(g_btm_cross && g_btm_x >= 0 && close[i] < g_swing_btm && g_swing_btm < DBL_MAX)
           {
            bool choch = (g_swing_trend > 0);
            string lbl = choch ? "CHoCH" : "BOS";
            color  clr = choch ? clrMagenta : clrOrangeRed;
            if(InpShowSwing)
              {
               DrawLine("SBOS_S_"+IntegerToString(i),
                        time[g_btm_x], g_swing_btm, time[i], g_swing_btm, clr, 2);
               DrawLabel("SBOS_SL_"+IntegerToString(i), time[i], g_swing_btm-_Point*30,
                         lbl, clr, ANCHOR_TOP);
              }
            g_swing_trend = -1;
            g_btm_cross   = false;
            if(choch) { g_cnt_choch_bear++;
               if(InpAlertCHoCH) DoAlert("CHoCH BEAR", close[i], time[i]); }
            else      { g_cnt_bos_bear++;
               if(InpAlertBOS)   DoAlert("BOS BEAR",   close[i], time[i]); }

            if(InpShowOB || InpShowIOB) AddOB_Bear(i, open, close, high, low, time, rates_total);
           }
        }

      //================================================================
      //  2. INTERNAL STRUCTURE (BOS / CHoCH internes, echelle plus petite)
      //================================================================
      if(i < rates_total - InpInternal)
        {
         if(IsSwingHigh(i, high, rates_total, InpInternal))
           {
            g_itop_x    = i;
            g_itop_cross= true;
            if(high[i] > g_int_top) g_int_top = high[i];
           }
         if(IsSwingLow(i, low, rates_total, InpInternal))
           {
            g_ibtm_x    = i;
            g_ibtm_cross= true;
            if(low[i] < g_int_btm) g_int_btm = low[i];
           }

         if(g_itop_cross && g_itop_x >= 0 && close[i] > g_int_top && g_int_top > 0)
           {
            bool choch = (g_int_trend < 0);
            string lbl = choch ? "CHoCH" : "BOS";
            color  clr = choch ? C'220,130,255' : C'100,200,255';
            if(InpShowInternal)
              {
               DrawLine("IBOS_B_"+IntegerToString(i),
                        time[g_itop_x], g_int_top, time[i], g_int_top,
                        clr, 1, STYLE_DOT);
               DrawLabel("IBOS_BL_"+IntegerToString(i),
                         time[i], g_int_top+_Point*20, lbl, clr, ANCHOR_BOTTOM);
              }
            g_int_trend  = 1;
            g_itop_cross = false;
           }

         if(g_ibtm_cross && g_ibtm_x >= 0 && close[i] < g_int_btm && g_int_btm < DBL_MAX)
           {
            bool choch = (g_int_trend > 0);
            string lbl = choch ? "CHoCH" : "BOS";
            color  clr = choch ? C'255,130,200' : C'255,150,100';
            if(InpShowInternal)
              {
               DrawLine("IBOS_S_"+IntegerToString(i),
                        time[g_ibtm_x], g_int_btm, time[i], g_int_btm,
                        clr, 1, STYLE_DOT);
               DrawLabel("IBOS_SL_"+IntegerToString(i),
                         time[i], g_int_btm-_Point*20, lbl, clr, ANCHOR_TOP);
              }
            g_int_trend  = -1;
            g_ibtm_cross = false;
           }
        }

      //================================================================
      //  3. FAIR VALUE GAPS
      //================================================================
      if(InpShowFVG && i >= 2 && i < rates_total - 1)
        {
         double atr = InpFVG_Auto ? ATR_approx(i, high, low, close, 14) : 0;
         double minFVG = InpFVG_Auto ? atr * 0.1 : 0;

         // FVG Bullish : high[i-2] < low[i]
         double fvgBullGap = low[i] - high[i-2];
         if(fvgBullGap > minFVG && fvgBullGap > 0)
           {
            int idx = g_fvg_count % MAX_FVG;
            g_fvg_top[idx] = low[i];
            g_fvg_btm[idx] = high[i-2];
            g_fvg_t1[idx]  = time[i-1];
            g_fvg_t2[idx]  = time[MathMin(i+InpFVG_Extend, rates_total-1)];
            g_fvg_dir[idx] = 1;
            g_fvg_mit[idx] = false;
            DrawRect("FVG_B_"+IntegerToString(i),
                     g_fvg_t1[idx], g_fvg_top[idx],
                     g_fvg_t2[idx], g_fvg_btm[idx],
                     C'52,121,245', C'15,40,90', STYLE_SOLID);
            g_fvg_count++;
            g_cnt_fvg_bull++;
            if(InpAlertFVG) DoAlert("FVG BULL", close[i], time[i]);
           }

         // FVG Bearish : low[i-2] > high[i]
         double fvgBearGap = low[i-2] - high[i];
         if(fvgBearGap > minFVG && fvgBearGap > 0)
           {
            int idx = g_fvg_count % MAX_FVG;
            g_fvg_top[idx] = low[i-2];
            g_fvg_btm[idx] = high[i];
            g_fvg_t1[idx]  = time[i-1];
            g_fvg_t2[idx]  = time[MathMin(i+InpFVG_Extend, rates_total-1)];
            g_fvg_dir[idx] = -1;
            g_fvg_mit[idx] = false;
            DrawRect("FVG_S_"+IntegerToString(i),
                     g_fvg_t1[idx], g_fvg_top[idx],
                     g_fvg_t2[idx], g_fvg_btm[idx],
                     C'247,124,128', C'90,15,20', STYLE_SOLID);
            g_fvg_count++;
            g_cnt_fvg_bear++;
            if(InpAlertFVG) DoAlert("FVG BEAR", close[i], time[i]);
           }
        }

      //================================================================
      //  4. MITIGATION DES FVG
      //================================================================
      for(int f=0; f<MathMin(g_fvg_count, MAX_FVG); f++)
        {
         if(g_fvg_mit[f]) continue;
         if(g_fvg_dir[f]==1 && low[i] < g_fvg_btm[f])  // prix rentre dans FVG bull
           { g_fvg_mit[f]=true; } // on pourrait griser la zone ici
         if(g_fvg_dir[f]==-1 && high[i] > g_fvg_top[f])
           { g_fvg_mit[f]=true; }
        }

      //================================================================
      //  5. EQUAL HIGHS / EQUAL LOWS (EQH / EQL)
      //================================================================
      if(InpShowEQ && i >= InpEQ_Bars + 1)
        {
         // EQH : deux swing highs proches
         if(IsSwingHigh(i, high, rates_total, InpSwing))
           {
            for(int j=i-InpSwing-1; j>=MathMax(0,i-InpSwing*3); j--)
              {
               if(IsSwingHigh(j, high, rates_total, InpSwing))
                 {
                  if(MathAbs(high[i]-high[j]) <= InpEQ_Thresh)
                    {
                     DrawLine("EQH_"+IntegerToString(i),
                              time[j], high[j], time[i], high[i],
                              clrOrangeRed, 1, STYLE_DOT);
                     DrawLabel("EQH_L_"+IntegerToString(i),
                               time[i], high[i]+_Point*40, "EQH",
                               clrOrangeRed, ANCHOR_BOTTOM);
                    }
                  break;
                 }
              }
           }
         // EQL
         if(IsSwingLow(i, low, rates_total, InpSwing))
           {
            for(int j=i-InpSwing-1; j>=MathMax(0,i-InpSwing*3); j--)
              {
               if(IsSwingLow(j, low, rates_total, InpSwing))
                 {
                  if(MathAbs(low[i]-low[j]) <= InpEQ_Thresh)
                    {
                     DrawLine("EQL_"+IntegerToString(i),
                              time[j], low[j], time[i], low[i],
                              clrDeepSkyBlue, 1, STYLE_DOT);
                     DrawLabel("EQL_L_"+IntegerToString(i),
                               time[i], low[i]-_Point*40, "EQL",
                               clrDeepSkyBlue, ANCHOR_TOP);
                    }
                  break;
                 }
              }
           }
        }

      //================================================================
      //  6. PREMIUM / DISCOUNT ZONES
      //================================================================
      if(InpShowPD && i >= InpPD_Len && i % 20 == 0) // mise a jour tous les 20 bars
        {
         double hi = high[ArrayMaximum(high, i-InpPD_Len+1, InpPD_Len)];
         double lo = low[ArrayMinimum(low,   i-InpPD_Len+1, InpPD_Len)];
         double mid = (hi + lo) / 2.0;
         double ext = time[MathMin(i+40, rates_total-1)];

         // Zone Premium (au dessus du milieu)
         DrawRect("PD_PREM_"+IntegerToString(i),
                  time[i-20], hi, (datetime)ext, mid,
                  C'247,124,128', C'60,10,15', STYLE_DOT);
         // Zone Discount (en dessous)
         DrawRect("PD_DISC_"+IntegerToString(i),
                  time[i-20], mid, (datetime)ext, lo,
                  C'52,121,245', C'10,30,60', STYLE_DOT);
        }

      //================================================================
      //  7. MISE A JOUR OB (extension + mitigation)
      //================================================================
      UpdateOBs(i, time, high, low, close, rates_total);

      //================================================================
      //  8. SIGNAL BUY / SELL
      //================================================================
      if(!InpGenSignals) continue;
      if((i - g_lastBar) < InpCooldown) continue;

      // Filtre session
      bool inSession = true;
      if(InpUseSession)
        {
         MqlDateTime dt; TimeToStruct(time[i], dt);
         int h = dt.hour;
         inSession = (h>=InpLondon_Start && h<InpLondon_End) ||
                     (h>=InpNY_Start     && h<InpNY_End);
        }
      if(!inSession) continue;

      // Confluences pour signal BUY
      bool hasBOSbull  = (g_swing_trend == 1);
      bool hasIntBull  = (g_int_trend   == 1);
      bool hasFVGbull  = false;
      bool hasOBbull   = false;
      bool inDiscount  = false;

      // Prix dans un FVG bullish non mitige
      for(int f=0; f<MathMin(g_fvg_count, MAX_FVG); f++)
        if(!g_fvg_mit[f] && g_fvg_dir[f]==1 &&
           close[i]>=g_fvg_btm[f] && close[i]<=g_fvg_top[f])
          { hasFVGbull=true; break; }

      // Prix dans un OB bullish
      for(int o=0; o<MathMin(g_ob_count, MAX_OB); o++)
        if(!g_ob_mit[o] && g_ob_dir[o]==1 &&
           close[i]>=g_ob_btm[o] && close[i]<=g_ob_top[o])
          { hasOBbull=true; break; }

      // Zone Discount
      if(i >= InpPD_Len)
        {
         double hi = high[ArrayMaximum(high, i-InpPD_Len+1, InpPD_Len)];
         double lo = low[ArrayMinimum(low,   i-InpPD_Len+1, InpPD_Len)];
         double mid = (hi+lo)/2.0;
         inDiscount = (close[i] < mid);
        }

      bool buySignal = hasBOSbull && hasIntBull && inDiscount &&
                       (!InpNeedFVG || hasFVGbull) &&
                       (!InpNeedOB  || hasOBbull) &&
                       (close[i] > open[i]); // bougie verte

      // Confluences SELL
      bool hasBOSbear = (g_swing_trend == -1);
      bool hasIntBear = (g_int_trend   == -1);
      bool hasFVGbear = false;
      bool hasOBbear  = false;
      bool inPremium  = false;

      for(int f=0; f<MathMin(g_fvg_count, MAX_FVG); f++)
        if(!g_fvg_mit[f] && g_fvg_dir[f]==-1 &&
           close[i]<=g_fvg_top[f] && close[i]>=g_fvg_btm[f])
          { hasFVGbear=true; break; }

      for(int o=0; o<MathMin(g_ob_count, MAX_OB); o++)
        if(!g_ob_mit[o] && g_ob_dir[o]==-1 &&
           close[i]<=g_ob_top[o] && close[i]>=g_ob_btm[o])
          { hasOBbear=true; break; }

      if(i >= InpPD_Len)
        {
         double hi = high[ArrayMaximum(high, i-InpPD_Len+1, InpPD_Len)];
         double lo = low[ArrayMinimum(low,   i-InpPD_Len+1, InpPD_Len)];
         double mid = (hi+lo)/2.0;
         inPremium = (close[i] > mid);
        }

      bool sellSignal = hasBOSbear && hasIntBear && inPremium &&
                        (!InpNeedFVG || hasFVGbear) &&
                        (!InpNeedOB  || hasOBbear) &&
                        (close[i] < open[i]); // bougie rouge

      if(buySignal)
        {
         BufBuy[i] = low[i] - _Point * 150;
         g_lastBar = i;
         g_last_signal = "BUY @ "+TimeToString(time[i], TIME_MINUTES);
         g_last_signal_clr = clrDeepSkyBlue;
         if(InpAlertSignal) DoAlert("SIGNAL BUY  [BOS+OB+FVG+Discount]", close[i], time[i]);
        }
      else if(sellSignal)
        {
         BufSell[i] = high[i] + _Point * 150;
         g_lastBar  = i;
         g_last_signal = "SELL @ "+TimeToString(time[i], TIME_MINUTES);
         g_last_signal_clr = clrOrangeRed;
         if(InpAlertSignal) DoAlert("SIGNAL SELL [BOS+OB+FVG+Premium]", close[i], time[i]);
        }
     }

   if(InpDashboard && rates_total > 1)
      UpdateDashboard(rates_total, time, close, high, low);

   return rates_total;
  }

//+------------------------------------------------------------------+
//  AJOUTER ORDER BLOCK BULLISH
//+------------------------------------------------------------------+
void AddOB_Bull(const int i, const double &open[], const double &close[],
                const double &high[], const double &low[],
                const datetime &time[], const int total)
  {
   // Derniere bougie baissiere avant le BOS = OB bullish
   for(int j=i-1; j>=MathMax(0,i-InpSwing*3); j--)
     {
      if(close[j] < open[j]) // bougie rouge
        {
         int idx = g_ob_count % MAX_OB;
         g_ob_top[idx] = open[j];
         g_ob_btm[idx] = close[j];
         g_ob_t1[idx]  = time[j];
         g_ob_t2[idx]  = time[MathMin(i+20, total-1)];
         g_ob_dir[idx] = 1;
         g_ob_mit[idx] = false;
         if(InpShowOB)
            DrawRect("OB_B_"+IntegerToString(i),
                     g_ob_t1[idx], g_ob_top[idx],
                     g_ob_t2[idx], g_ob_btm[idx],
                     C'52,121,245', C'10,30,80');
         g_ob_count++;
         if(InpAlertOB) DoAlert("Order Block BULL cree", g_ob_top[idx], g_ob_t1[idx]);
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//  AJOUTER ORDER BLOCK BEARISH
//+------------------------------------------------------------------+
void AddOB_Bear(const int i, const double &open[], const double &close[],
                const double &high[], const double &low[],
                const datetime &time[], const int total)
  {
   for(int j=i-1; j>=MathMax(0,i-InpSwing*3); j--)
     {
      if(close[j] > open[j]) // bougie verte
        {
         int idx = g_ob_count % MAX_OB;
         g_ob_top[idx] = close[j];
         g_ob_btm[idx] = open[j];
         g_ob_t1[idx]  = time[j];
         g_ob_t2[idx]  = time[MathMin(i+20, total-1)];
         g_ob_dir[idx] = -1;
         g_ob_mit[idx] = false;
         if(InpShowOB)
            DrawRect("OB_S_"+IntegerToString(i),
                     g_ob_t1[idx], g_ob_top[idx],
                     g_ob_t2[idx], g_ob_btm[idx],
                     C'247,124,128', C'80,10,15');
         g_ob_count++;
         if(InpAlertOB) DoAlert("Order Block BEAR cree", g_ob_btm[idx], g_ob_t1[idx]);
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//  MISE A JOUR OB (extension + mitigation)
//+------------------------------------------------------------------+
void UpdateOBs(const int i, const datetime &time[],
               const double &high[], const double &low[],
               const double &close[], const int total)
  {
   for(int o=0; o<MathMin(g_ob_count, MAX_OB); o++)
     {
      if(g_ob_mit[o]) continue;
      // Extension de la boite
      g_ob_t2[o] = time[MathMin(i+1, total-1)];
      string sfx = (g_ob_dir[o]==1) ? "B_" : "S_";
      // Mitigation : prix entre dans l OB
      if(g_ob_dir[o]==1 && low[i] < g_ob_btm[o])
        {
         g_ob_mit[o] = true;
         if(InpOB_HlightMit)
            DrawRect("OB_"+sfx+IntegerToString((int)g_ob_t1[o]),
                     g_ob_t1[o], g_ob_top[o], g_ob_t2[o], g_ob_btm[o],
                     C'99,99,99', C'30,30,30');
        }
      if(g_ob_dir[o]==-1 && high[i] > g_ob_top[o])
        {
         g_ob_mit[o] = true;
         if(InpOB_HlightMit)
            DrawRect("OB_"+sfx+IntegerToString((int)g_ob_t1[o]),
                     g_ob_t1[o], g_ob_top[o], g_ob_t2[o], g_ob_btm[o],
                     C'99,99,99', C'30,30,30');
        }
     }
  }

//+------------------------------------------------------------------+
//  ALERTE
//+------------------------------------------------------------------+
void DoAlert(const string msg, const double price, const datetime t)
  {
   if(t == g_lastAlert) return;
   string full = StringFormat("[SMC] %s | %s | %.2f | %s",
                              _Symbol, msg, price,
                              TimeToString(t, TIME_MINUTES));
   if(InpAlertBOS || InpAlertCHoCH || InpAlertOB || InpAlertFVG || InpAlertSignal)
      Alert(full);
   if(InpAlertPush) SendNotification(full);
   g_lastAlert = t;
  }

//+------------------------------------------------------------------+
//  WIN RATE
//+------------------------------------------------------------------+
string CalcWinRate(const int rates_total, const double &close[])
  {
   int wins=0, total=0;
   int lb=MathMin(InpWinBars, rates_total-2);
   int si=rates_total-1-lb; if(si<1) si=1;
   for(int i=si; i<rates_total-1; i++)
     {
      double mv=close[i+1]-close[i];
      if(BufBuy[i] !=EMPTY_VALUE){total++;if(mv>0)wins++;}
      if(BufSell[i]!=EMPTY_VALUE){total++;if(mv<0)wins++;}
     }
   if(total==0) return "-- (0 signaux)";
   return StringFormat("%.0f%%  [%d/%d]",(double)wins/total*100.0,wins,total);
  }

//+------------------------------------------------------------------+
//  DASHBOARD
//+------------------------------------------------------------------+
void MkLbl(const string n,const string t,const int x,const int y,
           const color c,const int sz=9,const string f="Arial")
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n,OBJPROP_FONT,      f);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,  sz);
   ObjectSetInteger(0,n,OBJPROP_COLOR,     c);
   ObjectSetString(0, n,OBJPROP_TEXT,      t);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,    true);
  }
void MkRect(const string n,const int x,const int y,const int w,const int h)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,      w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,      h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,    C'6,8,18');
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n,OBJPROP_COLOR,      C'40,40,100');
   ObjectSetInteger(0,n,OBJPROP_WIDTH,      1);
   ObjectSetInteger(0,n,OBJPROP_BACK,       true);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,     true);
  }

void CreateDashboard()
  {
   int x=InpDashX, y=InpDashY;
   string p=g_pfx+"D_";
   MkRect(p+"bg",x-6,y-6,300,320);
   MkLbl(p+"title","  SMC GOLD SCALPER",              x,y,clrGold,11,"Arial Bold");
   y+=18;MkLbl(p+"sub","  LuxAlgo Style | ICT Concepts",x,y,C'100,100,160',8);
   y+=14;MkLbl(p+"s0","-----------------------------------",x,y,C'40,40,90',8);
   y+=12;MkLbl(p+"sym","Symbole  : "+_Symbol,           x,y,clrSilver,9);
   y+=13;MkLbl(p+"tf", "Timeframe: M5",                 x,y,clrSilver,9);
   y+=14;MkLbl(p+"s1","-----------------------------------",x,y,C'40,40,90',8);
   y+=12;MkLbl(p+"wrl","Win Rate ("+IntegerToString(InpWinBars)+" bougies):",x,y,clrLightSkyBlue,9,"Arial Bold");
   y+=14;MkLbl(p+"wrv","Calcul...",                     x,y,clrYellow,10,"Arial Bold");
   y+=18;MkLbl(p+"s2","-----------------------------------",x,y,C'40,40,90',8);
   y+=12;MkLbl(p+"str","Structure : --",                x,y,clrSilver,9);
   y+=13;MkLbl(p+"ist","Int.Struct: --",                x,y,clrSilver,9);
   y+=13;MkLbl(p+"ob", "Order Blk : --",               x,y,clrSilver,9);
   y+=13;MkLbl(p+"fvg","FVG       : --",               x,y,clrSilver,9);
   y+=13;MkLbl(p+"pd", "Zone      : --",               x,y,clrSilver,9);
   y+=13;MkLbl(p+"cnt","Stats     : --",               x,y,clrSilver,9);
   y+=16;MkLbl(p+"s3","-----------------------------------",x,y,C'40,40,90',8);
   y+=12;MkLbl(p+"sig","Signal    : --",               x,y,clrSilver,9);
   y+=13;MkLbl(p+"ses","Session   : --",               x,y,clrSilver,9);
   y+=15;MkLbl(p+"ver","SMC v1.0 | BOS+CHoCH+OB+FVG+EQH", x,y,C'60,60,80',8);
   ChartRedraw();
  }

void UpdateDashboard(const int rates_total, const datetime &time[],
                     const double &close[], const double &high[], const double &low[])
  {
   int last=rates_total-1; if(last<5) return;
   string p=g_pfx+"D_";

   // Win Rate
   string wr=CalcWinRate(rates_total,close);
   double wrN=StringToDouble(StringSubstr(wr,0,3));
   color  wrC=(wrN>=60)?clrLimeGreen:(wrN>=50)?clrYellow:clrOrangeRed;
   ObjectSetString(0, p+"wrv",OBJPROP_TEXT, wr);
   ObjectSetInteger(0,p+"wrv",OBJPROP_COLOR,wrC);

   // Structure
   string strS=(g_swing_trend==1)?"BULL [BOS/CHoCH haussier]":
               (g_swing_trend==-1)?"BEAR [BOS/CHoCH baissier]":"NEUTRE";
   color  strC=(g_swing_trend==1)?clrLimeGreen:(g_swing_trend==-1)?clrOrangeRed:clrSilver;
   ObjectSetString(0, p+"str",OBJPROP_TEXT, "Structure : "+strS);
   ObjectSetInteger(0,p+"str",OBJPROP_COLOR,strC);

   // Internal
   string istS=(g_int_trend==1)?"BULL interne":(g_int_trend==-1)?"BEAR interne":"NEUTRE";
   color  istC=(g_int_trend==1)?clrLimeGreen:(g_int_trend==-1)?clrOrangeRed:clrSilver;
   ObjectSetString(0, p+"ist",OBJPROP_TEXT, "Int.Struct: "+istS);
   ObjectSetInteger(0,p+"ist",OBJPROP_COLOR,istC);

   // OB actif
   int obActif=0;
   for(int o=0;o<MathMin(g_ob_count,MAX_OB);o++) if(!g_ob_mit[o]) obActif++;
   color obC=(obActif>0)?clrYellow:clrSilver;
   ObjectSetString(0, p+"ob",OBJPROP_TEXT,
      StringFormat("Order Blk : %d actif(s)  [%d total]",obActif,g_ob_count));
   ObjectSetInteger(0,p+"ob",OBJPROP_COLOR,obC);

   // FVG actif
   int fvgActif=0;
   for(int f=0;f<MathMin(g_fvg_count,MAX_FVG);f++) if(!g_fvg_mit[f]) fvgActif++;
   color fvgC=(fvgActif>0)?clrYellow:clrSilver;
   ObjectSetString(0, p+"fvg",OBJPROP_TEXT,
      StringFormat("FVG       : %d actif(s)  [B:%d S:%d]",
                   fvgActif,g_cnt_fvg_bull,g_cnt_fvg_bear));
   ObjectSetInteger(0,p+"fvg",OBJPROP_COLOR,fvgC);

   // Premium / Discount
   string pdS="--"; color pdC=clrSilver;
   if(last>=InpPD_Len)
     {
      double hi=high[ArrayMaximum(high,last-InpPD_Len+1,InpPD_Len)];
      double lo=low[ArrayMinimum(low,  last-InpPD_Len+1,InpPD_Len)];
      double mid=(hi+lo)/2.0;
      if(close[last]>mid)   { pdS="PREMIUM [SELL zone]"; pdC=clrOrangeRed; }
      else if(close[last]<mid){ pdS="DISCOUNT [BUY zone]";pdC=clrLimeGreen; }
      else                   { pdS="EQUILIBRE";           pdC=clrYellow; }
     }
   ObjectSetString(0, p+"pd",OBJPROP_TEXT, "Zone      : "+pdS);
   ObjectSetInteger(0,p+"pd",OBJPROP_COLOR,pdC);

   // Stats
   ObjectSetString(0, p+"cnt",OBJPROP_TEXT,
      StringFormat("Stats     : BOS B:%d S:%d  CHoCH B:%d S:%d",
                   g_cnt_bos_bull,g_cnt_bos_bear,g_cnt_choch_bull,g_cnt_choch_bear));
   ObjectSetInteger(0,p+"cnt",OBJPROP_COLOR,clrSilver);

   // Dernier signal
   ObjectSetString(0, p+"sig",OBJPROP_TEXT, "Signal    : "+g_last_signal);
   ObjectSetInteger(0,p+"sig",OBJPROP_COLOR,g_last_signal_clr);

   // Session
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int hr=dt.hour,mn=dt.min;
   string sS="Hors session"; color sC=clrOrangeRed;
   if(hr>=InpLondon_Start&&hr<InpLondon_End)
     { bool isO=(hr*60+mn<InpLondon_Start*60+45);
       sS=isO?"LONDRES [OUVERTURE ★]":"LONDRES [ACTIVE]"; sC=isO?clrGold:clrLimeGreen; }
   else if(hr>=InpNY_Start&&hr<InpNY_End)
     { bool isO=(hr*60+mn<InpNY_Start*60+45);
       sS=isO?"NEW YORK [OUVERTURE ★]":"NEW YORK [ACTIVE]"; sC=isO?clrGold:clrLimeGreen; }
   ObjectSetString(0, p+"ses",OBJPROP_TEXT, "Session   : "+sS);
   ObjectSetInteger(0,p+"ses",OBJPROP_COLOR,sC);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
//|  FIN - SMC_Gold_Scalper v1.0                                     |
//+------------------------------------------------------------------+
