import { useEffect, useRef } from 'react';
import * as echarts from 'echarts/core';
import { BarChart, LineChart } from 'echarts/charts';
import { GridComponent, LegendComponent, TooltipComponent, MarkLineComponent } from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import { fmtMoney } from './format';

echarts.use([BarChart, LineChart, GridComponent, LegendComponent, TooltipComponent, MarkLineComponent, CanvasRenderer]);

/** Colores de las series (paleta de la UI). */
export const CHART = {
  text: '#8ea3b8',
  grid: 'rgba(140,180,220,0.12)',
  accent: '#ffcb3d',
  good: '#4ade80',
  bad: '#f87171',
  info: '#60a5fa',
  violet: '#a78bfa',
  dim: '#64748b',
};

/** Ejes y estilo comunes para gráficas sobre fondo oscuro. */
export function baseOption(categories: string[], opts: { money?: boolean; percent?: boolean; unit?: string } = {}): echarts.EChartsCoreOption {
  const fmt = opts.money ? (v: number) => fmtMoney(v).replace('US$ ', '') : opts.percent ? (v: number) => `${Math.round(v * 100)} %` : (v: number) => `${v}${opts.unit ?? ''}`;
  return {
    backgroundColor: 'transparent',
    animation: false,
    textStyle: { color: CHART.text, fontFamily: 'inherit' },
    grid: { left: 56, right: 16, top: 34, bottom: 28 },
    legend: { top: 0, textStyle: { color: CHART.text }, itemWidth: 12, itemHeight: 8 },
    tooltip: {
      trigger: 'axis', backgroundColor: '#0f1d2e', borderColor: 'rgba(140,180,220,0.3)', textStyle: { color: '#e6eef7' },
      valueFormatter: (v: unknown) => (typeof v === 'number' ? (opts.money ? fmtMoney(v) : opts.percent ? `${(v * 100).toFixed(1)} %` : `${v.toLocaleString('es-PA', { maximumFractionDigits: 1 })}${opts.unit ?? ''}`) : String(v)),
    },
    xAxis: { type: 'category', data: categories, axisLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text, hideOverlap: true } },
    yAxis: { type: 'value', splitLine: { lineStyle: { color: CHART.grid } }, axisLabel: { color: CHART.text, formatter: fmt } },
  };
}

export function Chart({ option, height = 220 }: { option: echarts.EChartsCoreOption; height?: number }) {
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<echarts.ECharts | null>(null);
  useEffect(() => {
    const c = echarts.init(el.current!, undefined, { renderer: 'canvas' });
    chart.current = c;
    const ro = new ResizeObserver(() => c.resize());
    ro.observe(el.current!);
    return () => { ro.disconnect(); c.dispose(); chart.current = null; };
  }, []);
  useEffect(() => { chart.current?.setOption(option, { notMerge: true, lazyUpdate: true }); }, [option]);
  return <div ref={el} style={{ width: '100%', height }} />;
}
