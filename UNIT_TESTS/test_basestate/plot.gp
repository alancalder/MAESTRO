set term post eps color
set output 'plot.eps'

set multiplot;

set size 0.5, 0.33;

set xlabel "x";

set logscale y

set style line 1  lw 5

set origin 0.0, 0.0
set xrange [0:2.5e8]
set yrange [1e-5:1e10]
set ylabel "density";
plot 'base.orig'                      using 1:2 with lines ls 1,\
     'base.new'                       using 1:2 with lines ls 2,\
     'compressible-1.e16-t=10.00.out' using 1:2 with lines ls 3;

set origin 0.0, 0.33
set xrange[0:2.5e8]
set yrange[4e6:1e10]
set ylabel "temp";
plot 'base.orig'                      using 1:3 with lines ls 1,\
     'base.new'                       using 1:3 with lines ls 2,\
     'compressible-1.e16-t=10.00.out' using 1:3 with lines ls 3;

set origin 0.0, 0.66
set xrange[0:2.5e8]
set yrange[1e13:1e28]
set ylabel "pres";
plot 'base.orig'                      using 1:4 with lines ls 1,\
     'base.new'                       using 1:4 with lines ls 2,\
     'compressible-1.e16-t=10.00.out' using 1:4 with lines ls 3;

unset multiplot;
set term x11;
