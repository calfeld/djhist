#!ruby

require 'time'

# Radius of circles for each dance.
RADIUS = 2
# For each day, color circles as follow in order of most common recording used.
SERIES_COLORS = ['black', 'blue', 'green', 'red', 'orange', 'darkblue', 'darkgreen', 'darkred', 'darkorange']
# Color for name of dance.
LEGEND_COLOR = 'lightgray'

# Height and width of each svg.
HEIGHT = 60
WIDTH = 1000
# Where name of dance ends and graph starts.
OFFSET = 200

# Start and end of x axis.
S = Time.new(2021, 1, 1, 0, 0, 0)
E = Time.new(2026, 1, 1, 0, 0, 0)

# When do we dance in seconds since midnight.
START_HOUR = 19*60*60
END_HOUR = 22*60*60

# Note: There is "magic" going on around DST.  The way it works is that for a
# given _day_ and _time_ we calculate the seconds since beginning of the year of
# _day_ and then add the seconds since midnight of _time_.  The result is that
# every verticle line on the graph is START_HOUR to END_HOUR in local time for
# that day.

VIRTUALDJ = ENV['HOME'] + "/Documents/VirtualDJ"

# Convert time as XX:YY into seconds since midnight.
def ParseTime(s) 
  if s !~ /(\d+):(\d+)/
    throw "Bad Time"
  end

  $1.to_i * 60 * 60 + $2.to_i * 60
end

# Math

def i(b, e, t)
  b*(1-t) + e*t
end

# Projects v in [b1, e1] onto [b2, e2]
def project(v, b1, e1, b2, e2)
  i(b2, e2, (v - b1).to_f/(e1 - b1))
end

# SVG output

def svg_text(svg, s, x, y) 
  svg.puts "<text x='#{x}' y='#{y}'>"
  svg.puts s
  svg.puts "</text>"
end

def svg_line(svg, x1, y1, x2, y2, stroke = LEGEND_COLOR)
  svg.puts "<line x1='#{x1}' y1='#{y1}' x2='#{x2}' y2='#{y2}' stroke='#{stroke}'/>"
end

def svg_circle(svg, cx, cy, r, color)
  svg.puts "<circle cx='#{cx}' cy='#{cy}' r='#{r}' stroke='#{color}' fill='#{color}'/>"
end

def svg_header(svg, viewbox)
  svg.puts "<svg viewBox='#{viewbox}' width='100%' height='100%' xmlns='http://www.w3.org/2000/svg'>"
end

def svg_footer(svg)
  svg.puts "</svg>"
end

# Draw

# Draw the n, title, and grey lines.  Note that title here is strictly for what
# appears.  It is possible to plot multiple series on the same graph.  See
# PlotSeries.
def PlotGraph(svg, title, n)
  # Plot name and count
  svg_text svg, "#{n} #{title}", 0, HEIGHT/2
  
  # Plot horizontal lines for 7, 8, 9, and 10 PM
  [7, 8, 9, 10].each do |t|
    y = project(t, 7, 10, 0, HEIGHT)
    svg_line svg, OFFSET, y, WIDTH, y
  end

  # Plot verticle lines for each year
  years = E.year - S.year
  (0..years).each do |n|
    x = project(n, 0, years, OFFSET, WIDTH)
    svg_line svg, x, 0, x, HEIGHT
  end
end

# Plot a series with the nth color.
def PlotSeries(svg, series, n)
  color = SERIES_COLORS[n]

  series.each do |day, time|
    x = project(day.to_i, S.to_i, E.to_i, OFFSET, WIDTH)
    y = project(time, START_HOUR, END_HOUR, 0, HEIGHT)
    next if y < 0

    svg_circle svg, x, y, RADIUS, color
  end
end

# Handle escapes
def deescape(s)
  result = s.gsub(/&apos;/, '\'').gsub(/&amp;/, "&")
  if result =~ /&(.+);/
    STDERR.puts "Unhandled escape: #{result}"
    exit 1
  end
  result
end

# Database Parsing

# Parse a line of metadata.
def Parse(s) 
  result = {}
  s.scan(/<(?<tag>.+?)>(?<value>.+)<\/\k<tag>>/) do |data|
    tag, value = data
    result[tag] = value
  end
  result
end

# Global mapping filepath to map of tag to value.
$Tags = Hash.new {|h,k| h[k] = {}}

# Parse database.xml
filepath = nil
File.open(VIRTUALDJ + "/database.xml", "r").each do |line|
  if line =~ /<Song FilePath="(.+?)"/
    filepath = deescape($1)
  elsif line =~ /<Tags/
    line.scan(/(\w+?)="(.+?)"/) do |key, value|
      $Tags[filepath][key] = value
    end
  end
end

# For a given _recording_ we need to figure out what _dance_ it is for.  If
# User2 is specified for the recording, then use that.  If it is not, then use
# the Title or if that is missing, the filename.  In both of the latter cases,
# do some hacks to remove common variations, such as + to denote a longer 
# recording.

# Hacked on Title or filename of path.
def Title(path)
  if !$Tags[path]
    STDERR.puts "Error finding title of #{path}"
    exit 1
  end
  raw = $Tags[path]['Title'] || File.basename(path, File.extname(path))
  raw.gsub!(/\(.+\)/, '')
  raw.gsub!(/\[.+\]/, '')
  raw.gsub!(/\d+$/, '') if raw !~ /Passu|Lisu/
  raw.gsub!(/\+/, '')
  raw.strip!
  raw.gsub!(/\d+$/, '') if raw !~ /Passu|Lisu/
  raw = deescape(raw)
  if raw !~ /A-Z/
    raw = raw.split(" ").map {|words| words.capitalize}.join(" ")
  end
  raw
end

# The dance we do for the path (see comment above).
def Dance(path)
  if !$Tags[path]
    STDERR.puts "Error finding tags of #{path}"
    exit 1
  end
  # Can be nil
  $Tags[path]['User2']
end


# Load the entire history into $Series.  
# $Series is keyed by the song file and contains an array of [day, time]
# where time is seconds since midnight local time (see note above).

$Series = Hash.new {|h,k| h[k] = []}

Dir.glob(VIRTUALDJ + "/History/**/*.m3u").each do |path|
  puts path
  day = File.basename(path, '.m3u')
  metadata = nil
  File.open(path, 'r').each_line do |line|
    if line =~ /^#EXTVDJ:/
      metadata = Parse(line)
    else
      file = line.chomp
      $Series[file] << [Time.parse(day), ParseTime(metadata['time'])]
    end
  end
end

# Now we merge all songs that are for the same dance.
# MultiSeries is indexed by dance name and contains an array of series, i.e.,
# an array of array of [day, time].

MultiSeries = {}
$Series.each do |path, series|
  key = Dance(path) || Title(path)
  puts "#{File.basename(path)} => #{key}"
  MultiSeries[key] ||= []
  MultiSeries[key] << series
end

# For each dance, order the series for each recording by most played to least
# played.
MultiSeries.each_key do |k|
  MultiSeries[k].sort! {|a, b| b.size <=> a.size}
end

# Now sort all dances in order of least played to most played.
all = MultiSeries.keys
all.sort! do |a,b|
  a_n = MultiSeries[a].sum(0) {|x| x.size}
  b_n = MultiSeries[b].sum(0) {|x| x.size}
  b_n <=> a_n
end

File.open("index.html", "w") do |index|
  i = 0
  all.each do |title|
    multiseries = MultiSeries[title]
    n = multiseries.sum(0) {|x| x.size}
    # Any dance done only once or twice will be placed in a single graph at the
    # end.
    break if n <= 2
    i += 1
    
    puts "#{i} #{n} #{title}"

    File.open("#{i}.svg", "w") do |svg|
      svg_header svg, "0, 0, #{WIDTH}, #{HEIGHT}"
      PlotGraph(svg, title, n)
      
      j = 0
      multiseries.each do |series|
        PlotSeries(svg, series, j)
        j += 1
      end
      svg_footer svg
    end
    
    index.puts "<p><img src=\"#{i}.svg\"/></p>"
  end

  index.puts "<p><img src=\"less_than_three.svg\"/></p>"
end

# Find total of dances played at most twice.
total = 0
all.each do |title|
  multiseries = MultiSeries[title]
  n = multiseries.sum(0) {|x| x.size}
  next if n > 2
  total += n
end

# Single graph for all these.
File.open("less_than_three.svg", "w") do |svg|
  svg_header svg, "0, 0, #{WIDTH}, #{HEIGHT}"    
  PlotGraph(svg, "less than three", total)

  all.each do |title|
    multiseries = MultiSeries[title]
    n = multiseries.sum(0) {|x| x.size}
    next if n > 2
    
    puts "less than three #{title}"

    multiseries.each do |series|
      PlotSeries(svg, series,0)
    end
  end
  svg_footer svg
end


# Output every dance and how many total datapoints there are.
grand_total = 0  
all.each do |title|
  multiseries = MultiSeries[title]
  grand_total += multiseries.sum(0) {|x| x.size}
end

puts MultiSeries.keys.sort.join("\n")

puts grand_total

