//+------------------------------------------------------------------+
//|                                             Supertrend_I.mq5    |
//|                    Converti depuis Pine Script v5                |
//|                                                                  |
//|  LOGIQUE :                                                       |
//|    - Bandes basees sur ATR (ou SMA du TR)                       |
//|    - Ratchet : les bandes ne reculent jamais                    |
//|    - Trend +1 = bull (ligne verte sous le prix)                 |
//|    - Trend -1 = bear (ligne rouge au-dessus)                    |
//|    - Filtre anti-doublon : BUY/SELL alternent obligatoirement   |
//|                                                                  |
//|  BUFFERS :                                                       |
//|    0 = ligne verte (bull)                                       |
//|    1 = ligne rouge (bear)                                       |
//+------------------------------------------------------------------+
#property copyright   "Supertrend_I MQL5 v1.0"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

// Ligne bull (verte)
#property indicator_label1  "Supertrend Bull"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Ligne bear (rouge)
#property indicator_label2  "Supertrend Bear"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//+------------------------------------------------------------------+
//  INPUTS
//+------------------------------------------------------------------+
input group "=== Supertrend I ==="
input int    InpPeriod     = 14;    // ATR Period
input double InpMultiplier = 3.0;   // ATR Multiplier
input bool   InpUseATR     = true;  // true=ATR | false=SMA du TR
input bool   InpShowSig    = true;  // Afficher fleches BUY/SELL

//+------------------------------------------------------------------+
//  BUFFERS
//+------------------------------------------------------------------+
double BufBull[];   // buffer 0 : ligne verte (trend = +1)
double BufBear[];   // buffer 1 : ligne rouge (trend = -1)
double BufUp[];     // buffer 2 : bande basse ratchet (calcul interne)
double BufDn[];     // buffer 3 : bande haute ratchet (calcul interne)

//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BufBull, INDICATOR_DATA);
   SetIndexBuffer(1, BufBear, INDICATOR_DATA);
   SetIndexBuffer(2, BufUp,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, BufDn,   INDICATOR_CALCULATIONS);

   ArraySetAsSeries(BufBull, true);
   ArraySetAsSeries(BufBear, true);
   ArraySetAsSeries(BufUp,   true);
   ArraySetAsSeries(BufDn,   true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);

   IndicatorSetString(INDICATOR_SHORTNAME,
      StringFormat("Supertrend(%d, %.1f)", InpPeriod, InpMultiplier));

   return INIT_SUCCEEDED;
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
   if(rates_total < InpPeriod + 2) return 0;

   // Travailler en mode series (index 0 = barre la plus recente)
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);

   // Nombre de barres a calculer
   int limit = rates_total - prev_calculated;
   if(prev_calculated == 0)
      limit = rates_total - InpPeriod - 2;
   else
      limit += 1;

   // Calculer le TR pour SMA si besoin
   // ATR calcule manuellement barre par barre

   for(int i = limit; i >= 0; i--)
     {
      // Source hl2
      double src = (high[i] + low[i]) / 2.0;

      // Calcul ATR ou SMA(TR)
      double atr_val = 0;
      if(InpUseATR)
        {
         // ATR = moyenne des True Range sur InpPeriod barres
         double sum_tr = 0;
         for(int k = 0; k < InpPeriod; k++)
           {
            int idx = i + k;
            if(idx + 1 >= rates_total) break;
            double tr = MathMax(high[idx] - low[idx],
                        MathMax(MathAbs(high[idx] - close[idx+1]),
                                MathAbs(low[idx]  - close[idx+1])));
            sum_tr += tr;
           }
         atr_val = sum_tr / InpPeriod;
        }
      else
        {
         // SMA du TR
         double sum_tr = 0;
         for(int k = 0; k < InpPeriod; k++)
           {
            int idx = i + k;
            if(idx + 1 >= rates_total) break;
            double tr = MathMax(high[idx] - low[idx],
                        MathMax(MathAbs(high[idx] - close[idx+1]),
                                MathAbs(low[idx]  - close[idx+1])));
            sum_tr += tr;
           }
         atr_val = sum_tr / InpPeriod;
        }

      if(atr_val <= 0) continue;

      // Bandes brutes
      double up_raw = src - InpMultiplier * atr_val;
      double dn_raw = src + InpMultiplier * atr_val;

      // Ratchet
      double prev_up = (i + 1 < rates_total) ? BufUp[i+1] : up_raw;
      double prev_dn = (i + 1 < rates_total) ? BufDn[i+1] : dn_raw;
      double prev_close = (i + 1 < rates_total) ? close[i+1] : close[i];

      if(prev_up == 0) prev_up = up_raw;
      if(prev_dn == 0) prev_dn = dn_raw;

      BufUp[i] = (prev_close > prev_up) ? MathMax(up_raw, prev_up) : up_raw;
      BufDn[i] = (prev_close < prev_dn) ? MathMin(dn_raw, prev_dn) : dn_raw;
     }

   // --- Calcul du trend et des lignes d affichage ---
   // Necessite une passe separee car trend[i] depend de trend[i+1]

   // Tableau trend temporaire (non-series, index 0 = barre la plus ancienne)
   static int trend[];
   if(ArraySize(trend) != rates_total)
      ArrayResize(trend, rates_total);

   // Remplir en ordre chronologique (de l ancien vers le recent)
   // Index series : 0=recent, rates_total-1=ancien
   // On parcourt du plus ancien au plus recent

   int start = rates_total - 1;  // barre la plus ancienne
   trend[start] = 1;

   for(int i = rates_total - 2; i >= 0; i--)
     {
      double c      = close[i];
      double up_i1  = BufUp[i+1];
      double dn_i1  = BufDn[i+1];

      if(trend[i+1] == -1 && c > dn_i1)
         trend[i] =  1;
      else if(trend[i+1] == 1 && c < up_i1)
         trend[i] = -1;
      else
         trend[i] = trend[i+1];
     }

   // Remplir les buffers d affichage
   for(int i = 0; i < rates_total; i++)
     {
      if(trend[i] == 1)
        {
         BufBull[i] = BufUp[i];
         BufBear[i] = 0.0;        // vide
        }
      else
        {
         BufBull[i] = 0.0;        // vide
         BufBear[i] = BufDn[i];
        }
     }

   // --- Fleches BUY / SELL ---
   if(InpShowSig)
     {
      // Supprimer les anciennes fleches
      ObjectsDeleteAll(0, "ST_SIG_");

      // Anti-doublon
      bool buy_allowed  = true;
      bool sell_allowed = true;

      for(int i = rates_total - 2; i >= 0; i--)
        {
         bool isBuy  = (trend[i] ==  1 && trend[i+1] == -1);
         bool isSell = (trend[i] == -1 && trend[i+1] ==  1);

         if(isBuy && buy_allowed)
           {
            string name = "ST_SIG_BUY_" + IntegerToString(i);
            datetime t  = time[i];
            double   pr = close[i];
            ObjectCreate(0, name, OBJ_ARROW_BUY, 0, t, pr);
            ObjectSetInteger(0, name, OBJPROP_COLOR,  clrLime);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_TOP);
            ObjectSetInteger(0, name, OBJPROP_WIDTH,  2);
            buy_allowed  = false;
            sell_allowed = true;
           }
         else if(isSell && sell_allowed)
           {
            string name = "ST_SIG_SELL_" + IntegerToString(i);
            datetime t  = time[i];
            double   pr = close[i];
            ObjectCreate(0, name, OBJ_ARROW_SELL, 0, t, pr);
            ObjectSetInteger(0, name, OBJPROP_COLOR,  clrRed);
            ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
            ObjectSetInteger(0, name, OBJPROP_WIDTH,  2);
            sell_allowed = false;
            buy_allowed  = true;
           }
        }
     }

   return rates_total;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "ST_SIG_");
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//  FIN — Supertrend_I v1.0
//+------------------------------------------------------------------+
