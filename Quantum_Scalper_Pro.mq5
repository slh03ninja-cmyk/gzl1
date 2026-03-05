//+------------------------------------------------------------------+
//|                                         Quantum_Scalper_Pro.mq5 |
//|                    XAUUSD M1/M5 - Version 3.0                   |
//|  Logique 1 : ALMA+RVOL+RSI (fleches) | Logique 2 : Reversal (triangles) |
//+------------------------------------------------------------------+
#property copyright   "Quantum_Scalper_Pro v3.0"
#property version     "3.00"
#property description "Double logique : Tendance (fleches) + Retournement (triangles)"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   4

//--- Plot 0 : Fleche BUY (Logique 1)
#property indicator_label1  "BUY Trend"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  3

//--- Plot 1 : Fleche SELL (Logique 1)
#property indicator_label2  "SELL Trend"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrOrangeRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  3

//--- Plot 2 : Triangle BUY (Logique 2 Retournement)
#property indicator_label3  "BUY Reversal"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_style3  STYLE_SOLID
#property indicator_width3  4

//--- Plot 3 : Triangle SELL (Logique 2 Retournement)
#property indicator_label4  "SELL Reversal"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_style4  STYLE_SOLID
#property indicator_width4  4

//+------------------------------------------------------------------+
//|  PARAMETRES                                                       |
//+------------------------------------------------------------------+
input group            "=== ALMA ==="
input int              InpALMA_Period   = 25;
input double           InpALMA_Sigma    = 6.0;
input double           InpALMA_Offset   = 0.80;

input group            "=== RSI ==="
input int              InpRSI_Period    = 14;
input int              InpRSI_Signal    = 5;
input int              InpRSI_OB        = 75;
input int              InpRSI_OS        = 25;

input group            "=== RVOL ==="
input int              InpRVOL_Period   = 10;
input double           InpRVOL_Mult     = 2.0;

input group            "=== Filtre Anti-Faux Signaux ==="
input double           InpMinSlope      = 2.0;   // Pente ALMA minimum (points)
input int              InpCooldown      = 5;     // Bougies minimum entre signaux
input double           InpMaxCandleMult = 1.5;   // Taille bougie max vs moyenne

input group            "=== Retournement (Logique 2) ==="
input int              InpSwingBars     = 3;     // Bougies pivot detection
input int              InpRSI_RevBuy    = 35;    // RSI seuil survente retournement
input int              InpRSI_RevSell   = 65;    // RSI seuil surachat retournement
input double           InpMinRange      = 50.0;  // Range minimum bougie retournement (points)
input double           InpVolRevMult    = 1.2;   // Volume minimum retournement

input group            "=== Sessions GMT+0 ==="
input bool             InpUseTimeFilter = true;
input int              InpLondon_Start  = 8;
input int              InpLondon_End    = 12;
input int              InpNewYork_Start = 13;
input int              InpNewYork_End   = 20;

input group            "=== Alertes ==="
input bool             InpAlertSound    = true;
input bool             InpAlertPush     = true;
input bool             InpAlertPopup    = true;

input group            "=== Dashboard ==="
input bool             InpShowDashboard = true;
input int              InpWinRateBars   = 100;
input ENUM_BASE_CORNER InpDashCorner    = CORNER_LEFT_UPPER;
input int              InpDashX         = 15;
input int              InpDashY         = 20;

//+------------------------------------------------------------------+
//|  BUFFERS                                                          |
//+------------------------------------------------------------------+
double BufferBuyTrend[];     // 0 - Fleche BUY  Logique 1
double BufferSellTrend[];    // 1 - Fleche SELL Logique 1
double BufferBuyRev[];       // 2 - Triangle BUY  Logique 2
double BufferSellRev[];      // 3 - Triangle SELL Logique 2
double BufferALMA[];         // 4 - ALMA (calcul)
double BufferRSI[];          // 5 - RSI  (calcul)
double BufferRSISig[];       // 6 - RSI Signal (calcul)
double BufferSlope[];        // 7 - Pente ALMA (calcul)

int      h_RSI          = INVALID_HANDLE;
datetime g_lastAlert    = 0;
int      g_lastSigBar   = 0;
int      g_lastRevBar   = 0;
string   g_pfx          = "QSP_";

//+------------------------------------------------------------------+
//|  OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0,BufferBuyTrend,  INDICATOR_DATA);
   SetIndexBuffer(1,BufferSellTrend, INDICATOR_DATA);
   SetIndexBuffer(2,BufferBuyRev,    INDICATOR_DATA);
   SetIndexBuffer(3,BufferSellRev,   INDICATOR_DATA);
   SetIndexBuffer(4,BufferALMA,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,BufferRSI,       INDICATOR_CALCULATIONS);
   SetIndexBuffer(6,BufferRSISig,    INDICATOR_CALCULATIONS);
   SetIndexBuffer(7,BufferSlope,     INDICATOR_CALCULATIONS);

   //--- Logique 1 : Fleches (233=haut, 234=bas)
   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,-15);
   PlotIndexSetInteger(1,PLOT_ARROW_SHIFT, 15);

   //--- Logique 2 : Triangles (241=triangle haut, 242=triangle bas)
   PlotIndexSetInteger(2,PLOT_ARROW,241);
   PlotIndexSetInteger(3,PLOT_ARROW,242);
   PlotIndexSetInteger(2,PLOT_ARROW_SHIFT,-25);
   PlotIndexSetInteger(3,PLOT_ARROW_SHIFT, 25);

   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(2,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(3,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   ArrayInitialize(BufferBuyTrend, EMPTY_VALUE);
   ArrayInitialize(BufferSellTrend,EMPTY_VALUE);
   ArrayInitialize(BufferBuyRev,   EMPTY_VALUE);
   ArrayInitialize(BufferSellRev,  EMPTY_VALUE);
   ArrayInitialize(BufferRSI,      EMPTY_VALUE);
   ArrayInitialize(BufferRSISig,   EMPTY_VALUE);
   ArrayInitialize(BufferALMA,     0.0);
   ArrayInitialize(BufferSlope,    0.0);

   h_RSI=iRSI(_Symbol,PERIOD_CURRENT,InpRSI_Period,PRICE_CLOSE);
   if(h_RSI==INVALID_HANDLE){Alert("Echec RSI:",GetLastError());return INIT_FAILED;}

   int mb=InpALMA_Period+InpRSI_Period+InpRSI_Signal+InpRVOL_Period+10;
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,mb);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,mb);
   PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,mb);
   PlotIndexSetInteger(3,PLOT_DRAW_BEGIN,mb);

   IndicatorSetString(INDICATOR_SHORTNAME,"QSP v3 [Trend+Reversal]");

   if(InpShowDashboard) CreateDashboard();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//|  OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(h_RSI!=INVALID_HANDLE) IndicatorRelease(h_RSI);
   ObjectsDeleteAll(0,g_pfx);
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
   int minReq=InpALMA_Period+InpRSI_Period+InpRSI_Signal+InpRVOL_Period+10;
   if(rates_total<minReq) return 0;

   // Copie buffer RSI (ordre chronologique)
   double rsi_raw[];
   ArraySetAsSeries(rsi_raw,false);
   int rsiCopied=CopyBuffer(h_RSI,0,0,rates_total,rsi_raw);
   if(rsiCopied<=0) return prev_calculated;

   // FIX : offset robuste entre rates_total et rsiCopied
   int rsiOffset=rates_total-rsiCopied;

   int lookback=500;
   int start=(prev_calculated==0)?minReq:MathMax(minReq,rates_total-lookback);

   //--- Effacement de la fenetre de recalcul
   for(int j=start;j<rates_total;j++)
     {
      BufferBuyTrend[j] =EMPTY_VALUE;
      BufferSellTrend[j]=EMPTY_VALUE;
      BufferBuyRev[j]   =EMPTY_VALUE;
      BufferSellRev[j]  =EMPTY_VALUE;
     }

   //================================================================
   //  BOUCLE PRINCIPALE
   //================================================================
   for(int i=start;i<rates_total;i++)
     {
      if(i<4) continue; // securite index

      //--------------------------------------------------------------
      // CALCUL ALMA + PENTE
      //--------------------------------------------------------------
      double alma=CalcALMA(i,close,rates_total);
      BufferALMA[i] =alma;
      BufferSlope[i]=(i>0)?alma-BufferALMA[i-1]:0;

      //--------------------------------------------------------------
      // CALCUL RSI LISSE (FIX : mapping robuste)
      //--------------------------------------------------------------
      int ri=i-rsiOffset;
      if(ri<1||ri>=rsiCopied)
        {
         BufferRSI[i]   =50.0;
         BufferRSISig[i]=50.0;
         continue;
        }
      BufferRSI[i]=rsi_raw[ri];

      // FIX : seed EMA RSI sur la premiere barre valide
      if(i<=minReq||BufferRSISig[i-1]==EMPTY_VALUE)
        { BufferRSISig[i]=BufferRSI[i]; }
      else
        {
         double k=2.0/(InpRSI_Signal+1.0);
         BufferRSISig[i]=BufferRSI[i]*k+BufferRSISig[i-1]*(1.0-k);
        }

      //--------------------------------------------------------------
      // FILTRE TEMPOREL
      //--------------------------------------------------------------
      bool condTime=true;
      if(InpUseTimeFilter)
        {
         MqlDateTime dt; TimeToStruct(time[i],dt);
         int h=dt.hour;
         condTime=(h>=InpLondon_Start&&h<InpLondon_End)||
                  (h>=InpNewYork_Start&&h<InpNewYork_End);
        }

      //--------------------------------------------------------------
      // CALCUL RVOL
      //--------------------------------------------------------------
      bool condB=false;
      if(i>=InpRVOL_Period)
        {
         double vs=0;
         for(int v=1;v<=InpRVOL_Period;v++) vs+=(double)tick_volume[i-v];
         double va=vs/InpRVOL_Period;
         condB=(va>0)&&((double)tick_volume[i]>=InpRVOL_Mult*va);
        }

      //--------------------------------------------------------------
      // TAILLE BOUGIE (filtre anti-grosse-bougie)
      //--------------------------------------------------------------
      double candleSize=MathAbs(close[i]-open[i]);
      double avgSize=0;
      for(int v=1;v<=10;v++) avgSize+=MathAbs(close[i-v]-open[i-v]);
      avgSize/=10;
      bool condSize=(avgSize>0)&&(candleSize<InpMaxCandleMult*avgSize);

      //==============================================================
      //  LOGIQUE 1 — TREND (fleches bleues/rouges)
      //==============================================================

      //--- ALMA direction stable sur 3 bougies
      double minSlope=InpMinSlope*_Point;
      bool almaOkBuy =(i>2)&&(BufferSlope[i]> minSlope)&&
                      (BufferSlope[i-1]>0)&&(BufferSlope[i-2]>0);
      bool almaOkSell=(i>2)&&(BufferSlope[i]<-minSlope)&&
                      (BufferSlope[i-1]<0)&&(BufferSlope[i-2]<0);
      bool condA_Buy =(close[i]>alma)&&almaOkBuy;
      bool condA_Sell=(close[i]<alma)&&almaOkSell;

      //--- RSI crossover
      double rN=BufferRSI[i],   rP=BufferRSI[i-1];
      double sN=BufferRSISig[i],sP=BufferRSISig[i-1];
      bool rsiBuy =(rP<=sP)&&(rN>sN)&&(rN<InpRSI_OB);
      bool rsiSell=(rP>=sP)&&(rN<sN)&&(rN>InpRSI_OS);

      //--- Confirmation 2 bougies consecutives
      bool candleBuy =(close[i-1]>open[i-1])&&(close[i-2]>open[i-2]);
      bool candleSell=(close[i-1]<open[i-1])&&(close[i-2]<open[i-2]);

      //--- Cooldown entre signaux tendance
      bool condCooldown=(i-g_lastSigBar)>=InpCooldown;

      //--- Signal final Logique 1
      bool buyTrend =condA_Buy &&condB&&rsiBuy &&condTime&&condSize&&condCooldown&&candleBuy;
      bool sellTrend=condA_Sell&&condB&&rsiSell&&condTime&&condSize&&condCooldown&&candleSell;

      if(buyTrend)
        { BufferBuyTrend[i]=low[i]-_Point*150; g_lastSigBar=i; }
      else if(sellTrend)
        { BufferSellTrend[i]=high[i]+_Point*150; g_lastSigBar=i; }

      //==============================================================
      //  LOGIQUE 2 — REVERSAL (triangles verts/magenta)
      //==============================================================

      //--- Swing Low / Swing High detection
      bool isSwingLow=true, isSwingHigh=true;
      for(int s=1;s<=InpSwingBars;s++)
        {
         if(i+s<rates_total)
           {
            if(low[i] >=low[i+s])  isSwingLow =false;
            if(high[i]<=high[i+s]) isSwingHigh=false;
           }
         if(low[i] >=low[i-s])  isSwingLow =false;
         if(high[i]<=high[i-s]) isSwingHigh=false;
        }

      //--- Patterns de bougies de retournement
      double body   =MathAbs(close[i]-open[i]);
      double hiShad =high[i]-MathMax(close[i],open[i]);
      double loShad =MathMin(close[i],open[i])-low[i];
      double range  =high[i]-low[i];
      double minRange=InpMinRange*_Point;

      // Marteau (BUY)
      bool isHammer=(loShad>2.0*body)&&(hiShad<body)&&(range>minRange);
      // Etoile filante (SELL)
      bool isStar  =(hiShad>2.0*body)&&(loShad<body)&&(range>minRange);
      // Engulfing haussier (BUY)
      bool isEngulfBuy =(close[i]> open[i])&&(close[i-1]<open[i-1])&&
                        (close[i]> open[i-1])&&(open[i]<close[i-1]);
      // Engulfing baissier (SELL)
      bool isEngulfSell=(close[i]< open[i])&&(close[i-1]>open[i-1])&&
                        (close[i]< open[i-1])&&(open[i]>close[i-1]);

      //--- RSI en zone de retournement
      bool rsiRevBuy =(BufferRSI[i-1]<InpRSI_RevBuy) &&
                      (BufferRSI[i]>BufferRSI[i-1]);
      bool rsiRevSell=(BufferRSI[i-1]>InpRSI_RevSell)&&
                      (BufferRSI[i]<BufferRSI[i-1]);

      //--- Volume sur retournement
      double vsR=0;
      for(int v=1;v<=10;v++) vsR+=(double)tick_volume[i-v];
      double vaR=vsR/10;
      bool volRev=((double)tick_volume[i]>InpVolRevMult*vaR);

      //--- Cooldown retournement independant
      bool condCooldownRev=(i-g_lastRevBar)>=5;

      //--- Signal final Logique 2
      bool buyRev =isSwingLow &&(isHammer||isEngulfBuy) &&
                   rsiRevBuy &&volRev&&condTime&&condCooldownRev;
      bool sellRev=isSwingHigh&&(isStar  ||isEngulfSell)&&
                   rsiRevSell&&volRev&&condTime&&condCooldownRev;

      if(buyRev)
        { BufferBuyRev[i]=low[i]-_Point*280; g_lastRevBar=i; }
      else if(sellRev)
        { BufferSellRev[i]=high[i]+_Point*280; g_lastRevBar=i; }

      //==============================================================
      //  ALERTES
      //==============================================================
      if(i==rates_total-1&&time[i]!=g_lastAlert)
        {
         string msg=""; string dir="";
         if(buyTrend)       { dir="[TREND] BUY fleche";       msg=StringFormat("[QSP] %s | %s | %.2f",_Symbol,dir,close[i]); }
         else if(sellTrend) { dir="[TREND] SELL fleche";      msg=StringFormat("[QSP] %s | %s | %.2f",_Symbol,dir,close[i]); }
         else if(buyRev)    { dir="[REVERSAL] BUY triangle";  msg=StringFormat("[QSP] %s | %s | %.2f",_Symbol,dir,close[i]); }
         else if(sellRev)   { dir="[REVERSAL] SELL triangle"; msg=StringFormat("[QSP] %s | %s | %.2f",_Symbol,dir,close[i]); }

         if(msg!="")
           {
            if(InpAlertPopup) Alert(msg);
            if(InpAlertSound) PlaySound("alert.wav");
            if(InpAlertPush)  SendNotification(msg);
            g_lastAlert=time[i];
           }
        }
     }

   if(InpShowDashboard&&rates_total>1)
      UpdateDashboard(rates_total,time,open,close,high,low,tick_volume);

   return rates_total;
  }

//+------------------------------------------------------------------+
//|  CalcALMA                                                         |
//+------------------------------------------------------------------+
double CalcALMA(const int idx,const double &price[],const int total)
  {
   int p=InpALMA_Period;
   if(idx<p-1||idx>=total) return price[idx];
   double m=InpALMA_Offset*(p-1);
   double s=p/InpALMA_Sigma;
   double wSum=0,result=0;
   for(int k=0;k<p;k++)
     {
      double w=MathExp(-MathPow(k-m,2)/(2.0*MathPow(s,2)));
      result+=w*price[idx-(p-1-k)];
      wSum+=w;
     }
   return(wSum>0)?result/wSum:price[idx];
  }

//+------------------------------------------------------------------+
//|  CalcWinRate                                                      |
//+------------------------------------------------------------------+
string CalcWinRate(const int rates_total,const double &close[])
  {
   int wT=0,tT=0,wR=0,tR=0;
   int lb=MathMin(InpWinRateBars,rates_total-2);
   int si=rates_total-1-lb;
   if(si<1) si=1;
   for(int i=si;i<rates_total-1;i++)
     {
      double mv=close[i+1]-close[i];
      if(BufferBuyTrend[i] !=EMPTY_VALUE){tT++;if(mv>0)wT++;}
      if(BufferSellTrend[i]!=EMPTY_VALUE){tT++;if(mv<0)wT++;}
      if(BufferBuyRev[i]   !=EMPTY_VALUE){tR++;if(mv>0)wR++;}
      if(BufferSellRev[i]  !=EMPTY_VALUE){tR++;if(mv<0)wR++;}
     }
   string s1=(tT>0)?StringFormat("Trend:%.0f%%(%d)",(double)wT/tT*100,tT):"Trend:--";
   string s2=(tR>0)?StringFormat("Rev:%.0f%%(%d)",  (double)wR/tR*100,tR):"Rev:--";
   return s1+" | "+s2;
  }

//+------------------------------------------------------------------+
//|  Dashboard helpers                                                |
//+------------------------------------------------------------------+
void MakeLabel(const string name,const string txt,const int x,const int y,
               const color clr,const int sz=9,const string font="Arial")
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    InpDashCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name,OBJPROP_FONT,      font);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  sz);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetString(0, name,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,    true);
  }

void MakeRect(const string name,const int x,const int y,const int w,const int h)
  {
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,     InpDashCorner);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,      w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,      h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,    C'10,12,22');
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,      C'50,50,100');
   ObjectSetInteger(0,name,OBJPROP_WIDTH,      1);
   ObjectSetInteger(0,name,OBJPROP_BACK,       true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,     true);
  }

string PeriodStr()
  {
   switch(Period())
     {
      case PERIOD_M1: return "M1"; case PERIOD_M5: return "M5";
      case PERIOD_M15:return "M15";case PERIOD_M30:return "M30";
      case PERIOD_H1: return "H1"; case PERIOD_H4: return "H4";
      default: return "??";
     }
  }

//+------------------------------------------------------------------+
//|  CreateDashboard                                                  |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   int x=InpDashX,y=InpDashY;
   MakeRect(g_pfx+"bg",x-6,y-6,285,290);
   MakeLabel(g_pfx+"title","  QUANTUM SCALPER PRO v3",x,y,clrGold,10,"Arial Bold");
   y+=20; MakeLabel(g_pfx+"s0","--------------------------------",x,y,C'50,50,100',8);
   y+=14; MakeLabel(g_pfx+"sym","Symbole  : "+_Symbol,x,y,clrSilver,9);
   y+=15; MakeLabel(g_pfx+"tf", "Timeframe: "+PeriodStr(),x,y,clrSilver,9);
   y+=16; MakeLabel(g_pfx+"s1","--------------------------------",x,y,C'50,50,100',8);
   y+=14; MakeLabel(g_pfx+"wrl","Win Rate ("+IntegerToString(InpWinRateBars)+" bougies):",x,y,clrLightSkyBlue,9,"Arial Bold");
   y+=16; MakeLabel(g_pfx+"wrv","Calcul...",x,y,clrYellow,10,"Arial Bold");
   y+=20; MakeLabel(g_pfx+"s2","--------------------------------",x,y,C'50,50,100',8);
   y+=14; MakeLabel(g_pfx+"l1t","LOGIQUE 1 - TREND",x,y,clrDodgerBlue,9,"Arial Bold");
   y+=15; MakeLabel(g_pfx+"alv","ALMA   : --",x,y,clrSilver,9);
   y+=15; MakeLabel(g_pfx+"rvv","RVOL   : --",x,y,clrSilver,9);
   y+=15; MakeLabel(g_pfx+"rsv","RSI    : --",x,y,clrSilver,9);
   y+=18; MakeLabel(g_pfx+"s3","--------------------------------",x,y,C'50,50,100',8);
   y+=14; MakeLabel(g_pfx+"l2t","LOGIQUE 2 - REVERSAL",x,y,clrLime,9,"Arial Bold");
   y+=15; MakeLabel(g_pfx+"swv","Pivot  : --",x,y,clrSilver,9);
   y+=15; MakeLabel(g_pfx+"ptv","Pattern: --",x,y,clrSilver,9);
   y+=18; MakeLabel(g_pfx+"s4","--------------------------------",x,y,C'50,50,100',8);
   y+=14; MakeLabel(g_pfx+"ses","Session: --",x,y,clrSilver,9);
   y+=18; MakeLabel(g_pfx+"ver","v3.0 | Trend+Reversal | XAUUSD",x,y,C'60,60,80',8);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//|  UpdateDashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(const int rates_total,const datetime &time[],
                     const double &open[],const double &close[],
                     const double &high[],const double &low[],
                     const long &tick_volume[])
  {
   int last=rates_total-1;
   if(last<4) return;

   // Win Rate
   string wr=CalcWinRate(rates_total,close);
   ObjectSetString(0, g_pfx+"wrv",OBJPROP_TEXT, wr);
   ObjectSetInteger(0,g_pfx+"wrv",OBJPROP_COLOR,clrYellow);

   // ALMA
   double av=BufferALMA[last],sl=BufferSlope[last];
   string aS=(close[last]>av&&sl>0)?"[UP]":(close[last]<av&&sl<0)?"[DOWN]":"[FLAT]";
   color  aC=(aS=="[UP]")?clrLimeGreen:(aS=="[DOWN]")?clrOrangeRed:clrYellow;
   ObjectSetString(0, g_pfx+"alv",OBJPROP_TEXT,StringFormat("ALMA(%d): %.2f  %s",InpALMA_Period,av,aS));
   ObjectSetInteger(0,g_pfx+"alv",OBJPROP_COLOR,aC);

   // RVOL
   long tvols[];
   if(CopyTickVolume(_Symbol,PERIOD_CURRENT,1,InpRVOL_Period+1,tvols)>0)
     {
      int sz=ArraySize(tvols); double vs=0;
      for(int v=0;v<sz-1;v++) vs+=(double)tvols[v];
      double va=vs/(sz-1),cur=(double)tvols[sz-1];
      double rv=(va>0)?cur/va:0;
      string rS=(rv>=InpRVOL_Mult)?"[ACTIF]":"[FAIBLE]";
      color  rC=(rv>=InpRVOL_Mult)?clrLimeGreen:clrOrangeRed;
      ObjectSetString(0, g_pfx+"rvv",OBJPROP_TEXT,StringFormat("RVOL: %.2fx / %.1fx  %s",rv,InpRVOL_Mult,rS));
      ObjectSetInteger(0,g_pfx+"rvv",OBJPROP_COLOR,rC);
     }

   // RSI
   if(BufferRSI[last]!=EMPTY_VALUE&&BufferRSISig[last]!=EMPTY_VALUE)
     {
      double rV=BufferRSI[last],sV=BufferRSISig[last];
      string rS=(rV>InpRSI_OB)?"[SURCH.]":(rV<InpRSI_OS)?"[SURV.]":"[OK]";
      color  rC=(rV>InpRSI_OB||rV<InpRSI_OS)?clrOrangeRed:clrLimeGreen;
      ObjectSetString(0, g_pfx+"rsv",OBJPROP_TEXT,StringFormat("RSI(%d): %.1f | Sig: %.1f  %s",InpRSI_Period,rV,sV,rS));
      ObjectSetInteger(0,g_pfx+"rsv",OBJPROP_COLOR,rC);
     }

   // Pivot status
   bool swL=true,swH=true;
   for(int s=1;s<=InpSwingBars;s++)
     {
      if(last-s>=0){if(low[last] >=low[last-s]) swL=false; if(high[last]<=high[last-s]) swH=false;}
     }
   string swS=swL?"Swing LOW detect":swH?"Swing HIGH detect":"Aucun pivot";
   color  swC=swL?clrLime:swH?clrMagenta:clrSilver;
   ObjectSetString(0, g_pfx+"swv",OBJPROP_TEXT, "Pivot: "+swS);
   ObjectSetInteger(0,g_pfx+"swv",OBJPROP_COLOR,swC);

   // Pattern bougie
   double body=MathAbs(close[last]-open[last]);
   double hiS =high[last]-MathMax(close[last],open[last]);
   double loS =MathMin(close[last],open[last])-low[last];
   string ptS ="Neutre";
   color  ptC =clrSilver;
   if(loS>2.0*body&&hiS<body)
     {ptS="Marteau (BUY)";  ptC=clrLime;}
   else if(hiS>2.0*body&&loS<body)
     {ptS="Etoile (SELL)";  ptC=clrMagenta;}
   else if(close[last]>open[last]&&last>0&&close[last-1]<open[last-1]&&
           close[last]>open[last-1]&&open[last]<close[last-1])
     {ptS="Engulf BUY";     ptC=clrLime;}
   else if(close[last]<open[last]&&last>0&&close[last-1]>open[last-1]&&
           close[last]<open[last-1]&&open[last]>close[last-1])
     {ptS="Engulf SELL";    ptC=clrMagenta;}
   ObjectSetString(0, g_pfx+"ptv",OBJPROP_TEXT, "Pattern: "+ptS);
   ObjectSetInteger(0,g_pfx+"ptv",OBJPROP_COLOR,ptC);

   // Session
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   int hr=dt.hour;
   string sS="Hors session [0h-8h bloque]"; color sC=clrOrangeRed;
   if(hr>=InpLondon_Start&&hr<InpLondon_End)
     {sS="LONDRES  [ACTIVE]";sC=clrLimeGreen;}
   else if(hr>=InpNewYork_Start&&hr<InpNewYork_End)
     {sS="NEW YORK [ACTIVE]";sC=clrLimeGreen;}
   ObjectSetString(0, g_pfx+"ses",OBJPROP_TEXT, "Session: "+sS);
   ObjectSetInteger(0,g_pfx+"ses",OBJPROP_COLOR,sC);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
//|  FIN - Quantum_Scalper_Pro v3.0                                  |
//+------------------------------------------------------------------+
