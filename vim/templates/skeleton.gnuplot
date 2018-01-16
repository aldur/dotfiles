#!/usr/bin/env gnuplot

set terminal postscript eps color enhanced lw 2 font "GillSans-Light"
set size 1.2,0.90

# Line style for axes
set style line 80 lt 0
set style line 80 lt rgb "#808080"

# Line style for grid
set style line 81 lt 3  # dashed
set style line 81 lt rgb "#808080" lw 0.5  # grey

set grid back linestyle 81
set grid noxtics
set grid ytics

# Remove border on top and right. These borders are useless and make it harder to see plotted lines near the border.
# Also, put it in grey; no need for so much emphasis on a border.
set border 3 back linestyle 80
set border 4 back linestyle 80
set xtics rotate nomirror
set ytics nomirror

# Select clustered histogram data
set style data histogram
set style histogram clustered gap 1

# Give the bars a plain fill pattern, and draw a solid line around them.
set style fill solid noborder
set cbrange [0:21]
unset colorbox
set key horiz
set key top center
set key textcolor rgb "#808080"

# Set the line styles
set style line 1 lt 1
set style line 2 lt 1
set style line 3 lt 1
set style line 4 lt 1
set style line 5 lt 1
set style line 6 lt 1
set style line 7 lt 1

set style line 1 lt rgb "#d41243" lw 1 pt 7 ps 0.5
set style line 2 lt rgb "#8ec127" lw 1 pt 7 ps 0.5

set style increment user

set auto x
set yrange [0:*]
