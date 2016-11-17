# -*- coding: utf-8 -*-
require 'nokogiri'
require 'open-uri'
require 'geocoder'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
options.query = [ ]
options.footage = 0

opt_parser = OptionParser.new do |opt|
  opt.banner = "Usage: craigslist_search [OPTIONS]"
  opt.separator  ""
  opt.separator  "Options"
  opt.on("-q", "--query QUERY", "which query you want to run") do |q|
    options.query << q
  end
  opt.on("-o", "--odo odometer", "max odometer reading") do |b|
    options.odometer = b
  end
  opt.on("-p", "--price PRICE", "max price") do |b|
    options.price = b
  end
  opt.on("-y", "--year year", "min model year") do |b|
    options.year = b
  end

  opt.on("-h","--help","help") do
    puts opt_parser
  end
end

opt_parser.parse!

max_price = options.price
max_odo = options.odometer.to_i
min_year = options.year.to_i
if !options.query.empty?
  query = options.query
else
  query = [ '' ] # 'cargo+van', 'passenger+van' ]
end

from_lat, from_lon = [ 40.768958,-73.9007302 ]

Geocoder.configure(:units => :mi )

print <<-header
    <html>

      <head>

        <link rel="stylesheet" href="http://tablesorter.com/themes/blue/style.css" type="text/css" media="print, projection, screen" />
        <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.8.0/jquery.min.js"></script>
        <script type="text/javascript" src="http://tablesorter.com/__jquery.tablesorter.min.js"></script>
        <script src="https://maps.googleapis.com/maps/api/js?v=3.exp&sensor=false"></script>

        <script type="text/javascript">
          $(document).ready(function() {
            $("#myTable").tablesorter();
          });
        </script>
        <style>
            table.tablesorter {
              font-size: 12pt;
            }
        </style>
      </head>

      <body>

    <div>Price: #{max_price}, Odometer: #{max_odo}, Query: #{query}</div>
    <table id="myTable" class="tablesorter">
    <thead>
    <tr>
        <th>#</th>
        <th>Date</th>
        <th>Title</th>
        <th>Price</th>
        <th>Odometer</th>
        <th>Year</th>
        <th>Image</th>
        <th>Map</th>
    </tr>
    </thead>
    <tbody>
header

post_ids = {}
i = 1
postNumber = 0
query.each do |q|
  [ 0, 1, 2, 3, 4, 5 ].each do |skip|
    url = "http://newyork.craigslist.org/search/cto?s=#{skip}00&query=#{q}&hasPic=1&max_auto_miles=#{max_odo}&max_price=#{max_price}&nearbyArea=168&nearbyArea=170&nearbyArea=249&nearbyArea=250&nearbyArea=349&nearbyArea=561&postal=11105&searchNearby=2&search_distance=100&auto_bodytype=12"
    printf "<!-- url: %s, postNumber: %d --> \n", url, postNumber
    doc = Nokogiri::HTML(open(url))

    ####
    # Search for nodes by css
    doc.css('li.result-row').each do |p|
      postNumber = postNumber + 1
      link = p.css('.result-info a')[0]
      img = p.css('a.result-image')[0]['data-ids'].split(',')[0]
      loc = p.css('.pnr small').text

      #next if options.location and !loc.downcase.include? options.location

      title = link.text
      
      if (link['href'] =~ /\/\//)
        url = 'http:' + link['href']
      else
        url = 'http://newyork.craigslist.org' + link['href']
      end

      if post_ids[img]
        printf "<!-- skipped: duplicate %s\n", url
      end

      post_ids[img] = 1
      if img
        img = img.split(':')[1]
      end
      exclude_models_regex = /Town\s*&\s*country|Chevy\s+Venture|windstar|Pontiac\s+Transport|mazda\s+mpv|chrysler\s+town|dodge\s+cara?van|Honda\s+Odyssey|Pontiac\s+Montana|Kia\s+Sedona|toyota\s+sienna|Chevy\s+uplander|grand\s+caravan|nissan\s+quest|minivan|mini\s+van/i
      if exclude_models_regex.match(title)
        printf "<!-- skipped: exclude regex match: %s-->\n", url
        next
      end

      date = p.css('time.result-date')[0]['datetime']
      price = p.css('span.result-price')[0].text
      if price =~ /\$/
        price = price.gsub(/\$/, '')
      end

#      dist = Geocoder::Calculations.distance_between([ from_lat, from_lon ], [ lat, lon ] )
#      next if dist > 15 and lat != 0 and lon != 0

      post = Nokogiri::HTML(open(url))

      map = post.css('#map')[0]
      if map 
        lat = map['data-latitude'].to_f
        lon = map['data-longitude'].to_f
      else
        lat = 0
        lon = 0
      end

      mileage = 0
      attrs = ''
      for span in post.css('p.attrgroup span') do 
         if span.text =~ /odometer:\s+(\d+)/
           mileage = $1.to_i
         end
         attrs += ' ' + span.text
      end

      if mileage < 1000
        mileage *= 1000
      end

      if mileage > max_odo
        printf "<!-- skipped: mileage: %s-->\n", url
        next
      end

      description = post.css('#postingbody')[0]
      if description
        description = q + "<br/>" + description.text.gsub(/QR Code Link to This Post/, "")
      end

      if exclude_models_regex.match(description)
        printf "<!-- skipped: exclude regex match: %s-->\n", url
        next
      end

      if title =~ /\b(19|20)(\d{2})\b/
        year = $1 + $2
      elsif description =~ /\b(19|20)(\d{2})\b/
        year = $1 + $2
      elsif attrs =~ /\b(19|20)(\d{2})\b/
        year = $1 + $2
      else
        year = '3000'
      end
      
      if year.to_i < min_year;
        printf "<!-- skipped: min year: %s-->\n", url
        next
      end

      printf('<tr>
            <td>%d</td>
            <td>%s</td>
            <td><p><a href="%s">%s</a></p><p>%s</p></td>
            <td>%s</td><td>%s</td><td>%s</td>
            <td><img src="http://images.craigslist.org/%s_300x300.jpg"></td>
            <td><img src="http://maps.googleapis.com/maps/api/staticmap?center=%f,%f&zoom=11&size=300x300&sensor=false&markers=color:blue%%7Clabel:X%%7C%f,%f"></td>
          </tr>
         ', i, date, url, title, description, price, mileage, year, img, lat, lon, lat, lon)
      i = i + 1
    end
  end
end

print <<-footer
</tbody>
</body>
</html>
footer
